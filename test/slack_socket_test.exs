defmodule SlackSocketTest do
  use ExUnit.Case
  doctest SlackSocket

  test "greets the world" do
    assert SlackSocket.hello() == :world
  end
end
