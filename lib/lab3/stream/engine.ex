defmodule Lab3.Stream.Engine do
  @moduledoc """
  Потоковый движок интерполяции (процесс через spawn).

  Получает точки сообщениями и печатает рассчитанные точки по мере готовности.

  Сообщения:
    {:point, {x, y}} — очередная входная точка (x строго по возрастанию)
    :eof             — конец входного потока (движок допечатывает хвост и завершает работу)

  По завершении (если parent задан) отправляет:
    {:done, pid()}
  """

  alias Lab3.Alg.Linear
  alias Lab3.Alg.Newton

  @type point :: {number(), number()}

  @spec start(keyword()) :: pid()
  def start(opts) do
    parent = Keyword.get(opts, :parent, nil)
    spawn(fn -> loop(init_state(Keyword.put(opts, :parent, parent))) end)
  end

  defp init_state(opts) do
    %{
      parent: Keyword.get(opts, :parent, nil),
      step: Keyword.fetch!(opts, :step),
      algs: Keyword.fetch!(opts, :algs),
      sep: Keyword.get(opts, :sep, " "),

      # Newton window size
      window: Keyword.get(opts, :window, 4),

      # input buffer (последние точки)
      buf: [],

      # для линейной
      prev: nil,
      next_x_linear: nil,
      last_out_linear: nil,

      # для newton
      next_x_newton: nil,
      last_out_newton: nil,
      newton_ready?: false
    }
  end

  # ----------------------------
  # Main loop
  # ----------------------------
  defp loop(state) do
    receive do
      {:point, {_x, _y} = p} ->
        state =
          state
          |> push_buf(p)
          |> handle_linear_point(p)
          |> handle_newton_point()

        loop(state)

      :eof ->
        state =
          state
          |> flush_linear_eof()
          |> flush_newton_eof()

        if state.parent, do: send(state.parent, {:done, self()})
        :ok

      _ ->
        loop(state)
    end
  end

  # ----------------------------
  # Buffer maintenance
  # ----------------------------
  defp push_buf(%{buf: buf, window: w} = state, p) do
    buf = buf ++ [p]
    buf = trim_left(buf, w)
    %{state | buf: buf}
  end

  defp trim_left(list, w) when length(list) <= w, do: list
  defp trim_left([_ | t], w), do: trim_left(t, w)

  # ----------------------------
  # Linear streaming: emits for each segment when 2 points available
  # ----------------------------
  defp handle_linear_point(%{prev: nil} = state, {x, _y} = p) do
    # первая точка: стартуем сетку с x0
    %{state | prev: p, next_x_linear: x, last_out_linear: nil}
  end

  defp handle_linear_point(%{prev: prev} = state, cur) do
    # есть сегмент [prev, cur] -> печатаем nx..x1
    state
    |> emit_segment_linear(prev, cur)
    |> then(fn s -> %{s | prev: cur} end)
  end

  defp emit_segment_linear(%{next_x_linear: nx} = state, {x0, _} = a, {x1, _} = b) do
    if :linear not in state.algs do
      state
    else
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
  end

  defp emit_points_linear(state, a, b, nx, step) do
    {x1, _} = b

    if nx <= x1 + 1.0e-12 do
      y = Linear.interp(a, b, nx)
      print_line(state, "linear", nx, y)
      state = %{state | last_out_linear: nx}
      emit_points_linear(state, a, b, nx + step, step)
    else
      {state, nx}
    end
  end

  defp flush_linear_eof(%{prev: nil} = state), do: state

  defp flush_linear_eof(%{prev: {x_last, y_last}, last_out_linear: lx} = state) do
    cond do
      :linear not in state.algs ->
        state

      is_nil(lx) ->
        print_line(state, "linear", x_last, y_last)
        %{state | last_out_linear: x_last}

      abs(lx - x_last) > 1.0e-9 ->
        print_line(state, "linear", x_last, y_last)
        %{state | last_out_linear: x_last}

      true ->
        state
    end
  end

  # ----------------------------
  # Newton streaming (windowed)
  #
  # Idea:
  # - when buf length < n -> not enough points, do nothing
  # - when buf length == n:
  #     first time => emit MANY points from x0..x_last (head)
  #     then for each new point (sliding window) emit a single "center" point
  # - on EOF: emit MANY points from last_center..x_last (tail)
  # ----------------------------
  defp handle_newton_point(state) do
    if :newton not in state.algs do
      state
    else
      n = state.window
      buf = state.buf

      cond do
        length(buf) < n ->
          state

        length(buf) == n and state.newton_ready? == false ->
          # first full window: emit from x0 to x_last
          {x0, _} = hd(buf)
          {x_last, _} = List.last(buf)

          nx = if is_nil(state.next_x_newton), do: x0, else: state.next_x_newton
          nx = if nx < x0, do: x0, else: nx

          {state2, nx2} = emit_range_newton(state, buf, nx, x_last)
          %{state2 | next_x_newton: nx2, newton_ready?: true}

        true ->
          # sliding: emit ONLY the center point for best accuracy
          emit_center_newton(state, buf)
      end
    end
  end

  defp emit_center_newton(state, buf) do
    # center x
    mid_idx = div(length(buf) - 1, 2)
    {x_mid, _} = Enum.at(buf, mid_idx)

    # we must advance monotonically: emit points on grid
    step = state.step
    nx = state.next_x_newton

    # if grid not init => start near x_mid rounded up to grid
    nx =
      cond do
        is_nil(nx) -> x_mid
        true -> nx
      end

    # ensure we emit at most one grid point near x_mid:
    # if nx is already beyond x_mid, nothing
    cond do
      nx > x_mid + 1.0e-12 ->
        state

      true ->
        y = Newton.interp(buf, nx)
        print_line(state, "newton", nx, y)
        %{state | last_out_newton: nx, next_x_newton: nx + step}
    end
  end

  defp flush_newton_eof(state) do
    if :newton not in state.algs do
      state
    else
      n = state.window
      buf = state.buf

      if length(buf) < n do
        state
      else
        {x_last, _} = List.last(buf)

        nx =
          cond do
            is_nil(state.next_x_newton) ->
              # if never emitted anything: start from first x
              {x0, _} = hd(buf)
              x0

            true ->
              state.next_x_newton
          end

        # tail: emit remaining points up to x_last
        emit_tail_newton(state, buf, nx, x_last)
      end
    end
  end

  defp emit_tail_newton(state, buf, nx, x_last) do
    if nx <= x_last + 1.0e-12 do
      y = Newton.interp(buf, nx)
      print_line(state, "newton", nx, y)
      emit_tail_newton(%{state | last_out_newton: nx}, buf, nx + state.step, x_last)
    else
      %{state | next_x_newton: nx}
    end
  end

  defp emit_range_newton(state, buf, nx, x_last) do
    if nx <= x_last + 1.0e-12 do
      y = Newton.interp(buf, nx)
      print_line(state, "newton", nx, y)
      emit_range_newton(%{state | last_out_newton: nx}, buf, nx + state.step, x_last)
    else
      {state, nx}
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
