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

  describe "where it is" do
    test "a page in the tournament's Settings with the feature on, and not otherwise", %{
      scope: scope,
      user: user,
      tournament: t
    } do
      assert [
               %{
                 id: "polis",
                 path: path,
                 group: :publishing,
                 icon: "hero-printer-micro",
                 label: "Print station"
               }
             ] = Plugin.tournament_settings_entries(scope, t)

      assert path == "/p/polis/tournaments/#{t.id}"

      {:ok, user} = Features.set_enabled(user, [])
      assert Plugin.tournament_settings_entries(Scope.for_user(user), t) == []
    end

    test "not in the top bar any more" do
      Code.ensure_loaded!(Plugin)
      refute function_exported?(Plugin, :tournament_menu_entries, 2)
    end

    test "the feature sits in the Belgian pack" do
      assert [%{key: "polis_print_station", federation: "BEL"}] = Plugin.features()
    end

    test "the tournament page sits in the Settings frame, the rail beside it", %{
      conn: conn,
      tournament: t
    } do
      {:ok, view, _html} = live(conn, "/p/polis/tournaments/#{t.id}")
      assert has_element?(view, "#settings-page")
      assert has_element?(view, "a[href='/p/polis/tournaments/#{t.id}']")
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

  describe "a station's name, room and share" do
    setup %{scope: scope, tournament: t} do
      t = t |> Ecto.Changeset.change(categories: ["U12", "Women"]) |> Repo.update!()
      {station, _key} = joined_station!(scope, t)
      %{tournament: t, station: station}
    end

    test "the page shows the parsed board numbers while typing, and saves", %{
      conn: conn,
      station: s,
      tournament: t
    } do
      Stations.subscribe(t.id)
      {:ok, view, _html} = live(conn, "/p/polis/tournaments/#{t.id}")
      dom = "#stations-#{s.id}"
      assert has_element?(view, "#{dom}-share", "Prints everything")
      assert has_element?(view, "#{dom}-categories input[value='Women']")

      view
      |> form("#{dom}-form", station: %{boards: "40-45, 1-20, 35"})
      |> render_change()

      assert has_element?(view, "#{dom}-boards-parsed", "1-20, 35, 40-45")

      view
      |> form("#{dom}-form", station: %{boards: "9-3"})
      |> render_change()

      assert has_element?(view, "#{dom}-boards-parsed.error-note")

      view
      |> form("#{dom}-form",
        station: %{name: "Door", room: "Annex", boards: "1-20", categories: ["", "Women"]}
      )
      |> render_submit()

      assert %Station{
               name: "Door",
               room: "Annex",
               filter_boards: "1-20",
               filter_categories: ["Women"]
             } =
               Repo.get!(Station, s.id)

      sid = s.id
      assert_receive {:polis_settings_changed, ^sid}
      assert has_element?(view, "#{dom}-room", "Annex")
      assert has_element?(view, "#{dom}-share", "1-20")
    end

    test "board numbers that do not read are not saved", %{conn: conn, station: s, tournament: t} do
      {:ok, view, _html} = live(conn, "/p/polis/tournaments/#{t.id}")

      view
      |> form("#stations-#{s.id}-form", station: %{boards: "abc"})
      |> render_submit()

      assert has_element?(view, "#polis-error")
      assert Repo.get!(Station, s.id).filter_boards == ""
    end

    test "what the station says about itself shows here", %{conn: conn, station: s, tournament: t} do
      {:ok, view, _html} = live(conn, "/p/polis/tournaments/#{t.id}")
      {:ok, _} = Stations.update_settings(s, %{"room" => "Room B", "categories" => ["U12"]})
      _ = render(view)
      assert has_element?(view, "#stations-#{s.id}-room", "Room B")
      assert has_element?(view, "#stations-#{s.id}-share", "U12")
    end
  end
end
