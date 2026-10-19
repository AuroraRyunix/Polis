# Polis on macOS

Every push to `main` builds **`Polis.app`** for Apple Silicon, zipped as
`polis-macos-aarch64.zip`, on `macos-15`; a release also gets a build for
**Intel Macs** from macOS 10.13, `polis-macos-x86_64.zip` (see
[Intel Macs](#intel-macs)). It is Alnasl's Mac build with the
names changed and the serial library left out, so most of what is said in
Alnasl's `docs/macos.md` holds here too. What is particular to Polis is
below. None of it has been watched on a real Mac yet.

| | |
|---|---|
| Apple Silicon (M1 and later) | `polis-macos-aarch64.zip`, built on `macos-15`, macOS 11 and newer |
| Intel | `polis-macos-x86_64.zip`, built on `macos-15-intel`, macOS 10.13 and newer, only for a release or a hand-started run |
| Oldest macOS | what `build_app.sh` finds every binary accepts, written into `Info.plist` |
| Signing | ad-hoc until there is a Developer ID (`docs/releasing.md`) |
| Data | `~/Library/Application Support/PolisData` - `state.json`, `jobs/`, the secret. Never inside the app, which `Polis.DataHome` refuses |
| Printing | CUPS, which is macOS's own printing system: `lpstat` for the list, `lp` to print. The printers are the ones in System Settings > Printers & Scanners |

## Intel Macs

macOS 10 exists only on Intel Macs, so the Intel build is also the one that
reaches back. It is `polis-macos-x86_64.zip`, compiled on GitHub's Intel
runner (`macos-15-intel`; a real Intel machine, nothing is cross-compiled)
with `MACOSX_DEPLOYMENT_TARGET=10.13`, which `build_otp.sh` and
`build_app.sh` read like the Apple Silicon build reads 11.0.

It is built **only when a release is published** (a version bump on `main`
with its changelog section) **or when the workflow is started by hand**
(*Actions > Build and release > Run workflow*), never on an ordinary push or
pull request: the Intel runner is slow, which is why Intel was dropped on
2026-10-14. The `plan` job in `release.yml` decides, from the release's own
two conditions, and adds the Intel target to the build matrix when it
should run. A release that cannot build for Intel is not published. A
hand-started run on a branch builds everything and publishes nothing: the
`release` job runs only on `main` or a tag.

Polis's update notice picks the zip that matches the Mac it is on
(`Polis.Updates.arch/0`): an Intel Mac gets `polis-macos-x86_64.zip`, an
Apple Silicon Mac `polis-macos-aarch64.zip`, and an Intel Polis running
under Rosetta on an Apple Silicon Mac still counts as Apple Silicon
(`sysctl.proc_translated`). `Polis.Updates.no_build?/1` is now false
everywhere.

### How far back

10.13 (High Sierra) is where the Intel build stops. The proof is in the
smoke test's log: it lists the `minos` of every Mach-O file in the bundle
(`vtool -show-build`) and `LSMinimumSystemVersion` in `Info.plist`, which the
test also compares with the target; `build_app.sh` fails the build, naming
the files, if any asks for more. The launcher is Swift, and macOS before
10.14.4 has no Swift runtime, so the libraries it uses are copied into
`Contents/Frameworks` by `swift-stdlib-tool` and found through an `@rpath`.
A few Foundation and AppKit calls it made are 10.14 or 10.15 and newer
(`scrollableTextView()`, `FileHandle.seekToEnd()` and relatives,
`monospacedSystemFont`); `Launcher.swift` asks `#available` and uses the
older call on 10.13.

**Not tested on a real Mac running 10.13.** The runner is macOS 15. What CI
proves is that nothing in the bundle asks for more than 10.13 and that the
app starts and answers on a current macOS. Whether 10.13 runs it, and
whether CUPS printing works there, is for a person with a Mac that old.

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
