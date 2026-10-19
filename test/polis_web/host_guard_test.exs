defmodule PolisWeb.HostGuardTest do
  @moduledoc """
  `PolisWeb.HostGuard`: the station answers to its own names only, so a web
  page that renamed 127.0.0.1 (DNS rebinding) gets a 403 and no socket.
  """

  use Polis.StationCase, async: false

  import Phoenix.ConnTest

  alias PolisWeb.HostGuard

  @endpoint PolisWeb.Endpoint

  defp ask(host, path \\ "/help") do
    build_conn() |> Map.put(:host, host) |> get(path)
  end

  test "this machine's own names are answered" do
    for host <- ["localhost", "127.0.0.1", "LOCALHOST"] do
      assert ask(host).status == 200, host
    end
  end

  test "a name the page chose is a 403, on every kind of route" do
    for path <- ["/", "/help", "/jobs/abc/pdf", "/lang/nl"] do
      assert ask("attacker.example", path).status == 403, path
    end
  end

  test "the hall's address is refused until the station is told to listen on the network" do
    {:ok, name} = :inet.gethostname()
    refute HostGuard.host_allowed?(to_string(name))

    Application.put_env(:polis, :listen, :lan)
    on_exit(fn -> Application.delete_env(:polis, :listen) end)

    assert HostGuard.host_allowed?(to_string(name))
    assert ask(to_string(name)).status == 200
    refute HostGuard.host_allowed?("attacker.example")
    assert ask("attacker.example").status == 403
  end

  test "the socket's origin goes through the same list" do
    assert HostGuard.origin_allowed?(URI.parse("http://localhost:4061"))
    assert HostGuard.origin_allowed?(URI.parse("http://127.0.0.1:4061"))
    refute HostGuard.origin_allowed?(URI.parse("http://attacker.example:4061"))
    refute HostGuard.origin_allowed?(URI.parse("null"))
  end
end
