defmodule OpenPairingsPolisWeb.JoinPlug do
  @moduledoc """
  `POST /p/polis/join/:code` - a print station joining with a one-time
  code. JSON in (`{"v":1,"device","name","software"}`), JSON out:

    * 200 `{"key","socket","server","tournament":{"id","name"}}`
    * 404 a code nobody made; 410 one used or expired
    * 409 a protocol version this side does not speak
    * 422 a body that is not a station describing itself
    * 429 too many wrong codes from one address

  Mounted without a pipeline (`PairingsEngine.Plugin.http_routes/0`): no
  session, no CSRF, no sign-in. The code is the only credential, which is
  why wrong ones are counted per client address (the core's
  `:board_link_auth` bucket, under a key of our own).
  """
  @behaviour Plug

  import Plug.Conn

  alias OpenPairingsPolis.Stations
  alias PairingsEngine.RateLimit
  alias PairingsEngineWeb.ClientIp

  @protocol 1
  @text_bytes 100

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_params: %{"code" => code}} = conn, _opts) do
    params = conn.body_params
    limit_key = "polis:" <> ClientIp.get(conn)

    cond do
      params["v"] != @protocol ->
        json(conn, 409, %{error: "version", v: @protocol})

      not RateLimit.allow?(:board_link_auth, limit_key) ->
        json(conn, 429, %{error: "slow down"})

      true ->
        case station_attrs(params) do
          {:ok, attrs} -> redeem(conn, code, attrs, limit_key)
          :error -> json(conn, 422, %{error: "device"})
        end
    end
  end

  defp redeem(conn, code, attrs, limit_key) do
    case Stations.redeem(code, attrs) do
      {:ok, _station, key, tournament} ->
        json(conn, 200, %{
          key: key,
          socket: Stations.socket_path(),
          server: Stations.server_name(),
          tournament: %{id: tournament.id, name: tournament.name}
        })

      {:error, :not_found} ->
        RateLimit.record(:board_link_auth, limit_key)
        json(conn, 404, %{error: "unknown"})

      {:error, :gone} ->
        RateLimit.record(:board_link_auth, limit_key)
        json(conn, 410, %{error: "used or expired"})
    end
  end

  defp station_attrs(%{"device" => device} = params)
       when is_binary(device) and device != "" and byte_size(device) <= @text_bytes do
    {:ok,
     %{
       device: device,
       name: text(params["name"]) || device,
       software: text(params["software"]) || ""
     }}
  end

  defp station_attrs(_params), do: :error

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      v -> String.slice(v, 0, @text_bytes)
    end
  end

  defp text(_value), do: nil

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end
