defmodule OpenPairingsPolis.RoundPayloadTest do
  use PairingsEngineWeb.ConnCase, async: false

  import OpenPairingsPolis.Fixtures

  alias OpenPairingsPolis.RoundPayload
  alias PairingsEngine.{Accounts, Repo}

  setup :register_and_log_in_user
  setup :admin_with_feature

  test "boards in the printed list's order, with the bye last and spoken names", %{scope: scope} do
    fx = paired(scope)
    add_bye!(fx)
    publish!(fx.round)

    assert {:ok, 1, payload} = RoundPayload.latest(Repo.reload!(fx.tournament))

    assert %{
             "round" => 1,
             "rounds" => 3,
             "team" => false,
             "rating_label" => "Elo",
             "tournament" => %{"name" => "Board Link Open", "city" => "Somewhere"},
             "boards" => [b1, b2, bye]
           } = payload

    assert b1["board"] == "1"
    assert b1["white"]["name"] == "Player 1"
    assert b1["white"]["rating"] == 1990
    assert b1["white"]["number"] == 1
    assert b1["white"]["score"] == "0"
    assert b1["black"]["name"] == "Player 2"
    assert b1["bye"] == nil
    assert b2["board"] == "2"

    assert bye["black"] == nil
    assert bye["bye"] == "bye"
    assert bye["white"]["spoken"] == "Odd Fifth"

    rev = payload["rev"]
    assert rev == RoundPayload.rev(Map.delete(payload, "rev"))
    assert {:ok, _, %{"rev" => ^rev}} = RoundPayload.latest(Repo.reload!(fx.tournament))
  end

  test "nothing while the round is not public", %{scope: scope} do
    fx = paired(scope)
    assert RoundPayload.latest(fx.tournament) == :none
    assert RoundPayload.build(fx.tournament, 1) == :none
  end

  test "the locale is the owner's account language", %{scope: scope, user: user} do
    fx = paired(scope)
    publish!(fx.round)

    assert {:ok, %{"locale" => "en"}} = RoundPayload.build(Repo.reload!(fx.tournament), 1)

    user |> Ecto.Changeset.change(locale: "nl") |> Repo.update!()
    assert {:ok, %{"locale" => "nl"}} = RoundPayload.build(Repo.reload!(fx.tournament), 1)
    assert Accounts.get_user!(user.id).locale == "nl"
  end

  test "spoken names" do
    assert RoundPayload.spoken("Carlsen, Magnus") == "Magnus Carlsen"
    assert RoundPayload.spoken("Magnus Carlsen") == "Magnus Carlsen"
    assert RoundPayload.spoken("Loner,") == "Loner"
  end
end
