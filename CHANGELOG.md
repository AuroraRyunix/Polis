# Changelog

What changed in Polis, newest first. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and each entry is
tagged so that a version can be skimmed:

| tag | meaning |
|---|---|
| [Feature] | something new you can do |
| [Fix] | something that was broken |
| [Change] | existing behaviour works differently |
| [Removed] | something is gone |
| [Security] | a hole closed, or judged not to be one |
| [Verified] | checked against the real thing, no code change |

## [Unreleased]

## [0.3.0] - 2026-10-18

- [Feature] **The room is a choice now, when the tournament has rooms.** OpenPairings sends the room names with the station's settings, and the station's page offers them in a picker instead of a text field that accepted "Hal", "hal" and "The big room, you know the one". A station in a room prints only the boards that room holds, on top of its board numbers and categories. Nothing picked is every room, as before.
- [Feature] **A room the server does not accept is said.** If OpenPairings turns a room down it keeps what it had, and the page says the room is not one of the tournament's, in the same tone it already used for board numbers that do not parse.
- [Change] **The plug-in keeps a station's room by the room's id**, so renaming "Hall B" to "Annexe" in OpenPairings moves nobody, and removing a room leaves its stations in no room rather than in a room that no longer exists. Board numbers are now read by OpenPairings' own reader; the plug-in's copy retired without ceremony.
- [Change] **An old free-text room survives, but filters nothing.** A label typed before the tournament had rooms stays visible as "not a room of this tournament" until somebody picks a real one. A server that predates rooms sends no list, and gets the free-text field it was always used to.
- [Change] **New address.** The repository moved to github.com/teapot-chess; old links still redirect, out of politeness rather than obligation.
## [0.2.0] - 2026-10-18

- [Change] **Print station moved out of the tournament's top bar and into its Settings**, under Publishing, with the rail beside it. A thing you set up once and then forget about does not get a tab next to Pairings. The station's page now says where to find it: Settings → Print station → Add a print station.
- [Feature] **Each printer prints its own share.** A station can be told which categories and which board numbers it prints (`1-20, 35, 40-45`, read back to you before you save, because typos are the only thing arbiters produce more of than pairings). A board prints when its number is in the list and either player is in a ticked category; a bye answers for its one player. Nothing set is everything, so nobody who ignores this feature notices it exists.
- [Feature] **Name and room, settable from both ends.** The station's page and OpenPairings edit the same settings, OpenPairings keeps them, and a change on one side shows on the other at the next push. Changing them from the hall needs the line up; a change the server cannot hear is a change that did not happen.
- [Feature] **The sheet says which part of the hall it is for.** A station printing a share puts its room, boards and categories in the heading, and a round with nothing for it prints nothing instead of a page announcing an absence.
- [Change] **Joining again keeps the name somebody gave the station**, rather than reverting to the machine's hostname, which nobody chose on purpose.
- [Fix] **Stopping Polis stops Polis, and what it started.** Every `lp`, `lpstat` and PowerShell now has a deadline (fifteen seconds to name the printers, a minute to take a job, two for Windows), past which it is killed and the job fails with a sentence instead of saying "printing" until further notice. A command whose caller is gone is killed too, and whatever is still running when the station stops goes with it: Erlang closes the port and walks away, and the `lp` on the other end used to stay behind, waiting for a printer that was not coming back.
- [Fix] **No part of a stop waits forever.** Every supervisor has a deadline, open browser connections get three seconds instead of fifteen, and on the Mac the launcher's SIGKILL after twenty seconds now reaches the whole tree under the server - the BEAM and the programs it started - rather than the BEAM alone. The app's own last resort, ten seconds later, does the same instead of killing only the script and leaving the server to launchd.

- [Change] **The Print station switch is in the Belgian pack** of OpenPairings' Features, not under "Optional tools for any federation", a heading whose main achievement was never being read.

## [0.1.0] - 2026-10-18

- [Feature] **A print station for the hall.** Polis joins a tournament in OpenPairings with a join link, keeps a line open to it, and prints the pairings list and the place cards of every newly published round on the printer of the machine it runs on. Once per round, which is the number of times anyone wants a pairings list taped to a pillar.
- [Feature] **It does not reprint behind anybody's back.** A round the arbiter changes after it came out of the printer is not printed again by itself; the page says "changed since it was printed" and offers Reprint. "Print round N again" in OpenPairings prints what it names, at once.
- [Feature] **Switches per tournament:** the pairings list and the place cards each on or off, and one to five copies of the list. Without a printer chosen, jobs wait in the queue and go when one is; Polis never guesses which printer is the hall's, because the bar's printer would be a guess too.
- [Feature] **A queue you can read.** The last fifty jobs with what happened to each - waiting for a printer, queued, printing, printed, or failed with the printer's own words - a Reprint button, and the PDF of every sheet in the browser.
- [Feature] **Its own sheets.** The pairings list (board, both players, rating and points, a bye where there is one, the header and the page number on every page) and tent-shaped place cards with the upper half upside down and a fold line, laid out on A4 or Letter. Long names are made smaller and then cut, never spilled into the next column.
- [Feature] **Two roads to paper.** CUPS on Linux and macOS, with a small PDF writer of its own; Windows PowerShell and the printer's driver on Windows, which every Windows 10 and 11 has, so nothing is installed beside it. A dry run writes PDFs instead, and development and the tests never use anything else.
- [Feature] **The page and its help in English and Dutch**, the language remembered per browser. The sheets speak the tournament's language, since the players read them and not whoever has the page open.
- [Feature] **Releases**: a Windows installer that updates itself and a portable zip, Linux archives for PCs and the Raspberry Pi with a one-line installer and a systemd service, and an Apple Silicon Mac app. An update waits for a sheet that is printing, unless it is told twice, and says so on every page including the help; a launcher's Details panel says how many jobs are waiting, which printer is chosen and how many lines are up.
