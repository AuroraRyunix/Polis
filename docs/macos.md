# Polis on macOS

Every push to `main` builds **`Polis.app`** for Apple Silicon, zipped as
`polis-macos-aarch64.zip`, on `macos-15`. It is Alnasl's Mac build with the
names changed and the serial library left out, so most of what is said in
Alnasl's `docs/macos.md` holds here too. What is particular to Polis is
below. None of it has been watched on a real Mac yet.

| | |
|---|---|
| Apple Silicon only (M1 and later) | Intel Macs get "there is no build for this machine" in the update notice |
| Oldest macOS | what `build_app.sh` finds every binary accepts, written into `Info.plist` |
| Signing | ad-hoc until there is a Developer ID (`docs/releasing.md`) |
| Data | `~/Library/Application Support/PolisData` - `state.json`, `jobs/`, the secret. Never inside the app, which `Polis.DataHome` refuses |
| Printing | CUPS, which is macOS's own printing system: `lpstat` for the list, `lp` to print. The printers are the ones in System Settings > Printers & Scanners |

## The app

`Contents/MacOS/Polis` (`rel/macos/Launcher.swift`) starts the release in
`Contents/Resources/app`, opens the browser at `http://localhost:4061`
when the page answers, and shows a small window: the address, *Open in
browser*, *Stop Polis*, *Details*. Stopping asks first, because while
Polis is stopped nothing prints.

## The first start

Downloaded from the internet and not notarised, the app is stopped by
Gatekeeper the first time: System Settings > Privacy & Security, scroll to
"Polis was blocked", **Open Anyway**. Once.

"Polis is damaged and can't be opened" means the quarantine flag on an
ad-hoc signed app, not damage:

```sh
xattr -dr com.apple.quarantine /Applications/Polis.app
```

## Printing from a Mac

- The printer must be added in System Settings first; Polis lists what
  CUPS lists and adds nothing.
- `lp` is given the PDF, the title, the copies and `media=A4` or
  `media=Letter`. A printer whose driver ignores `media` prints on whatever
  is in the tray; the Test print shows that at once.
- The PDF uses Helvetica, which every Mac has; a name without Latin letters
  prints as question marks on this road (`README.md`, "Why Polis lays out
  its own pages").

## Testing a build

With a Mac and a printer: download the zip from the run, open the app as
above, join a tournament from a test OpenPairings, choose the printer,
press Test print (the frame must be whole), publish a round (the pairings
and the place cards must come out once), change a pairing (nothing must
come out; the page says "changed since it was printed"), Reprint, Stop.
Then bin the app and check that the data folder is still there.
