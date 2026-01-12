defmodule Lab3.Alg.Linear do
  @moduledoc """
  Линейная интерполяция на отрезке между двумя точками.
  """

  @type point :: {number(), number()}

  @spec interp(point(), point(), number()) :: number()
  def interp({x0, y0}, {x1, y1}, x) when x1 != x0 do
    t = (x - x0) / (x1 - x0)
    y0 + t * (y1 - y0)
  end

  def interp({_x0, y0}, {_x1, _y1}, _x), do: y0
end
