defmodule Polis do
  @moduledoc """
  Polis, the print station of a chess hall. It joins tournaments in
  OpenPairings through a join link, keeps a line open to each, and prints
  the pairings list and the place cards of every newly published round on
  the printer of the machine it runs on - once, and again only when
  somebody asks.

  The pieces: `Polis.Join` and `Polis.Link` (the hall-link protocol,
  `docs/protocol.md`), `Polis.Station` (what to do with a round),
  `Polis.Queue` (one job at a time), `Polis.Layout` and `Polis.Pdf` (the
  sheets), `Polis.Printer` (the roads to a printer), and `Polis.State`
  (the one file that remembers).
  """
end
