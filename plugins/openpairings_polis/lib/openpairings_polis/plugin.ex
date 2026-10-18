defmodule OpenPairingsPolis.Plugin do
  @moduledoc """
  Polis, the print station, as an OpenPairings plugin (`PairingsEngine.Plugin`).

  A hall PC with a printer joins a tournament once, with a one-time link
  made on `/p/polis/tournaments/:id` - the tournament's Settings, under
  Print station - and from then on holds a WebSocket
  open to `/p/polis/link`. Every time a round's pairings go public, the
  station gets the round and prints it. The plugin prints nothing itself;
  it would not know a printer if one fell on it.
  """
  @behaviour PairingsEngine.Plugin

  use Gettext, backend: OpenPairingsPolis.Gettext

  alias OpenPairingsPolis.Gettext, as: PolisGettext
  alias PairingsEngine.Features
  alias PairingsEngine.Tournaments.Tournament

  # Kept in step with the plugin's line in the Polis CHANGELOG.
  @version "0.1.0"

  @feature "polis_print_station"

  @doc "The `PairingsEngine.Features` key that switches the plugin on for an account."
  def feature, do: @feature

  @impl true
  def id, do: "polis"

  @impl true
  def name do
    PolisGettext.follow_core_locale()
    gettext("Print station")
  end

  @impl true
  def description do
    PolisGettext.follow_core_locale()

    gettext(
      "Prints the pairings and the place cards on a PC in the playing hall the moment a round is published."
    )
  end

  @impl true
  def version, do: @version

  @impl true
  def start_path, do: "/p/polis"

  @impl true
  def routes do
    [
      {"/", OpenPairingsPolisWeb.StationsLive, :index},
      {"/tournaments/:id", OpenPairingsPolisWeb.StationsLive, :show}
    ]
  end

  @impl true
  def http_routes do
    [
      {:post, "/join/:code", OpenPairingsPolisWeb.JoinPlug, []},
      {:get, "/link", OpenPairingsPolisWeb.LinkPlug, []}
    ]
  end

  # In the tournament's Settings, not its top bar: a print station is set
  # up once and then left alone, which does not earn it a tab beside
  # Pairings. The icon is one the core's own source uses, because the
  # stylesheet only builds those.
  @impl true
  def tournament_settings_entries(scope, %Tournament{} = t) do
    if Features.enabled?(scope, @feature) do
      PolisGettext.follow_core_locale()

      [
        %{
          id: "polis",
          label: gettext("Print station"),
          path: "/p/polis/tournaments/#{t.id}",
          icon: "hero-printer-micro",
          group: :publishing
        }
      ]
    else
      []
    end
  end

  @impl true
  def features do
    PolisGettext.follow_core_locale()

    [
      %{
        key: @feature,
        # The hosted edition is a Belgian server, and every plug-in on it
        # lives in the Belgian pack. "Optional tools for any federation" is
        # where nobody looks, as was pointed out with some force.
        federation: "BEL",
        label: gettext("Print station"),
        description:
          gettext(
            "Adds \"Print station\" to a tournament's Settings: join a PC in the hall with a printer, and it prints the pairings and the place cards of every round as soon as you publish it."
          )
      }
    ]
  end

  @impl true
  def migrations_path, do: Path.expand("../../priv/migrations", __DIR__)
end
