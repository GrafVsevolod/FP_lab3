defmodule Lab3.Stream.Engine do
  @moduledoc """
  Потоковый движок интерполяции (отдельный процесс через spawn).

  Получает точки сообщениями и печатает рассчитанные точки по мере готовности.

  Сообщения:
    {:point, {x, y}} — очередная входная точка (x по возрастанию)
    :eof             — конец входного потока (движок допечатывает хвост и завершает работу)

  После завершения отправляет родителю:
    {:done, pid()}
  """

  alias Lab3.Alg.Linear
  alias Lab3.Alg.Newton

  @type point :: {number(), number()}

  @spec start(keyword()) :: pid()
  def start(opts) do
    spawn(fn -> loop(init_state(opts)) end)
  end

  defp init_state(opts) do
    %{
      parent: Keyword.fetch!(opts, :parent),
      step: Keyword.fetch!(opts, :step),
      algs: Keyword.fetch!(opts, :algs),
      sep: Keyword.get(opts, :sep, " "),
      window: Keyword.get(opts, :window, 4),

      # linear state
      prev: nil,
      next_x_linear: nil,
      last_emitted_x_linear: nil,

      # newton state
      buf: [],
      next_x_newton: nil,
      last_emitted_x_newton: nil
    }
  end

  defp loop(state) do
    receive do
      {:point, {x, y} = p} ->
        state =
          state
          |> push_buf(p)
          |> handle_linear_point({x, y})
          |> handle_newton_step()

        loop(state)

      :eof ->
        state =
          state
          |> emit_last_knot_linear()
          |> emit_tail_newton()

        send(state.parent, {:done, self()})
        :ok

      _ ->
        loop(state)
    end
  end

  # ----------------------------
  # Buffer (for Newton)
  # ----------------------------
  defp push_buf(%{buf: buf, window: w} = state, p) do
    new_buf = trim_left(buf ++ [p], w)
    %{state | buf: new_buf}
  end

  defp trim_left(list, w) when length(list) <= w, do: list
  defp trim_left([_ | t], w), do: trim_left(t, w)

  # ----------------------------
  # Linear
  # ----------------------------
  defp handle_linear_point(%{prev: nil} = state, {x, _y} = p) do
    %{state | prev: p, next_x_linear: x, last_emitted_x_linear: nil}
  end

  defp handle_linear_point(%{prev: prev} = state, cur) do
    state
    |> emit_segment_linear(prev, cur)
    |> then(fn s -> %{s | prev: cur} end)
  end

  defp emit_segment_linear(%{next_x_linear: nx} = state, {x0, _y0} = a, {x1, _y1} = b) do
    step = state.step
    nx = if is_nil(nx), do: x0, else: nx
    nx = if nx < x0, do: x0, else: nx

    if nx > x1 do
      %{state | next_x_linear: nx}
    else
      {state2, nx2} = emit_points_linear(state, a, b, nx, step)
      %{state2 | next_x_linear: nx2}
    end
  end

  defp emit_points_linear(state, a, b, nx, step) do
    {x1, _} = b

    if nx <= x1 + 1.0e-12 do
      state = emit_linear_at(state, a, b, nx)
      emit_points_linear(state, a, b, nx + step, step)
    else
      {state, nx}
    end
  end

  defp emit_linear_at(state, a, b, x) do
    if :linear in state.algs do
      y = Linear.interp(a, b, x)
      print_line(state, "linear", x, y)
    end

    %{state | last_emitted_x_linear: x}
  end

  defp emit_last_knot_linear(%{prev: nil} = state), do: state

  defp emit_last_knot_linear(%{prev: {x_last, y_last}, last_emitted_x_linear: lx} = state) do
    cond do
      :linear not in state.algs ->
        state

      is_nil(lx) ->
        print_line(state, "linear", x_last, y_last)
        %{state | last_emitted_x_linear: x_last}

      abs(lx - x_last) > 1.0e-9 ->
        print_line(state, "linear", x_last, y_last)
        %{state | last_emitted_x_linear: x_last}

      true ->
        state
    end
  end

  # ----------------------------
  # Newton (streaming)
  #
  # Простой и “проверяемый” режим:
  # - начинаем печатать, когда buf набрал window точек
  # - печатаем все x от next_x_newton до x_last(buf) (в порядке возрастания)
  # - next_x_newton увеличиваем на step
  # ----------------------------
  defp handle_newton_step(%{buf: buf} = state) do
    if :newton in state.algs and length(buf) >= 2 do
      maybe_emit_newton(state)
    else
      state
    end
  end

  defp maybe_emit_newton(%{buf: buf, window: w} = state) do
    # ждём пока окно набралось (как в примере с n=4)
    if length(buf) < w do
      state
    else
      [{x_first, _} | _] = buf
      {x_last, _} = List.last(buf)

      nx =
        case state.next_x_newton do
          nil -> x_first
          v -> v
        end

      {state2, nx2} = emit_points_newton(state, buf, nx, state.step, x_last)
      %{state2 | next_x_newton: nx2}
    end
  end

  defp emit_points_newton(state, points, nx, step, x_last) do
    if nx <= x_last + 1.0e-12 do
      state = emit_newton_at(state, points, nx)
      emit_points_newton(state, points, nx + step, step, x_last)
    else
      {state, nx}
    end
  end

  defp emit_newton_at(state, points, x) do
    if :newton in state.algs do
      y = Newton.interp(points, x)
      print_line(state, "newton", x, y)
    end

    %{state | last_emitted_x_newton: x}
  end

  # На EOF для Ньютона просто добиваем “хвост” по последнему окну (если оно было)
  defp emit_tail_newton(%{buf: buf} = state) do
    if :newton in state.algs and length(buf) >= 2 do
      # если окно меньше window (например данных мало) — всё равно можно интерполировать по тому, что есть
      [{x_first, _} | _] = buf
      {x_last, _} = List.last(buf)

      nx =
        cond do
          is_nil(state.next_x_newton) -> x_first
          true -> state.next_x_newton
        end

      {state2, nx2} = emit_points_newton(state, buf, nx, state.step, x_last)
      %{state2 | next_x_newton: nx2}
    else
      state
    end
  end

  # ----------------------------
  # Output formatting
  # ----------------------------
  defp print_line(%{sep: sep}, tag, x, y) do
    IO.puts("#{tag}: #{fmt(x)}#{sep}#{fmt(y)}")
  end

  defp fmt(n) when is_integer(n), do: Integer.to_string(n)

  defp fmt(n) when is_float(n) do
    :erlang.float_to_binary(n, decimals: 10)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp fmt(n), do: to_string(n)
end
