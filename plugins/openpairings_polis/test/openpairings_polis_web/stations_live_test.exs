defmodule OpenPairingsPolisWeb.StationsLiveTest do
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import OpenPairingsPolis.Fixtures

  alias OpenPairingsPolis.{Plugin, Station, Stations}
  alias PairingsEngine.{Features, Repo}
  alias PairingsEngine.Accounts.Scope

  setup :register_and_log_in_user
  setup :admin_with_feature

  setup %{scope: scope} do
    paired(scope)
  end

  describe "the menu" do
    test "offers the page with the feature on, and not otherwise", %{
      scope: scope,
      user: user,
      tournament: t
    } do
      assert [%{id: "polis", path: path}] = Plugin.tournament_menu_entries(scope, t)
      assert path == "/p/polis/tournaments/#{t.id}"

      {:ok, user} = Features.set_enabled(user, [])
      assert Plugin.tournament_menu_entries(Scope.for_user(user), t) == []
    end

    test "the feature is a general one, in no federation's pack" do
      assert [%{key: "polis_print_station", federation: nil}] = Plugin.features()
    end
  end

  describe "the tournament page" do
    test "adding a station shows a one-time link and its QR code", %{conn: conn, tournament: t} do
      {:ok, view, _html} = live(conn, "/p/polis/tournaments/#{t.id}")
      assert has_element?(view, "#polis-no-stations")

      view |> element("#polis-add-station") |> render_click()

      assert has_element?(view, "#polis-join-url[value*='/p/polis/join/']")
      assert has_element?(view, "#polis-join-qr svg")
      assert has_element?(view, "#polis-join-expiry")
    end

    test "a joined station is listed, and Remove removes it", %{
      conn: conn,
      scope: scope,
      tournament: t
    } do
      {station, _key} = joined_station!(scope, t)
      Stations.subscribe(t.id)

      {:ok, view, _html} = live(conn, "/p/polis/tournaments/#{t.id}")
      assert has_element?(view, "#stations-#{station.id}")

      view |> element("#stations-#{station.id}-remove") |> render_click()

      sid = station.id
      assert_receive {:polis_revoked, ^sid}
      assert Repo.get!(Station, station.id).revoked_at
      refute has_element?(view, "#stations-#{station.id}")
    end

    test "print again sends the latest published round to every station", %{
      conn: conn,
      scope: scope,
      tournament: t,
      round: r
    } do
      joined_station!(scope, t)
      publish!(r)
      Stations.subscribe(t.id)

      {:ok, view, _html} = live(conn, "/p/polis/tournaments/#{t.id}")

      view
      |> form("#polis-print-form", print: %{what: "pairings"})
      |> render_submit()

      assert_receive {:polis_print, 1, "pairings"}
    end

    test "nothing to print again before a round is published", %{
      conn: conn,
      scope: scope,
      tournament: t
    } do
      joined_station!(scope, t)
      {:ok, view, _html} = live(conn, "/p/polis/tournaments/#{t.id}")
      assert has_element?(view, "#polis-nothing-published")
      refute has_element?(view, "#polis-print-form")
    end

    test "without the feature there is nothing to add", %{conn: conn, user: user, tournament: t} do
      {:ok, _} = Features.set_enabled(user, [])
      {:ok, view, _html} = live(conn, "/p/polis/tournaments/#{t.id}")
      assert has_element?(view, "#polis-not-enabled")
      refute has_element?(view, "#polis-add-station")
    end
  end

  describe "the overview" do
    test "lists this account's stations with their tournament", %{
      conn: conn,
      scope: scope,
      tournament: t
    } do
      {station, _key} = joined_station!(scope, t)
      {:ok, view, _html} = live(conn, "/p/polis")
      assert has_element?(view, "#stations-#{station.id} a[href='/p/polis/tournaments/#{t.id}']")
    end
  end
end
