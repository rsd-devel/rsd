#!/bin/sh
# Run from the ARM_Linux Makefile on the development host.
set -eu
action=$1
board=$(cat "$(dirname "$0")/OnBoard.sh")
cd "$RSD_ZYNQ_CLIENT_DIR"

remote() {
    # Only the fixed action and a SHA-256 digest enter the remote shell command.
    ssh "$1" -i "$RSD_ZYNQ_SSH_KEY" -o IdentitiesOnly=yes -l root -- "$RSD_ZYNQ_HOST" \
        "set -- $2 ${3:-}; $board"
}

case "$action" in
    boot/deploy) file=$RSD_ZYNQ_IMAGES/boot.bin ;;
    program/deploy) file=${RSD_ZYNQ_HEX:?Specify RSD_ZYNQ_HEX or use a test-specific zynq/deploy target.} ;;
    program/run) file=${RSD_ZYNQ_HEX:-} ;;
    reboot) file= ;;
    *) exit 2 ;;
esac

digest=
if [ -n "$file" ]; then
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        echo "Missing or empty file: $file. Build it before deploying." >&2
        exit 1
    fi
    digest=$(sha256sum < "$file")
    digest=${digest%% *}
fi
: "${RSD_ZYNQ_HOST:?Set RSD_ZYNQ_HOST to the board hostname or root@address.}"
[ -r "$RSD_ZYNQ_SSH_KEY" ] || { echo "Cannot read SSH key: $RSD_ZYNQ_SSH_KEY" >&2; exit 1; }

if [ -n "$file" ]; then
    remote -T "${action%/*}/deploy" "$digest" < "$file"
fi
case "$action" in
    program/run) remote -tt program/run "$digest" ;; # Ctrl-C reaches the foreground loader.
    reboot)
        remote -T reboot </dev/null
        echo 'Reboot requested. Follow the boot on the serial console.' ;;
esac
