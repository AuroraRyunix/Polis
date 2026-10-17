defmodule OpenPairingsPolis.JoinCode do
  @moduledoc """
  A one-time join link's code, by its SHA-256: bound to one tournament,
  good for fifteen minutes, spent on first use.
  """
  use Ecto.Schema

  schema "polis_join_codes" do
    field :code_hash, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :tournament, PairingsEngine.Tournaments.Tournament
    belongs_to :created_by, PairingsEngine.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
