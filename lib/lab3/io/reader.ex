defmodule Lab3.IO.Reader do
  @moduledoc """
  Reader читает stdin в потоковом режиме и отправляет точки в Engine.

  Работает как GenServer (под Supervisor), чтобы показать второй подход
  к параллельности: behaviour (GenServer).
  """

  use GenServer

  alias Lab3.IO.Parser

  @type point :: {number(), number()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    engine = Keyword.fetch!(opts, :engine)
    in_sep = Keyword.get(opts, :in_sep, :auto)

    # читаем stdin в отдельном процессе (spawn) и шлём точки в engine
    spawn(fn -> read_loop(engine, in_sep) end)

    {:ok, %{engine: engine, in_sep: in_sep}}
  end

  defp read_loop(engine, in_sep) do
    IO.stream(:stdio, :line)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.each(fn line ->
      case Parser.parse_line(line, in_sep) do
        {:ok, point} -> send(engine, {:point, point})
        :skip -> :ok
        {:error, _} -> :ok
      end
    end)

    # EOF
    send(engine, :eof)
  end
end
