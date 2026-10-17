defmodule OpenPairingsPolisWeb.LinkPlug do
  @moduledoc """
  `GET /p/polis/link` - upgrades to the station's WebSocket
  (`OpenPairingsPolisWeb.LinkSocket`). Nothing is checked here: the key
  arrives in the first frame, not in the URL, which proxies write down.
  A request that is not a WebSocket upgrade gets a 426 and a shrug.
  """
  @behaviour Plug

  import Plug.Conn

  # A round payload of a large open is a few hundred kilobytes at most
  # going OUT; what comes IN is hello, status and leave. A megabyte frame
  # from a station is not a station.
  @max_frame_size 64_000

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if websocket?(conn) do
      conn
      |> WebSockAdapter.upgrade(OpenPairingsPolisWeb.LinkSocket, %{},
        timeout: 120_000,
        max_frame_size: @max_frame_size
      )
      |> halt()
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(426, "WebSocket only")
      |> halt()
    end
  end

  defp websocket?(conn) do
    conn
    |> get_req_header("upgrade")
    |> Enum.any?(&(String.downcase(&1) == "websocket"))
  end
end
