defmodule SlackSocket.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(opts) do
    name = opts[:name] || SlackSocket
    sup_name = Module.concat(name, "Supervisor")
    Supervisor.start_link(__MODULE__, opts, name: sup_name)
  end

  @impl true
  def init(_opts) do
    children = [
      SlackWebApi,
      {DynamicSupervisor, name: SlackSocket.WebSocketSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
