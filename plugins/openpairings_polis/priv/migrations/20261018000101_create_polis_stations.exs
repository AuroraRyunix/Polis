defmodule PairingsEngine.Repo.Migrations.CreatePolisStations do
  use Ecto.Migration

  # The print station plugin's two tables. Additive only, like every core
  # migration: a build without the plugin never reads them, and a database
  # that once had the plugin keeps working without it.
  def change do
    # One-time join links. Only the code's SHA-256 is kept: the code itself
    # lives for fifteen minutes on one arbiter's screen and nowhere else.
    create table(:polis_join_codes) do
      add :tournament_id, references(:tournaments, on_delete: :delete_all), null: false
      add :code_hash, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:polis_join_codes, [:code_hash])
    create index(:polis_join_codes, [:tournament_id])

    # A hall PC joined to one tournament. Removing it keeps the row with
    # `revoked_at` set, so the next time it calls it hears "revoked" rather
    # than a puzzling "wrong key".
    create table(:polis_stations) do
      add :tournament_id, references(:tournaments, on_delete: :delete_all), null: false
      add :device_id, :string, null: false
      add :name, :string, null: false, default: ""
      add :software, :string, null: false, default: ""
      add :key_hash, :string, null: false
      add :status, :map, null: false, default: %{}
      add :last_seen_at, :utc_datetime
      add :connected, :boolean, null: false, default: false
      add :connection_ref, :string
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:polis_stations, [:tournament_id, :device_id])
    create index(:polis_stations, [:device_id])
  end
end
