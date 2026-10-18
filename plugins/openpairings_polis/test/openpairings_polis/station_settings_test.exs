defmodule OpenPairingsPolis.StationSettingsTest do
  @moduledoc """
  A station's name, room and share of the round: the board-number reader,
  the one place that changes them, and the payload cut down to the share.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import OpenPairingsPolis.Fixtures

  alias OpenPairingsPolis.{BoardRanges, RoundPayload, Station, Stations}
  alias PairingsEngine.Repo

  setup :register_and_log_in_user
  setup :admin_with_feature

  setup %{scope: scope} do
    fx = paired(scope)
    {station, _key} = joined_station!(scope, fx.tournament)
    Map.put(fx, :station, station)
  end

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

      assert %Station{
               name: "Printer by the door",
               room: "Room B",
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
               Stations.update_settings(s, %{"room" => "X", "boards" => "9-3"})

      assert Repo.get!(Station, s.id).room == ""
    end

    test "the page's version refuses a station of another tournament", %{scope: scope, station: s} do
      other = paired(scope).tournament
      assert {:error, :not_found} = Stations.update_settings(other, s.id, %{"room" => "X"})
    end

    test "joining again keeps the name a person gave it", %{
      scope: scope,
      station: s,
      tournament: t
    } do
      {:ok, _} = Stations.update_settings(s, %{"name" => "Door", "room" => "B"})
      {again, _key} = joined_station!(scope, t)
      assert again.id == s.id
      assert %{name: "Door", room: "B"} = Repo.get!(Station, s.id)
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
      selection = station |> Stations.filter(t) |> Map.put(:room, station.room)
      {:ok, 1, payload} = RoundPayload.latest(t, selection)
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

    test "a room alone is a selection too, and changes the rev", %{station: s, tournament: t} do
      {_, before} = boards_for(s, t)
      {:ok, _} = Stations.update_settings(s, %{"room" => "Room B"})
      {boards, payload} = boards_for(s, t)
      assert boards == ["1", "2", "3"]
      assert payload["selection"]["room"] == "Room B"
      refute payload["rev"] == before["rev"]
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
