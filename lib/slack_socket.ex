defmodule SlackSocket do
  @moduledoc """
  Documentation for `SlackSocket`.
  """
  alias SlackSocket.WebSocket
  alias SlackSocket.WebSocketSupervisor

  @doc """
  Returns a child specification for SlackSocket with the given `options`.
  The `:name`, the `:app_token`, and the `:bot_token` options are
  optional, though the latter two must be set via runtime config if not
  explicitly provided.

  ## Options
    * `:name` - the name of the SlackWebApi to be started
    * `:app_token` - the app token to use in Slack Socket Mode setup
    * `:bot_token` - the bot token to use in Slack Web API calls
  """
  @spec child_spec(keyword) :: Supervisor.child_spec()
  defdelegate child_spec(options), to: SlackSocket.Supervisor

  def connect(socket_opts \\ [], num_conn \\ 3) when num_conn > 0 and num_conn <= 10 do
    Enum.each(1..num_conn, fn _x ->
      {:ok, _} = DynamicSupervisor.start_child(WebSocketSupervisor, {WebSocket, socket_opts})
    end)
  end

  defdelegate create_channel(channel_name), to: SlackWebApi
  defdelegate join_channel(channel_id), to: SlackWebApi
  defdelegate leave_channel(channel_id), to: SlackWebApi
  defdelegate archive_channel(channel_id), to: SlackWebApi
  defdelegate set_channel_topic(channel_id, topic), to: SlackWebApi
  defdelegate invite_to_channel(channel_id, users), to: SlackWebApi
  defdelegate send_message(message), to: SlackWebApi
  defdelegate react_to_message(message, emoji_name), to: SlackWebApi
end
