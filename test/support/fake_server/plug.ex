defmodule Polis.FakeServer.Plug do
  @moduledoc false
  @behaviour Elixir.Plug

  import Elixir.Plug.Conn

  def init(agent), do: agent

  def call(%{method: "POST", path_info: ["p", "polis", "join", code]} = conn, agent) do
    {:ok, body, conn} = read_body(conn)
    identity = Jason.decode!(body)

    reply =
      Agent.get_and_update(agent, fn state ->
        cond do
          identity["v"] != 1 ->
            {:version, state}

          MapSet.member?(state.codes, code) ->
            {{:ok, state.key, state.tournament},
             %{state | codes: MapSet.delete(state.codes, code), identity: identity}}

          true ->
            {:gone, state}
        end
      end)

    case reply do
      {:ok, key, tournament} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            "key" => key,
            "socket" => "/p/polis/link",
            "server" => "fake",
            "tournament" => tournament
          })
        )

      :version ->
        send_resp(conn, 409, "version")

      :gone ->
        send_resp(conn, 410, "gone")
    end
  end

  def call(%{path_info: ["p", "polis", "link"]} = conn, agent) do
    conn
    |> WebSockAdapter.upgrade(Polis.FakeServer.Socket, agent, timeout: 120_000)
    |> halt()
  end

  # Somebody's web server, not OpenPairings: a page for every path.
  def call(%{path_info: ["somebody", "else" | _]} = conn, _agent),
    do: conn |> put_resp_content_type("text/html") |> send_resp(200, "<html>hello</html>")

  def call(conn, _agent), do: send_resp(conn, 404, "")
end
