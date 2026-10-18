defmodule PairingsEngine.Repo.Migrations.AddPolisStationSettings do
  use Ecto.Migration

  # What each print station prints, and where it stands. Additive, like the
  # first: a station from before this has no room and no filters, which is
  # to say it prints everything, as it always did.
  def change do
    alter table(:polis_stations) do
      # Free text. OpenPairings has no rooms of its own; a station knows
      # where it is better than the tournament does.
      add :room, :string, null: false, default: ""
      # Category names the station prints, as a JSON list (the core's own
      # way with `players.categories`). Empty: every category.
      add :filter_categories, :text, null: false, default: "[]"
      # Board numbers as text, "1-20, 35", stored in the reader's own
      # spelling (`OpenPairingsPolis.BoardRanges`). Empty: every board.
      add :filter_boards, :string, null: false, default: ""
    end
  end
end
