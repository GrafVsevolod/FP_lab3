defmodule Lab3.CLI do
  @moduledoc """
  CLI: парсит аргументы, запускает Engine и поднимает Supervisor/Reader,
  который читает stdin потоково и шлёт точки в Engine.
  """

  alias Lab3.Stream.Engine

  @spec main([String.t()]) :: :ok
  def main(argv) do
    # Чтобы нормальный shutdown дочерних процессов не “ронял” CLI
    Process.flag(:trap_exit, true)

    opts = parse_args(argv)

    if opts.help do
      IO.puts(help_text())
      :ok
    else
      engine =
        Engine.start(
          step: opts.step,
          algs: opts.algs,
          sep: opts.out_sep,
          window: opts.window
        )

      {:ok, sup_pid} =
        Lab3.AppSupervisor.start_link(
          engine: engine,
          in_sep: opts.in_sep
        )

      wait_until_done(engine, sup_pid)
    end
  end

  defp wait_until_done(engine, sup_pid) do
    receive do
      {:done, ^engine} ->
        # останавливаем supervisor (если ещё жив)
        if Process.alive?(sup_pid), do: Process.exit(sup_pid, :normal)
        :ok

      {:EXIT, _from, :normal} ->
        # нормальное завершение — игнорируем
        wait_until_done(engine, sup_pid)

      {:EXIT, _from, :shutdown} ->
        # нормальное “дерево” завершилось — игнорируем
        wait_until_done(engine, sup_pid)

      {:EXIT, _from, {:shutdown, _}} ->
        wait_until_done(engine, sup_pid)

      {:EXIT, _from, reason} ->
        # если вдруг упало нештатно — можно вывести в stderr
        IO.puts(:stderr, "Process exit: #{inspect(reason)}")
        :ok
    after
      60_000 ->
        :ok
    end
  end

  # --------------------
  # Аргументы командной строки
  # --------------------
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

  # --------------------
  # Help
  # --------------------
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
      --newton          Enable Newton interpolation
      -n, --window N    Window size for Newton (e.g. 4)
      --step S          Output discretization step (e.g. 0.5)
      --sep SEP         Output separator: space | semicolon | tab (default: space)
      --in-sep SEP      Input separator: auto | space | semicolon | tab (default: auto)
    """
  end
end
