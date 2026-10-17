#!/bin/sh
# Removes the Polis program from a box installed with install.sh.
#
#   sudo /opt/polis/uninstall.sh
#
# It removes the service, its units and /opt/polis. It does NOT remove the
# data, the service's settings or the user that owns the data: the joined
# tournaments, their keys and the printed jobs are still there when Polis is
# installed again, and they are yours to delete. The last lines say how.

set -eu

INSTALL_DIR="/opt/polis"
DATA_DIR="/var/lib/polis"
UNIT_DIR="/etc/systemd/system"

main() {
    [ "$(id -u)" = 0 ] || { echo "run this as root: sudo $0" >&2; exit 1; }

    for unit in polis-update.path polis-update.service polis.service; do
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
        rm -f "$UNIT_DIR/$unit"
    done
    systemctl daemon-reload || true

    # The program, and what the updater noted about its last run. Nothing
    # else: the two paths are spelled out so that no variable can be empty.
    rm -rf /opt/polis
    rm -rf /var/lib/polis-update

    echo "Polis is removed from $INSTALL_DIR."
    echo "Your data is untouched, in $DATA_DIR, and so are the settings in /etc/polis."
    echo "Installing Polis again finds both."
    echo "To delete the data for good - there is no way back - that is yours to do:"
    echo "  the folder $DATA_DIR, the folder /etc/polis, and the user 'polis'."
}

main "$@"
