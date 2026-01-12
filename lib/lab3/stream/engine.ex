defmodule Lab3.Stream.Engine do
  @moduledoc """
  Потоковый движок интерполяции (процесс).
  Получает точки сообщениями и печатает рассчитанные точки по мере готовности.
  """

  alias Lab3.Alg.Linear

  @type point :: {number(), number()}

  @spec start(keyword()) :: pid()
  def start(opts) do
    spawn(fn -> loop(init_state(opts)) end)
  end

  defp init_state(opts) do
    %{
      step: Keyword.fetch!(opts, :step),
      # например [:linear]
      algs: Keyword.fetch!(opts, :algs),
      sep: Keyword.get(opts, :sep, " "),
      prev: nil,
      next_x: nil,
      last_emitted_x: nil
    }
  end

  defp loop(state) do
    receive do
      {:point, {x, _y} = p} ->
        state =
          case state.prev do
            nil ->
              # первая точка: готовим next_x = x0
              %{state | prev: p, next_x: x, last_emitted_x: nil}

            {_x0, _y0} = prev ->
              # пришла следующая точка -> у нас есть отрезок [prev, p]
              state
              |> emit_segment(prev, p)
              |> then(fn s ->
                # сдвигаем окно: prev становится текущей точкой
                %{s | prev: p}
              end)
          end

        loop(state)

      :eof ->
        # На EOF — гарантируем, что последняя "узловая" точка выведена (если есть)
        new_state = emit_last_knot(state)
        loop(new_state)

        # Можно послать подтверждение (если CLI захочет ждать)
        send(self(), :done)
        :ok

      _ ->
        loop(state)
    end
  end

  # Печатаем точки на отрезке [a,b] начиная с next_x, с шагом step.
  defp emit_segment(%{next_x: nx} = state, {x0, _y0} = a, {x1, _y1} = b) do
    step = state.step

    # Если nx не инициализирован (на всякий), стартуем с x0
    nx = if is_nil(nx), do: x0, else: nx

    {state, nx} =
      if nx < x0 do
        {%{state | next_x: x0}, x0}
      else
        {state, nx}
      end

    {state, nx} =
      cond do
        nx > x1 ->
          # уже ушли за сегмент — ничего не печатаем
          {state, nx}

        true ->
          # печатаем все nx <= x1 с шагом
          {state2, nx2} = emit_points(state, a, b, nx, step)
          {state2, nx2}
      end

    %{state | next_x: nx}
  end

  defp emit_points(state, a, b, nx, step) do
    {x1, _} = b

    if nx <= x1 + 1.0e-12 do
      state = emit_all_algs(state, a, b, nx)
      emit_points(state, a, b, nx + step, step)
    else
      {state, nx}
    end
  end

  defp emit_all_algs(state, a, b, x) do
    # пока делаем linear (Newton добавим дальше)
    if :linear in state.algs do
      y = Linear.interp(a, b, x)
      print_line(state, "linear", x, y)
    end

    %{state | last_emitted_x: x}
  end

  defp emit_last_knot(%{prev: nil} = state), do: state

  defp emit_last_knot(%{prev: {x_last, y_last}, last_emitted_x: lx} = state) do
    # если вообще ничего не печатали — печатаем узел
    cond do
      is_nil(lx) ->
        if :linear in state.algs do
          print_line(state, "linear", x_last, y_last)
        end

        %{state | last_emitted_x: x_last}

      abs(lx - x_last) > 1.0e-9 ->
        if :linear in state.algs do
          print_line(state, "linear", x_last, y_last)
        end

        %{state | last_emitted_x: x_last}

      true ->
        state
    end
  end

  defp print_line(%{sep: sep}, tag, x, y) do
    IO.puts("#{tag}: #{fmt(x)}#{sep}#{fmt(y)}")
  end

  defp fmt(n) when is_integer(n), do: Integer.to_string(n)

  defp fmt(n) when is_float(n) do
    # красиво и стабильно для отчёта/проверки
    :erlang.float_to_binary(n, decimals: 10)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp fmt(n), do: to_string(n)
end
