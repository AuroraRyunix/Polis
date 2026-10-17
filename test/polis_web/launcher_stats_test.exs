defmodule PolisWeb.LauncherStatsTest do
  @moduledoc """
  `GET /_launcher/stats` (`PolisWeb.Plugs.LauncherStats`): a loopback peer,
  this start's secret and no proxy header, or a 404 that says nothing more.
  """

  use Polis.StationCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint PolisWeb.Endpoint
  @token "a-launcher-secret-for-this-test"

  setup do
    Application.put_env(:polis, :launcher_token, @token)
    on_exit(fn -> Application.delete_env(:polis, :launcher_token) end)
    %{conn: build_conn()}
  end

  defp ask(conn, token) do
    conn = if token, do: put_req_header(conn, "x-launcher-token", token), else: conn
    get(conn, "/_launcher/stats")
  end

  test "no secret, a wrong one, or an empty one: 404", %{conn: conn} do
    assert ask(conn, nil).status == 404
    assert ask(build_conn(), "not-the-secret").status == 404
    assert ask(build_conn(), "").status == 404
  end

  test "the secret from another machine: 404", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.put_peer_data(%{address: {192, 168, 1, 23}, port: 50_000, ssl_cert: nil})
      |> ask(@token)

    assert conn.status == 404
  end

  test "a proxy header on a loopback request: 404" do
    for header <- ~w(x-forwarded-for forwarded x-real-ip cf-connecting-ip x-forwarded-host) do
      conn = build_conn() |> put_req_header(header, "203.0.113.9") |> ask(@token)
      assert conn.status == 404, header
    end
  end

  test "no secret made (details switched off): 404 even with a guess", %{conn: conn} do
    Application.delete_env(:polis, :launcher_token)
    assert ask(conn, @token).status == 404
  end

  test "anything but GET: 404", %{conn: conn} do
    conn = conn |> put_req_header("x-launcher-token", @token) |> post("/_launcher/stats", %{})
    assert conn.status == 404
  end

  test "with the secret: the documented shape, and no key in it", %{conn: conn} do
    {:ok, _} =
      State.add_tournament(%{
        "socket_url" => "ws://127.0.0.1:1/p/polis/link",
        "key" => "a-tournament-key-never-shown",
        "server" => "fake",
        "tournament_id" => "t-1",
        "name" => "Club Open"
      })

    Station.choose_printer("Hall printer")
    conn = ask(conn, @token)
    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    refute conn.resp_body =~ @token
    refute conn.resp_body =~ "a-tournament-key-never-shown"

    assert %{
             "app" => "polis",
             "version" => _,
             "uptime_s" => _,
             "system" => %{"os" => _, "arch" => _},
             "beam" => %{"memory_bytes" => %{"total" => _}, "cpu_percent" => _},
             "log" => %{"source" => _},
             "polis" => %{
               "jobs_queued" => 0,
               "printer" => "Hall printer",
               "tournaments" => 1,
               "links_up" => 0,
               "live_views" => _
             },
             "summary" => summary
           } = Jason.decode!(conn.resp_body)

    assert Enum.map(summary, & &1["label"]) == Polis.LauncherDetails.Stats.labels("en")
  end

  test "in Dutch when asked", %{conn: conn} do
    conn = conn |> put_req_header("x-launcher-token", @token) |> get("/_launcher/stats?lang=nl")
    labels = conn.resp_body |> Jason.decode!() |> Map.fetch!("summary") |> Enum.map(& &1["label"])
    assert labels == Polis.LauncherDetails.Stats.labels("nl")
  end
end
