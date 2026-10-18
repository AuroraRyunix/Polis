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

## [0.1.0] - 2026-10-18

- [Feature] **A print station for the hall.** Polis joins a tournament in OpenPairings with a join link, keeps a line open to it, and prints the pairings list and the place cards of every newly published round on the printer of the machine it runs on. Once per round, which is the number of times anyone wants a pairings list taped to a pillar.
- [Feature] **It does not reprint behind anybody's back.** A round the arbiter changes after it came out of the printer is not printed again by itself; the page says "changed since it was printed" and offers Reprint. "Print round N again" in OpenPairings prints what it names, at once.
- [Feature] **Switches per tournament:** the pairings list and the place cards each on or off, and one to five copies of the list. Without a printer chosen, jobs wait in the queue and go when one is; Polis never guesses which printer is the hall's, because the bar's printer would be a guess too.
- [Feature] **A queue you can read.** The last fifty jobs with what happened to each - waiting for a printer, queued, printing, printed, or failed with the printer's own words - a Reprint button, and the PDF of every sheet in the browser.
- [Feature] **Its own sheets.** The pairings list (board, both players, rating and points, a bye where there is one, the header and the page number on every page) and tent-shaped place cards with the upper half upside down and a fold line, laid out on A4 or Letter. Long names are made smaller and then cut, never spilled into the next column.
- [Feature] **Two roads to paper.** CUPS on Linux and macOS, with a small PDF writer of its own; Windows PowerShell and the printer's driver on Windows, which every Windows 10 and 11 has, so nothing is installed beside it. A dry run writes PDFs instead, and development and the tests never use anything else.
- [Feature] **The page and its help in English and Dutch**, the language remembered per browser. The sheets speak the tournament's language, since the players read them and not whoever has the page open.
- [Feature] **Releases**: a Windows installer that updates itself and a portable zip, Linux archives for PCs and the Raspberry Pi with a one-line installer and a systemd service, and an Apple Silicon Mac app. An update waits for a sheet that is printing, unless it is told twice, and says so on every page including the help; a launcher's Details panel says how many jobs are waiting, which printer is chosen and how many lines are up.
