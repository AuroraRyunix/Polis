defmodule OpenPairingsPolis.StationSettingsTest do
  @moduledoc """
  A station's name, room and share of the round: the one place that
  changes them, and the payload cut down to the share. The board-number
  reader itself is the core's (`PairingsEngine.BoardRanges`); the few
  lines on it here are the plug-in's reasons for relying on it.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import OpenPairingsPolis.Fixtures

  alias OpenPairingsPolis.{RoundPayload, Station, Stations}
  alias PairingsEngine.{BoardRanges, Repo, Tournaments}

  setup :register_and_log_in_user
  setup :admin_with_feature

  setup %{scope: scope} do
    fx = paired(scope)

    {:ok, t} =
      Tournaments.update_tournament(fx.tournament, %{
        "rooms" => [
          %{"name" => "Room A", "boards" => "1"},
          %{"name" => "Room B", "boards" => "2-3"},
          %{"name" => "Annex", "boards" => ""}
        ]
      })

    {station, _key} = joined_station!(scope, t)
    %{fx | tournament: t} |> Map.put(:station, station)
  end

  defp room_id(t, name), do: Enum.find(t.rooms, &(&1["name"] == name))["id"]

  describe "board numbers" do
    test "ranges and single boards, merged and in order" do
      assert {:ok, [{1, 20}, {35, 35}, {40, 45}]} = BoardRanges.parse("1-20, 35, 40-45")
      assert {:ok, [{1, 9}]} = BoardRanges.parse("3-8; 1 - 5 9")
      assert {:ok, [{2, 4}]} = BoardRanges.parse("2–4")
      assert {:ok, []} = BoardRanges.parse("  ")
      assert BoardRanges.format([{1, 20}, {35, 35}]) == "1-20, 35"
    end

    test "what does not read says which piece and why" do
      assert {:error, {:backwards, "20-1"}} = BoardRanges.parse("20-1")
      assert {:error, {:bad, "abc"}} = BoardRanges.parse("1, abc")
      assert {:error, {:bad, "0"}} = BoardRanges.parse("0")
      assert {:error, {:too_big, "10000"}} = BoardRanges.parse("10000")
      assert {:error, {:bad, "1-2-3"}} = BoardRanges.parse("1-2-3")
    end

    test "a board label's numbers: plain, team, and a shared fixed table" do
      assert BoardRanges.board_numbers("12") == [12]
      assert BoardRanges.board_numbers("3.1") == [3]
      assert BoardRanges.board_numbers("1001/1002") == [1001, 1002]
      assert BoardRanges.member?([], "anything")
      assert BoardRanges.member?([{1000, 1001}], "1001/1002")
      refute BoardRanges.member?([{1, 5}], "12")
    end
  end

  describe "update_settings/2" do
    test "keeps name, room, known categories and board numbers in its own spelling", %{
      station: s,
      tournament: t
    } do
      t |> Ecto.Changeset.change(categories: ["U12", "Women"]) |> Repo.update!()
      Stations.subscribe(t.id)

      assert {:ok, s} =
               Stations.update_settings(s, %{
                 "name" => "  Printer by the door ",
                 "room" => "Room B",
                 "categories" => ["Women", "Nonsense", "Women"],
                 "boards" => "40-45,1 - 20"
               })

      b = room_id(t, "Room B")

      assert %Station{
               name: "Printer by the door",
               room: "Room B",
               room_id: ^b,
               filter_categories: ["Women"],
               filter_boards: "1-20, 40-45"
             } = Repo.get!(Station, s.id)

      sid = s.id
      assert_receive {:polis_settings_changed, ^sid}
      assert_receive :polis_stations_changed
    end

    test "an empty name keeps the old one; keys left out are left alone", %{station: s} do
      {:ok, s} = Stations.update_settings(s, %{"room" => "Annex"})
      {:ok, s} = Stations.update_settings(s, %{"name" => "   "})
      assert %{name: "Hall PC", room: "Annex"} = s
    end

    test "board numbers that do not read change nothing", %{station: s} do
      assert {:error, {:boards, {:backwards, "9-3"}}} =
               Stations.update_settings(s, %{"room" => "Annex", "boards" => "9-3"})

      assert Repo.get!(Station, s.id).room == ""
    end

    test "a room the tournament does not have changes nothing", %{station: s} do
      assert {:error, {:room, :unknown}} =
               Stations.update_settings(s, %{"name" => "Door", "room" => "Narnia"})

      assert {:error, {:room, :unknown}} =
               Stations.update_settings(s, %{"room_id" => "no-such-id"})

      assert %{name: "Hall PC", room: "", room_id: ""} = Repo.get!(Station, s.id)
    end

    test "the page picks by id, keeps by \"keep\", clears by \"\"", %{station: s, tournament: t} do
      a = room_id(t, "Room A")
      {:ok, s} = Stations.update_settings(s, %{"room_id" => a})
      assert %{room_id: ^a, room: "Room A"} = s
      {:ok, s} = Stations.update_settings(s, %{"room_id" => "keep", "name" => "Door"})
      assert %{room_id: ^a, name: "Door"} = s
      {:ok, s} = Stations.update_settings(s, %{"room_id" => ""})
      assert %{room_id: "", room: ""} = s
    end

    test "a free-text room from before rooms survives being sent back, and is only a label", %{
      station: s,
      tournament: t
    } do
      s = s |> Ecto.Changeset.change(room: "Upstairs") |> Repo.update!()
      assert Stations.legacy_room?(s, t)
      assert Stations.settings(s, t)["room"] == "Upstairs"
      assert Stations.filter(s, t).room == nil

      {:ok, s} = Stations.update_settings(s, %{"room" => "Upstairs", "name" => "Door"})
      assert %{room: "Upstairs", room_id: "", name: "Door"} = s

      {:ok, s} = Stations.update_settings(s, %{"room" => "room a"})
      refute Stations.legacy_room?(s, t)
      assert Stations.settings(s, t)["room"] == "Room A"
    end

    test "a room renamed follows the station; a room removed leaves it in none", %{
      station: s,
      tournament: t
    } do
      b = room_id(t, "Room B")
      {:ok, s} = Stations.update_settings(s, %{"room_id" => b})

      {:ok, t} =
        Tournaments.update_tournament(t, %{
          "rooms" => [%{"id" => b, "name" => "The annexe", "boards" => "2-3"}]
        })

      assert Stations.settings(s, t)["room"] == "The annexe"
      assert Stations.settings(s, t)["rooms_available"] == ["The annexe"]

      {:ok, t} = Tournaments.update_tournament(t, %{"rooms" => []})
      assert Stations.settings(s, t)["room"] == ""
      assert Stations.filter(s, t).room == nil
    end

    test "the page's version refuses a station of another tournament", %{scope: scope, station: s} do
      other = paired(scope).tournament
      assert {:error, :not_found} = Stations.update_settings(other, s.id, %{"name" => "X"})
    end

    test "joining again keeps the name a person gave it", %{
      scope: scope,
      station: s,
      tournament: t
    } do
      {:ok, _} = Stations.update_settings(s, %{"name" => "Door", "room" => "Room B"})
      {again, _key} = joined_station!(scope, t)
      assert again.id == s.id
      assert %{name: "Door", room: "Room B"} = Repo.get!(Station, s.id)
    end
  end

  describe "a station's share of the round" do
    setup %{tournament: t, players: [a, b, c, _d], round: r} = fx do
      t = t |> Ecto.Changeset.change(categories: ["U12", "Women"]) |> Repo.update!()
      a |> Ecto.Changeset.change(categories: ["U12"]) |> Repo.update!()
      b |> Ecto.Changeset.change(categories: []) |> Repo.update!()
      c |> Ecto.Changeset.change(categories: ["Women"]) |> Repo.update!()
      bye = add_bye!(fx)
      bye |> Ecto.Changeset.change(categories: ["U12"]) |> Repo.update!()
      publish!(r)
      %{tournament: Repo.reload!(t)}
    end

    defp boards_for(station, t) do
      station = Repo.reload!(station)
      {:ok, 1, payload} = RoundPayload.latest(t, Stations.filter(station, t))
      {Enum.map(payload["boards"], & &1["board"]), payload}
    end

    test "no filter is the whole round, and no selection in the payload", %{
      station: s,
      tournament: t
    } do
      {boards, payload} = boards_for(s, t)
      assert boards == ["1", "2", "3"]
      refute Map.has_key?(payload, "selection")
      {:ok, 1, whole} = RoundPayload.latest(t)
      assert whole["rev"] == payload["rev"]
    end

    test "a mixed board prints when either player is in a ticked category; a bye by its one player",
         %{station: s, tournament: t} do
      {:ok, _} = Stations.update_settings(s, %{"categories" => ["U12"]})
      assert {["1", "3"], _} = boards_for(s, t)

      {:ok, _} = Stations.update_settings(s, %{"categories" => ["Women"]})
      assert {["2"], _} = boards_for(s, t)
    end

    test "board numbers and categories both have to agree", %{station: s, tournament: t} do
      {:ok, _} = Stations.update_settings(s, %{"categories" => ["U12"], "boards" => "2-3"})
      {boards, payload} = boards_for(s, t)
      assert boards == ["3"]

      assert payload["selection"] == %{
               "room" => "",
               "boards" => "2-3",
               "categories" => ["U12"]
             }
    end

    test "a room is its boards, and changes the rev", %{station: s, tournament: t} do
      {_, before} = boards_for(s, t)
      {:ok, _} = Stations.update_settings(s, %{"room" => "Room B"})
      {boards, payload} = boards_for(s, t)
      assert boards == ["2", "3"]
      assert payload["selection"]["room"] == "Room B"
      refute payload["rev"] == before["rev"]
    end

    test "room, board numbers and categories all have to agree", %{station: s, tournament: t} do
      {:ok, s} =
        Stations.update_settings(s, %{"room" => "Room B", "boards" => "1-2", "categories" => []})

      assert {["2"], _} = boards_for(s, t)

      {:ok, s} = Stations.update_settings(s, %{"categories" => ["U12"]})
      assert {[], _} = boards_for(s, t)

      {:ok, _} = Stations.update_settings(s, %{"boards" => ""})
      assert {["3"], _} = boards_for(s, t)
    end

    test "a room with no boards yet holds none", %{station: s, tournament: t} do
      {:ok, _} = Stations.update_settings(s, %{"room" => "Annex"})
      assert {[], %{"selection" => %{"room" => "Annex"}}} = boards_for(s, t)
    end

    test "a free-text label restricts nothing and is no selection", %{station: s, tournament: t} do
      s |> Ecto.Changeset.change(room: "Upstairs") |> Repo.update!()
      {boards, payload} = boards_for(s, t)
      assert boards == ["1", "2", "3"]
      refute Map.has_key?(payload, "selection")
    end

    test "a category the tournament dropped matches everybody, not nobody", %{
      station: s,
      tournament: t
    } do
      {:ok, _} = Stations.update_settings(s, %{"categories" => ["Women"]})
      t = t |> Ecto.Changeset.change(categories: ["U12"]) |> Repo.update!()
      assert {["1", "2", "3"], _} = boards_for(s, t)
    end
  end
end
