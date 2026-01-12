defmodule Lab3.IO.Parser do
  @moduledoc "Парсер строк stdin в точки {x,y}."

  @type point :: {number(), number()}

  @spec parse_line(binary(), binary() | atom()) ::
          {:ok, point()} | :skip | {:error, term()}
  def parse_line(line, in_sep \\ :auto) do
    line = String.trim(line)

    cond do
      line == "" ->
        :skip

      true ->
        do_parse(line, in_sep)
    end
  end

  defp do_parse(line, :auto) do
    cond do
      String.contains?(line, ";") -> do_parse(line, "semicolon")
      String.contains?(line, "\t") -> do_parse(line, "tab")
      true -> do_parse(line, "space")
    end
  end

  defp do_parse(line, "space"), do: split_parse(line, ~r/\s+/)
  defp do_parse(line, "semicolon"), do: split_parse(line, ";")
  defp do_parse(line, "tab"), do: split_parse(line, "\t")

  defp split_parse(line, pattern) do
    parts =
      case pattern do
        %Regex{} -> String.split(line, pattern, trim: true)
        sep when is_binary(sep) -> String.split(line, sep, trim: true)
      end

    case parts do
      [xs, ys] ->
        with {x, ""} <- Float.parse(xs),
             {y, ""} <- Float.parse(ys) do
          {:ok, {x, y}}
        else
          _ -> {:error, :bad_number}
        end

      _ ->
        {:error, :bad_format}
    end
  end
end
