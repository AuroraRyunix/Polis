defmodule OpenPairingsPolis.Fixtures do
  @moduledoc """
  A small paired tournament (the core's `PairingsEngine.BoardLinkFixtures`:
  four players, round 1, two boards) plus what the print station tests
  need on top: an admin with the feature, a published round, a bye, and a
  joined station.
  """
  alias OpenPairingsPolis.{Plugin, Stations}
  alias PairingsEngine.{Accounts, BoardLinkFixtures, Features, Repo}
  alias PairingsEngine.Accounts.Scope
  alias PairingsEngine.Tournaments.{Pairing, Player, Round}

  @doc "Makes the context's user an admin with the print station switched on."
  def admin_with_feature(%{user: user}) do
    {:ok, _} = Accounts.set_role(user.email, "admin")
    {:ok, user} = user.id |> Accounts.get_user!() |> Features.set_enabled([Plugin.feature()])
    %{user: user, scope: Scope.for_user(user)}
  end

  @doc "The board-link tournament, round 1 unpublished."
  def paired(scope, attrs \\ %{}), do: BoardLinkFixtures.paired_tournament(scope, attrs)

  @doc "Publishes `round` as of a second ago."
  def publish!(%Round{} = round) do
    at = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
    round |> Ecto.Changeset.change(published_at: at) |> Repo.update!()
  end

  @doc "Takes `round` off the public page again."
  def unpublish!(%Round{} = round),
    do: round |> Ecto.Changeset.change(published_at: nil) |> Repo.update!()

  @doc "A fifth player with the bye on board 3 of `round`."
  def add_bye!(%{tournament: t, round: round}) do
    player =
      Repo.insert!(%Player{
        tournament_id: t.id,
        name: "Fifth, Odd",
        pairing_number: 5,
        fide_rating: 1900,
        federation: "BEL"
      })

    Repo.insert!(%Pairing{
      round_id: round.id,
      board: 3,
      white_player_id: player.id,
      black_player_id: nil,
      result: "bye"
    })

    player
  end

  @doc "A station joined to `tournament`, by the front door. `{station, key}`."
  def joined_station!(scope, tournament, device \\ "polis-device-1") do
    {:ok, %{code: code}} = Stations.create_join_code(scope, tournament)

    {:ok, station, key, _t} =
      Stations.redeem(code, %{device: device, name: "Hall PC", software: "polis 0.1.0"})

    {station, key}
  end

  @doc "The hello frame a station sends."
  def hello(device, key, v \\ 1) do
    Jason.encode!(%{
      type: "hello",
      v: v,
      device: device,
      key: key,
      name: "Hall PC",
      software: "polis 0.1.0"
    })
  end
end
