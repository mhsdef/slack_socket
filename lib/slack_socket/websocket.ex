defmodule SlackSocket.WebSocketPool do
  @behaviour NimblePool

  require Logger
  require Mint.HTTP

  @socket_open_url "https://slack.com/api/apps.connections.open"

  @impl NimblePool
  def init_worker([{:token, token}] = pool_state) do
    parent = self()

    async = fn ->
      ws_url = Req.post!(@socket_open_url, auth: {:bearer, token}, json: %{}).body["url"]
      uri = URI.parse(ws_url)
      path = if uri.query, do: uri.path <> "?" <> uri.query, else: uri.path

      with {:ok, conn} <- Mint.HTTP.connect(:https, uri.host, uri.port),
           {:ok, conn} <- Mint.HTTP.controlling_process(conn, parent),
           {:ok, conn, ref} <-
             Mint.WebSocket.upgrade(:wss, conn, path, [],
               extensions: [
                 Mint.WebSocket.PerMessageDeflate
               ]
             ) do
        %{
          conn: conn,
          websocket: nil,
          request_ref: ref,
          status: nil,
          resp_headers: nil,
          closing?: false
        }
      else
        _ -> %{}
      end
    end

    {:async, async, pool_state}
  end

  @impl NimblePool
  def handle_checkin(result, _from, _old_state, pool_state) do
    with {:ok, state} <- result,
         {:ok, conn} <- Mint.HTTP.set_mode(state.conn, :active) do
      state = put_in(state.conn, conn)
      {:ok, state, pool_state}
    else
      {:error, _} -> {:remove, :closed, pool_state}
    end
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, state, pool_state) do
    with %{conn: conn, request_ref: _ref} <- state,
         {:ok, conn} <- Mint.HTTP.set_mode(conn, :passive) do
      state = put_in(state.conn, conn)
      {:ok, state, state, pool_state}
    else
      _ -> {:remove, :closed, pool_state}
    end
  end

  @impl NimblePool
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = put_in(state.conn, conn) |> handle_responses(responses)
        if state.closing?, do: do_close(state), else: {:ok, state}

      {:error, _conn, reason, _responses} ->
        Logger.debug("Ws response error: #{inspect(reason)}")
        {:remove, :closed}

      :unknown ->
        {:ok, state}
    end
  end

  @impl NimblePool
  def terminate_worker(_reason, state, pool_state) do
    do_close(state)
    {:ok, pool_state}
  end

  def send_message(data) when is_map(data) do
    send_message(Jason.encode!(data))
  end

  def send_message(text) when is_binary(text) do
    NimblePool.checkout!(
      __MODULE__,
      :checkout,
      fn _pool, state -> {text, send_frame(state, {:text, text})} end
    )
  end

  def handle_frames(state, frames) do
    Enum.reduce(frames, state, fn
      # reply to pings with pongs
      {:ping, data}, state ->
        {:ok, state} = send_frame(state, {:pong, data})
        state

      {:close, _code, reason}, state ->
        Logger.debug("Closing connection: #{inspect(reason)}")
        %{state | closing?: true}

      {:text, text}, state ->
        Logger.debug("Received: #{inspect(text)}")
        json = Jason.decode!(text)

        state
        |> do_ack(json)
        # akshully, take given adapter and call it
        |> do_robot_fwd(json["payload"]["event"])

      frame, state ->
        Logger.debug("Unexpected frame received: #{inspect(frame)}")
        state
    end)
  end

  ######################
  ##     Private      ##
  ######################

  defp handle_responses(state, responses)

  defp handle_responses(%{request_ref: ref} = state, [{:status, ref, status} | rest]) do
    put_in(state.status, status)
    |> handle_responses(rest)
  end

  defp handle_responses(%{request_ref: ref} = state, [{:headers, ref, resp_headers} | rest]) do
    put_in(state.resp_headers, resp_headers)
    |> handle_responses(rest)
  end

  defp handle_responses(%{request_ref: ref} = state, [{:done, ref} | rest]) do
    case Mint.WebSocket.new(state.conn, ref, state.status, state.resp_headers) do
      {:ok, conn, websocket} ->
        %{state | conn: conn, websocket: websocket, status: nil, resp_headers: nil}
        |> handle_responses(rest)

      {:error, conn, reason} ->
        Logger.debug("Ws response error: #{inspect(reason)}")
        put_in(state.conn, conn)
    end
  end

  defp handle_responses(%{request_ref: ref, websocket: websocket} = state, [
         {:data, ref, data} | rest
       ])
       when websocket != nil do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} ->
        put_in(state.websocket, websocket)
        |> handle_frames(frames)
        |> handle_responses(rest)

      {:error, websocket, reason} ->
        Logger.debug("Ws response error: #{inspect(reason)}")
        put_in(state.websocket, websocket)
    end
  end

  defp handle_responses(state, [_response | rest]) do
    handle_responses(state, rest)
  end

  defp handle_responses(state, []), do: state

  defp send_frame(state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, frame),
         state = put_in(state.websocket, websocket),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.request_ref, data) do
      {:ok, put_in(state.conn, conn)}
    else
      {:error, %Mint.WebSocket{} = websocket, reason} ->
        Logger.debug("Send frame ws error: #{inspect(reason)}")
        {:error, put_in(state.websocket, websocket)}

      {:error, conn, reason} ->
        Logger.debug("Send frame conn error: #{inspect(reason)}")
        {:error, put_in(state.conn, conn)}
    end
  end

  defp do_ack(state, %{"envelope_id" => envelope_id} = _slack_msg) do
    {:ok, state} = send_frame(state, {:text, Jason.encode!(%{"envelope_id" => envelope_id})})
    state
  end

  defp do_ack(state, _), do: state

  defp do_robot_fwd(state, %{"type" => "message", "user" => _user} = slack_event) do
    GenServer.call(state.caller_pid, slack_event)
    state
  end

  defp do_robot_fwd(state, _), do: state

  defp do_close(state) do
    # Streaming a close frame may fail if the server has already closed
    # for writing.
    _ = send_frame(state, :close)
    Mint.HTTP.close(state.conn)
  end
end
