defmodule Lab3.Alg.Newton do
  @moduledoc """
  Интерполяция Ньютона по набору точек (разделённые разности).
  points: [{x, y}, ...] длины n (x должны быть различны).
  """

  @type point :: {number(), number()}

  @spec interp([point()], number()) :: number()
  def interp(points, x) when is_list(points) and length(points) >= 2 do
    xs = Enum.map(points, fn {xi, _yi} -> xi end)
    # [a0, a1, ..., a_{n-1}]
    coeffs = divided_differences(points)
    eval_newton(xs, coeffs, x)
  end

  # a_k = f[x0..xk]
  defp divided_differences(points) do
    ys = Enum.map(points, fn {_x, y} -> y end)
    xs = Enum.map(points, fn {x, _y} -> x end)
    n = length(points)

    # строим таблицу DD по слоям: каждый слой короче
    # layer0 = y0..y_{n-1}
    # layer1[i] = (layer0[i+1]-layer0[i])/(x_{i+1}-x_i)
    # ...
    layers =
      Enum.reduce(1..(n - 1), [ys], fn level, acc ->
        prev = hd(acc)

        next =
          for i <- 0..(n - level - 1) do
            (Enum.at(prev, i + 1) - Enum.at(prev, i)) /
              (Enum.at(xs, i + level) - Enum.at(xs, i))
          end

        [next | acc]
      end)
      |> Enum.reverse()

    # коэффициенты — первые элементы каждого слоя
    Enum.map(layers, fn layer -> hd(layer) end)
  end

  # P(x) = a0 + a1(x-x0) + a2(x-x0)(x-x1) + ...
  defp eval_newton(xs, coeffs, x) do
    {res, _prod} =
      Enum.reduce(Enum.with_index(coeffs), {0.0, 1.0}, fn {a, k}, {acc, prod} ->
        acc = acc + a * prod
        prod = prod * (x - Enum.at(xs, k))
        {acc, prod}
      end)

    res
  end
end
