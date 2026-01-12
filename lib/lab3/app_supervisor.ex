defmodule Lab3.AppSupervisor do
  @moduledoc """
  Supervisor для Lab3.

  Поднимает Reader (GenServer), который читает stdin и отправляет точки в Engine (spawn-процесс).
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children = [
      {Lab3.IO.Reader, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
