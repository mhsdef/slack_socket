defmodule SlackSocket.WebSocket do
  use GenServer

  require Logger
  require Mint.HTTP

  defstruct [
    :conn,
    :websocket,
    :request_ref,
    :status,
    :resp_headers,
    :app_callback,
    :socket_open_url,
    :token,
    :closing?
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts \\ []) do
    state = %__MODULE__{
      app_callback: opts[:app_callback] || fn _x -> nil end,
      socket_open_url: opts[:socket_open_url] || "https://slack.com/api/apps.connections.open",
      token: opts[:app_token] || Application.fetch_env!(:slack_socket, :app_token)
    }

    Process.send_after(self(), :connect, some_jitter())
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, %{socket_open_url: url, token: token} = state) do
    ws_url = Req.post!(url, auth: {:bearer, token}, json: %{}).body["url"]
    uri = URI.parse(ws_url)

    http_scheme =
      case uri.scheme do
        "ws" -> :http
        "wss" -> :https
      end

    ws_scheme =
      case uri.scheme do
        "ws" -> :ws
        "wss" -> :wss
      end

    path =
      case uri.query do
        nil -> uri.path
        query -> uri.path <> "?" <> query
      end

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, uri.host, uri.port),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(ws_scheme, conn, path, [],
             extensions: [
               Mint.WebSocket.PerMessageDeflate
             ]
           ) do
      {:noreply, %{state | conn: conn, request_ref: ref}}
    else
      _ -> {:noreply, state}
    end
  end

  @impl true
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = put_in(state.conn, conn) |> handle_responses(responses)
        if state.closing?, do: do_close(state), else: {:noreply, state}

      {:error, conn, reason, _responses} ->
        Logger.debug("Ws response error: #{inspect(reason)}")
        state = put_in(state.conn, conn)
        {:noreply, state}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_frames(state, frames) do
    Enum.reduce(frames, state, fn
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
        |> do_app_callback(json["payload"]["event"])

      frame, state ->
        Logger.debug("Unexpected frame received: #{inspect(frame)}")
        state
    end)
  end

  ##########################
  ##       Private        ##
  ##########################

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
        {:error, put_in(state.websocket, websocket), reason}

      {:error, conn, reason} ->
        Logger.debug("Send frame conn error: #{inspect(reason)}")
        {:error, put_in(state.conn, conn), reason}
    end
  end

  defp do_ack(state, %{"envelope_id" => envelope_id} = _slack_msg) do
    {:ok, state} = send_frame(state, {:text, Jason.encode!(%{"envelope_id" => envelope_id})})
    state
  end

  defp do_ack(state, _), do: state

  defp do_app_callback(state, slack_event) do
    state.app_callback.(slack_event)
    state
  end

  defp do_close(state) do
    # Streaming a close frame may fail if the server has already closed
    # for writing.
    _ = send_frame(state, :close)
    Mint.HTTP.close(state.conn)
    {:stop, :normal, state}
  end

  defp some_jitter() do
    :rand.uniform(10_000)
  end
end
