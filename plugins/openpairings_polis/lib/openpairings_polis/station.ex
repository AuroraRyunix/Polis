defmodule OpenPairingsPolis.Station do
  @moduledoc """
  A print station: one hall PC joined to one tournament. The key it was
  given is kept only as its SHA-256 (`key_hash`); `status` is whatever the
  station last said about itself (`printer`, `last_printed_round`).

  `name` and `room` are the station's to say and OpenPairings' to change;
  `filter_categories` and `filter_boards` decide what it prints, empty
  meaning everything (`OpenPairingsPolis.Stations.update_settings/2`).
  """
  use Ecto.Schema

  schema "polis_stations" do
    field :device_id, :string
    field :name, :string, default: ""
    field :room, :string, default: ""
    field :filter_categories, {:array, :string}, default: []
    field :filter_boards, :string, default: ""
    field :software, :string, default: ""
    field :key_hash, :string, redact: true
    field :status, :map, default: %{}
    field :last_seen_at, :utc_datetime
    field :connected, :boolean, default: false
    field :connection_ref, :string
    field :revoked_at, :utc_datetime

    belongs_to :tournament, PairingsEngine.Tournaments.Tournament

    timestamps(type: :utc_datetime)
  end
end
