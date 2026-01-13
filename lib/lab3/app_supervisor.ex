defmodule Lab3.AppSupervisor do
  @moduledoc """
  Supervisor, который поднимает:
  - Engine (процесс через spawn)
  - Reader (GenServer, читает stdin и шлёт точки в Engine)

  Важно: parent для Engine должен быть CLI-процесс, чтобы CLI мог дождаться {:done, pid}.
  """

  use Supervisor

  alias Lab3.Stream.Engine
  alias Lab3.IO.Reader

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    parent = Keyword.fetch!(opts, :parent)

    engine =
      Engine.start(
        parent: parent,
        step: Keyword.fetch!(opts, :step),
        algs: Keyword.fetch!(opts, :algs),
        sep: Keyword.get(opts, :sep, " "),
        window: Keyword.get(opts, :window, 4)
      )

    children = [
      {Reader, engine: engine, in_sep: Keyword.get(opts, :in_sep, :auto)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
