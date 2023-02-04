defmodule SlackSocket.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SlackWebApi,
      SlackSocket.WebSocketPool
    ]

    opts = [strategy: :one_for_one, name: SlackSocket.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
