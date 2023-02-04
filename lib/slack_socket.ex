defmodule SlackSocket do
  @moduledoc """
  Documentation for `SlackSocket`.
  """

  defdelegate create_channel(channel_name), to: SlackWebApi
  defdelegate join_channel(channel_id), to: SlackWebApi
  defdelegate leave_channel(channel_id), to: SlackWebApi
  defdelegate archive_channel(channel_id), to: SlackWebApi
  defdelegate set_channel_topic(channel_id, topic), to: SlackWebApi
  defdelegate invite_to_channel(channel_id, users), to: SlackWebApi
  defdelegate send_message(slack_message), to: SlackWebApi
  defdelegate react_to_message(channel_id, emoji_name, message_ts), to: SlackWebApi
end
