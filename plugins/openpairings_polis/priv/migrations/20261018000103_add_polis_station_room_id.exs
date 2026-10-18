defmodule PairingsEngine.Repo.Migrations.AddPolisStationRoomId do
  use Ecto.Migration

  # OpenPairings has rooms of its own now (`tournaments.rooms`), so a
  # station's room is one of them, by the room's id: a rename in Settings,
  # Rooms follows the station, a free-text label could not.
  #
  # Nothing is converted. A room typed before this was free text in a
  # tournament that had no rooms, so it names none; it stays in `room` as a
  # label and, as before, restricts nothing. Picking a real room replaces
  # it; a station that sends the same text back is left alone.
  def change do
    alter table(:polis_stations) do
      add :room_id, :string, null: false, default: ""
    end
  end
end
