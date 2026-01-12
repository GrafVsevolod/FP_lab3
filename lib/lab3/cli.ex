defmodule Lab3.CLI do
  @moduledoc """
  CLI: парсит аргументы, запускает Engine и читает stdin -> Engine.
  """

  alias Lab3.Stream.Engine
  alias Lab3.IO.Parser

  @spec main([String.t()]) :: :ok
  def main(argv) do
    opts = parse_args(argv)

    if opts.help do
      IO.puts(help_text())
      :ok
    else
      engine = Engine.start(step: opts.step, algs: opts.algs, sep: opts.out_sep)

      IO.stream(:stdio, :line)
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.each(fn line ->
        case Parser.parse_line(line, opts.in_sep) do
          {:ok, point} -> send(engine, {:point, point})
          {:error, _} -> :ok
        end
      end)

      send(engine, :eof)
      :ok
    end
  end

  defp parse_args(argv) do
    {parsed, _, _} =
      OptionParser.parse(argv,
        strict: [
          help: :boolean,
          linear: :boolean,
          newton: :boolean,
          step: :float,
          n: :integer,
          window: :integer,
          sep: :string,
          in_sep: :string
        ],
        aliases: [h: :help, n: :window]
      )

    algs =
      []
      |> add_alg(parsed[:linear], :linear)
      |> add_alg(parsed[:newton], :newton)

    %{
      help: parsed[:help] || false,
      algs: if(algs == [], do: [:linear], else: algs),
      step: parsed[:step] || 0.5,
      out_sep: normalize_out_sep(parsed[:sep] || "space"),
      in_sep: normalize_in_sep(parsed[:in_sep] || "auto"),
      window: parsed[:window] || parsed[:n] || 4
    }
  end

  defp add_alg(list, true, alg), do: list ++ [alg]
  defp add_alg(list, _, _), do: list

  defp normalize_out_sep("space"), do: " "
  defp normalize_out_sep("semicolon"), do: ";"
  defp normalize_out_sep("tab"), do: "\t"
  defp normalize_out_sep(other) when other in [" ", ";", "\t"], do: other
  defp normalize_out_sep(_), do: " "

  defp normalize_in_sep("auto"), do: :auto
  defp normalize_in_sep("space"), do: " "
  defp normalize_in_sep("semicolon"), do: ";"
  defp normalize_in_sep("tab"), do: "\t"
  defp normalize_in_sep(other), do: other

  defp help_text do
    """
    lab3 — streaming interpolation (FP)

    Usage:
      cat data.csv | ./lab3 --linear --step 0.7
      cat data.csv | ./lab3 --newton -n 4 --step 0.5
      cat data.csv | ./lab3 --linear --newton -n 4 --step 0.5

    Input (stdin):
      Lines with two numbers: "x y" or "x;y" or "x\\ty"
      Points must be sorted by increasing x

    Output (stdout):
      algorithm: x y

    Options:
      --help            Show this help
      --linear          Enable linear interpolation
      --newton          Enable Newton interpolation (will be added next)
      -n, --window N    Window size for Newton (e.g. 4)
      --step S          Output discretization step (e.g. 0.5)
      --sep SEP         Output separator: space | semicolon | tab (default: space)
      --in-sep SEP      Input separator: auto | space | semicolon | tab (default: auto)
    """
  end
end
