defmodule Lab3.IO.Reader do
  @moduledoc """
  Reader (GenServer): читает stdin потоково и шлёт точки в Engine.

  Это "второй" способ параллельности: OTP GenServer.
  """

  use GenServer

  alias Lab3.IO.Parser

  @type point :: {number(), number()}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    engine = Keyword.fetch!(opts, :engine)
    in_sep = Keyword.get(opts, :in_sep, :auto)

    # запускаем чтение stdin в отдельном процессе, чтобы GenServer не блокировался
    parent = self()

    spawn(fn ->
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

      send(parent, :stdin_done)
    end)

    {:ok, %{engine: engine}}
  end

  @impl true
  def handle_info(:stdin_done, state) do
    send(state.engine, :eof)
    {:stop, :normal, state}
  end
end
