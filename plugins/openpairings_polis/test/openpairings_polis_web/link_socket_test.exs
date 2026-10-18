defmodule OpenPairingsPolisWeb.LinkSocketTest do
  @moduledoc """
  The link's callbacks, driven directly: the test process plays the socket
  process, so PubSub messages land in its own mailbox and are handed to
  `handle_info/2` by hand.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import OpenPairingsPolis.Fixtures

  alias OpenPairingsPolis.{Station, Stations}
  alias OpenPairingsPolisWeb.LinkSocket
  alias PairingsEngine.{Repo, Tournaments}

  setup :register_and_log_in_user
  setup :admin_with_feature

  setup %{scope: scope} do
    fx = paired(scope)
    {station, key} = joined_station!(scope, fx.tournament)
    Map.merge(fx, %{station: station, key: key})
  end

  defp dial(device, key, v \\ 1) do
    {:ok, state} = LinkSocket.init(%{})
    LinkSocket.handle_in({hello(device, key, v), [opcode: :text]}, state)
  end

  defp frames({:push, frames, state}), do: {Enum.map(frames, &decode/1), state}
  defp frames({:ok, state}), do: {[], state}

  defp decode({:text, json}), do: Jason.decode!(json)

  describe "hello" do
    test "a good key is welcomed, and the station marked online", %{station: s, key: key} do
      {[welcome, settings], state} = frames(dial(s.device_id, key))

      assert %{"type" => "welcome", "v" => 1, "tournament" => %{"id" => tid}} = welcome
      assert tid == s.tournament_id

      assert %{
               "type" => "settings",
               "name" => "Hall PC",
               "room" => "",
               "categories" => [],
               "boards" => "",
               "categories_available" => [],
               "rooms_available" => []
             } = settings

      assert state.station.id == s.id
      assert Stations.online?(Repo.get!(Station, s.id))
    end

    test "a wrong key is refused", %{station: s} do
      assert {:stop, :normal, 1000, [frame], _} = dial(s.device_id, "not the key")
      assert %{"type" => "refused", "reason" => "key"} = decode(frame)
    end

    test "a removed station is refused as revoked", %{station: s, key: key, tournament: t} do
      {:ok, _} = Stations.revoke(t, s.id)
      assert {:stop, :normal, 1000, [frame], _} = dial(s.device_id, key)
      assert %{"type" => "refused", "reason" => "revoked"} = decode(frame)
    end

    test "another protocol version is refused", %{station: s, key: key} do
      assert {:stop, :normal, 1000, [frame], _} = dial(s.device_id, key, 2)
      assert %{"type" => "refused", "reason" => "version"} = decode(frame)
    end

    test "nothing but hello is heard before hello" do
      {:ok, state} = LinkSocket.init(%{})
      status = Jason.encode!(%{type: "status", printer: "x"})
      assert {:ok, %{station: nil}} = LinkSocket.handle_in({status, [opcode: :text]}, state)
    end
  end

  describe "rounds" do
    test "the published round comes right after welcome", %{station: s, key: key, round: r} do
      publish!(r)
      {[_welcome, _settings, round], _state} = frames(dial(s.device_id, key))

      assert %{"type" => "round", "round" => %{"round" => 1, "rev" => rev, "boards" => boards}} =
               round

      assert is_binary(rev)
      assert length(boards) == 2
    end

    test "an unpublished round is not sent", %{station: s, key: key} do
      assert {[_welcome, _settings], state} = frames(dial(s.device_id, key))
      assert {[], _} = frames(LinkSocket.handle_info(:recompute, state))
    end

    test "a newly published round is sent once, and not again while it is unchanged", %{
      station: s,
      key: key,
      round: r,
      tournament: t
    } do
      {[_welcome, _settings], state} = frames(dial(s.device_id, key))

      {:ok, round} = Tournaments.publish_round_now(Tournaments.get_round(t.id, r.number))
      tid = t.id
      # The core said so on its topic, which the socket subscribed to.
      assert_receive {:tournament_changed, ^tid, _}

      {:ok, state} = LinkSocket.handle_info({:tournament_changed, tid, :settings}, state)
      assert state.timer
      assert_receive :recompute, 1_000

      {[%{"type" => "round", "round" => %{"round" => 1}}], state} =
        frames(LinkSocket.handle_info(:recompute, state))

      # Nothing changed: nothing sent.
      assert {[], state} = frames(LinkSocket.handle_info(:recompute, state))

      # Taken back: not news either.
      {:ok, _} = Tournaments.unpublish_round(round)
      assert {[], _} = frames(LinkSocket.handle_info(:recompute, state))
    end

    test "a result changing the payload sends it again with a new rev", %{
      station: s,
      key: key,
      round: r
    } do
      publish!(r)

      {[_welcome, _settings, %{"round" => %{"rev" => rev1}}], state} =
        frames(dial(s.device_id, key))

      [p | _] = Repo.preload(r, :pairings).pairings
      p |> Ecto.Changeset.change(display_board: "7") |> Repo.update!()

      {[%{"round" => %{"rev" => rev2}}], _} = frames(LinkSocket.handle_info(:recompute, state))
      refute rev1 == rev2
    end
  end

  describe "commands from the page" do
    test "print again reaches the socket", %{station: s, key: key, round: r, tournament: t} do
      publish!(r)
      {_frames, state} = frames(dial(s.device_id, key))

      Stations.print_again(t.id, 1, "placecards")
      assert_receive {:polis_print, 1, "placecards"} = msg

      # The round was already sent, so only the command goes out.
      assert {[%{"type" => "print", "round" => 1, "what" => "placecards"}], _} =
               frames(LinkSocket.handle_info(msg, state))
    end

    test "a removed station is told to leave", %{station: s, key: key, tournament: t} do
      {_frames, state} = frames(dial(s.device_id, key))
      {:ok, _} = Stations.revoke(t, s.id)
      sid = s.id
      assert_receive {:polis_revoked, ^sid} = msg

      assert {:stop, :normal, 1000, [frame], state} = LinkSocket.handle_info(msg, state)
      assert %{"type" => "leave"} = decode(frame)

      LinkSocket.terminate(:normal, state)
      refute Stations.online?(Repo.get!(Station, s.id))
    end

    test "status is kept and shown; leave forgets the station", %{station: s, key: key} do
      {_frames, state} = frames(dial(s.device_id, key))

      status = Jason.encode!(%{type: "status", printer: "Hall laser", last_printed_round: 1})
      {:ok, state} = LinkSocket.handle_in({status, [opcode: :text]}, state)

      assert %{"printer" => "Hall laser", "last_printed_round" => 1} =
               Repo.get!(Station, s.id).status

      leave = Jason.encode!(%{type: "leave"})
      assert {:stop, :normal, _} = LinkSocket.handle_in({leave, [opcode: :text]}, state)
      refute Repo.get(Station, s.id)
    end

    test "a stale socket closing does not mark a reconnected station offline", %{
      station: s,
      key: key
    } do
      {_frames, old} = frames(dial(s.device_id, key))
      {_frames, _new} = frames(dial(s.device_id, key))

      LinkSocket.terminate(:normal, old)
      assert Stations.online?(Repo.get!(Station, s.id))
    end
  end

  describe "name, room and share" do
    defp say(state, frame),
      do: LinkSocket.handle_in({Jason.encode!(frame), [opcode: :text]}, state)

    test "the station changes them; they are kept and told back, with its new share", %{
      station: s,
      key: key,
      round: r,
      tournament: t
    } do
      {:ok, t} =
        Tournaments.update_tournament(t, %{
          "categories" => ["U12"],
          "rooms" => [%{"name" => "Main", "boards" => "1"}, %{"name" => "Annex", "boards" => "2"}]
        })

      [_main, %{"id" => annex_id}] = t.rooms
      publish!(r)

      {[_welcome, _settings, %{"round" => %{"boards" => [_, _]}}], state} =
        frames(dial(s.device_id, key))

      # The room by name, as an older station types it, in its own spelling.
      {frames, state} = frames(say(state, %{type: "settings", name: "Door", room: " annex "}))

      assert [
               %{
                 "type" => "settings",
                 "name" => "Door",
                 "room" => "Annex",
                 "rooms_available" => ["Main", "Annex"]
               },
               %{"type" => "round", "round" => %{"boards" => [%{"board" => "2"}]} = payload}
             ] = frames

      assert payload["selection"]["room"] == "Annex"
      assert %{name: "Door", room: "Annex", room_id: ^annex_id} = Repo.get!(Station, s.id)

      # The topic says so too; the socket has already told the station.
      sid = s.id
      assert_receive {:polis_settings_changed, ^sid} = msg
      assert {[], _} = frames(LinkSocket.handle_info(msg, state))
    end

    test "board numbers that do not read are turned down, with what still holds", %{
      station: s,
      key: key
    } do
      {_frames, state} = frames(dial(s.device_id, key))

      assert {[%{"type" => "settings", "error" => "boards", "boards" => "", "room" => ""}], _} =
               frames(say(state, %{type: "settings", name: "X", boards: "9-1"}))

      assert Repo.get!(Station, s.id).name == "Hall PC"
    end

    test "a room the tournament does not have is turned down the same way", %{
      station: s,
      key: key
    } do
      {_frames, state} = frames(dial(s.device_id, key))

      assert {[%{"type" => "settings", "error" => "room", "room" => ""}], _} =
               frames(say(state, %{type: "settings", name: "Door", room: "Narnia"}))

      assert %{name: "Hall PC", room: "", room_id: ""} = Repo.get!(Station, s.id)
    end

    test "a free-text room from before rooms is a label: kept when sent back, filters nothing",
         %{station: s, key: key, round: r} do
      s |> Ecto.Changeset.change(room: "Old annex") |> Repo.update!()
      publish!(r)

      {[_welcome, %{"room" => "Old annex"}, %{"round" => round}], state} =
        frames(dial(s.device_id, key))

      assert [_, _] = round["boards"]
      refute Map.has_key?(round, "selection")

      assert {[%{"type" => "settings", "name" => "Door", "room" => "Old annex"}], _} =
               frames(say(state, %{type: "settings", name: "Door", room: "Old annex"}))

      assert %{room: "Old annex", room_id: ""} = Repo.get!(Station, s.id)
    end

    test "a change on the page reaches the socket and goes down the line", %{
      station: s,
      key: key,
      tournament: t
    } do
      {_frames, state} = frames(dial(s.device_id, key))

      {:ok, t} =
        Tournaments.update_tournament(t, %{"rooms" => [%{"name" => "Hall 2", "boards" => "1-2"}]})

      [%{"id" => id}] = t.rooms
      {:ok, _} = Stations.update_settings(t, s.id, %{"name" => "Renamed", "room_id" => id})

      sid = s.id
      assert_receive {:polis_settings_changed, ^sid} = msg

      assert {[%{"type" => "settings", "name" => "Renamed", "room" => "Hall 2"}], state} =
               frames(LinkSocket.handle_info(msg, state))

      # Renamed in Settings, Rooms: the station follows, at the next look.
      {:ok, _} =
        Tournaments.update_tournament(t, %{
          "rooms" => [%{"id" => id, "name" => "Annexe", "boards" => "1-2"}]
        })

      assert {[%{"type" => "settings", "room" => "Annexe", "rooms_available" => ["Annexe"]}], _} =
               frames(LinkSocket.handle_info(:recompute, state))
    end

    test "a category added to the tournament is offered at the next look", %{
      station: s,
      key: key,
      tournament: t
    } do
      {_frames, state} = frames(dial(s.device_id, key))
      t |> Ecto.Changeset.change(categories: ["Seniors"]) |> Repo.update!()

      assert {[%{"type" => "settings", "categories_available" => ["Seniors"]}], _} =
               frames(LinkSocket.handle_info(:recompute, state))
    end
  end
end
