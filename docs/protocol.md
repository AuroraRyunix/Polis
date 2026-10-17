# The hall link, as Polis speaks it

Version 1 of the hall-link protocol between OpenPairings and a hall
program, with Polis (product `polis`) as the program. The server side is
`plugins/openpairings_polis` (`docs/openpairings-integration.md`); this side
is `Polis.Join`, `Polis.Link` and `Polis.Protocol`.

The station always dials out: one HTTP request to join, then one outgoing
WebSocket per tournament. Nothing in the hall is listened on for the
server.

## Joining

The arbiter makes a join link in OpenPairings:
`https://<server>/p/polis/join/<code>`. Any prefix before `/p/polis/join/`
is the server's (a sub-path, a port); the code is good once, for fifteen
minutes, for one tournament.

Polis posts to that exact URL:

```json
{"v": 1, "device": "<device id>", "name": "<machine name>", "software": "polis 0.1.0"}
```

`device` is made once per data folder and never changes; joining the same
tournament again from the same device replaces the key.

| Answer | Means | The page says |
|---|---|---|
| 200 `{"key", "socket", "server", "tournament": {"id", "name"}}` | joined | Joined |
| 404, 410 | the code is used or expired | make a new one |
| 409 | another protocol version | update one of the two |
| anything else, or not JSON of that shape | not an OpenPairings server | that address is not one |
| no connection | | the server does not answer from here |

A link whose product is not `polis` (`/p/nunki/join/...`) is refused before
anything is sent: the code stays unspent for the program it was made for.

`key` goes into `state.json` and nowhere else: not onto the page, not into
a log, not into a URL. `socket` is an absolute path on the same host and
port as the link: `ws://` for an `http://` link, `wss://` for `https://`.

## The line

```
station                                  server
   |-- hello {v, device, key, name, software} -->|
   |<-- welcome {v, server, tournament} ---------|
   |<-- round {round: payload} ------------------|   the latest published round, if any
   |-- status {printer, last_printed_round} ---->|   after welcome, and on every change
   |                 ...                         |
   |<-- round {round: payload} ------------------|   a newer round, or the same one changed
   |<-- print {round, what} --------------------|   "Print round N again"
   |-- leave ----------------------------------->|   Remove on the station's page
   |<-- leave -----------------------------------|   Remove in OpenPairings
```

Every frame is a JSON object with a `type`.

Station to server:

- `hello`: `v` (1), `device`, `key`, `name`, `software`. The key travels in
  this frame, never in the URL.
- `status`: `printer` (the chosen printer's name, or null) and
  `last_printed_round` (the highest round of this tournament whose sheets
  came out of the printer, or null). Sent after `welcome` and whenever
  either changes; never twice the same.
- `leave`: the station is removing the tournament.

Server to station:

- `welcome`: `v`, `server`, `tournament` `{id, name}`. The name is kept.
- `refused`: `reason` is `version`, `key` or `revoked`. `revoked` means
  forget the tournament; the others are shown and tried again in a minute
  (a key the server does not know today may be a server restored from
  yesterday's backup tomorrow).
- `round`: `round` is the payload below.
- `print`: `round` and `what` (`pairings`, `placecards` or `both`). Acted
  on only for the round the station holds.
- `leave`: the station was removed in OpenPairings; forget the tournament.

Keeping it up: a WebSocket ping every 25 seconds; a line that has said
nothing for 75 is taken for dead. After a drop: try again after 1 second,
then 2, 4, ... up to 30. After a refusal: 60.

## The round payload

```json
{
  "tournament": {"id": "t-1", "name": "Club Open", "city": "Gent", "dates": "2026-10-17"},
  "round": 3, "rounds": 7,
  "published_at": "2026-10-17T19:30:00Z",
  "locale": "nl",
  "rating_label": "Elo",
  "team": false,
  "rev": "2c1f...",
  "boards": [
    {"board": "1",
     "white": {"name", "spoken", "title", "rating", "federation", "club", "number", "score"},
     "black": {...},
     "bye": null},
    {"board": "12", "white": {...}, "black": null, "bye": "bye"}
  ]
}
```

- `board` is a string (team boards are "3.1").
- `rating` is an integer; 0 is unrated and is left off the sheet.
- `locale` is the language the sheets are printed in.
- `rev` changes whenever anything printed would change. The station keeps,
  per round, the `rev` it printed: a new round prints; a known round with
  another `rev` is "changed since it was printed" and waits for a person;
  a known round with the same `rev` is a reconnect and does nothing.
- `spoken` and `club` are not printed by Polis; the announcer uses the
  first.

## What Polis does not do with it

It does not print a round that was taken back (the server never sends
one), it never prints an older round than the one it holds, and it does
not keep rounds other than the latest: the queue's jobs keep their own copy
of the payload they were made from, so a Reprint prints what was printed.
