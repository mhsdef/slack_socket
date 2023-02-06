defmodule SlackSocket.WebSocketTest do
  use ExUnit.Case

  alias SlackSocket.WebSocket

  test "handle_frames/2, closing" do
    state = %{somesome: "whatever", closing?: false}
    frames = [{:close, 3333, "cuz unit test!"}]

    assert %{somesome: "whatever", closing?: true} = WebSocket.handle_frames(state, frames)
  end

  test "handle_frames/2, unexpected" do
    state = %{somesome: "whatever", closing?: false}
    frames = [{:weirdness, "oye!"}]

    assert state == WebSocket.handle_frames(state, frames)
  end
end
