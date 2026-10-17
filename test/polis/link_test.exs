defmodule Polis.LinkTest do
  @moduledoc """
  The line to a joined tournament, against a stand-in server: welcome, the
  station's status, a round that becomes jobs, a print command; a removal
  that makes the station forget; and a server that goes away and comes
  back.
  """

  use Polis.StationCase, async: false

  alias Polis.Link

  setup do
    server = FakeServer.start()
    Station.choose_printer("Hall printer")
    {:ok, id} = Station.join(FakeServer.link(server))
    %{server: server, id: id}
  end

  test "welcome, then the station's status", %{server: server, id: id} do
    eventually(fn -> Link.info(id).up? end)
    eventually(fn -> FakeServer.statuses(server) != [] end)

    assert [%{"printer" => "Hall printer", "last_printed_round" => nil} | _] =
             FakeServer.statuses(server)

    # A new printer is news; the server hears it.
    Station.choose_printer("Office printer")
    eventually(fn -> List.last(FakeServer.statuses(server))["printer"] == "Office printer" end)
  end

  test "a round becomes jobs, and the status says it was printed", %{server: server, id: id} do
    eventually(fn -> Link.info(id).up? end)
    FakeServer.push(server, %{"type" => "round", "round" => FakeServer.payload(1)})

    assert_receive {:printed, %{title: "Club Open - " <> _}}, 3_000
    assert_receive {:printed, _}, 3_000
    eventually(fn -> List.last(FakeServer.statuses(server))["last_printed_round"] == 1 end)

    FakeServer.push(server, %{"type" => "print", "round" => 1, "what" => "pairings"})
    assert_receive {:printed, %{title: "Club Open - Pairings 1"}}, 3_000
  end

  test "the round the server holds arrives right after welcome", %{server: server, id: id} do
    FakeServer.set(server, :round, FakeServer.payload(6))
    Station.restart_link(id)
    assert_receive {:printed, %{title: "Club Open - " <> rest}}, 3_000
    assert rest =~ "6"
  end

  test "removed in OpenPairings: forgotten here", %{server: server, id: id} do
    eventually(fn -> Link.info(id).up? end)
    FakeServer.push(server, %{"type" => "leave"})
    eventually(fn -> State.tournaments() == [] end)
    eventually(fn -> Link.whereis(id) == nil end)
  end

  test "a revoked key on the next hello: forgotten too", %{server: server, id: id} do
    eventually(fn -> Link.info(id).up? end)
    FakeServer.set(server, :revoked, true)
    Station.restart_link(id)
    eventually(fn -> State.tournaments() == [] end)
  end

  test "an unknown key is said and tried again later, not forgotten", %{server: server, id: id} do
    FakeServer.set(server, :key, "another-key")
    Station.restart_link(id)
    eventually(fn -> Link.info(id).error == {:refused, "key"} end)
    assert [_] = State.tournaments()
  end

  test "the server goes away and comes back: the line is back by itself", %{
    server: server,
    id: id
  } do
    eventually(fn -> Link.info(id).up? end)
    hellos = FakeServer.get(server, :hellos)

    FakeServer.down(server)
    eventually(fn -> not Link.info(id).up? end)
    FakeServer.up(server)

    eventually(fn -> Link.info(id).up? end, 8_000)
    assert FakeServer.get(server, :hellos) > hellos
  end

  test "Remove tells the server", %{server: server, id: id} do
    eventually(fn -> Link.info(id).up? end)
    Station.remove(id)
    eventually(fn -> FakeServer.get(server, :left?) end)
    assert State.tournaments() == []
  end
end
