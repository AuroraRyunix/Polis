#!/bin/sh
# Starts Polis from this folder, in this terminal, without installing
# anything: to try it, or on a box you would rather not install a service on.
# install.sh, beside this file, is the other way.
#
# The data goes to ~/.polis (or POLIS_DATA), not into this folder: a new
# version unpacked beside the old one finds it.
set -e
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PORT=${PORT:-4061}
export PORT

# `./polis.sh details [--once | --json]`: the numbers the Windows launcher's
# Details panel shows (version, uptime, CPU, memory, the queue, the printer,
# the links) and the last lines of the log, in this terminal. It asks
# the Polis already running from this data folder, through a second,
# short-lived runtime (`eval` starts nothing of the server); see
# Polis.LauncherDetails.CLI and docs/launcher-details.md.
if [ "${1:-}" = details ]; then
  shift
  exec "$here/bin/polis" eval "Polis.LauncherDetails.CLI.main()" "$@"
fi

echo "Starting Polis on http://localhost:$PORT"
echo "Data: ${POLIS_DATA:-$HOME/.polis}"
echo "Press Ctrl-C to stop it. Nothing is printed while it is stopped."
echo
exec "$here/bin/polis" start
