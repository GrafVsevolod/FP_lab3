defmodule Lab3.Proc.Reader do
  @moduledoc """
  Процесс, который читает stdin построчно, парсит точки и отправляет их в Engine.
  """

  alias Lab3.IO.Parser

  @spec start(pid()) :: pid()
  def start(engine_pid) do
    spawn(fn -> run(engine_pid) end)
  end

  defp run(engine_pid) do
    IO.stream(:stdio, :line)
    |> Enum.each(fn line ->
      case Parser.parse_line(line) do
        {:ok, point} -> send(engine_pid, {:point, point})
        :skip -> :ok
        {:error, _reason} -> :ok
      end
    end)

    send(engine_pid, :eof)
  end
end
