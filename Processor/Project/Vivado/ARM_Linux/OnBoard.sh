#!/bin/sh
# BoardClient sends this script as the SSH command so stdin can carry the artifact.
set -eu
action=$1
digest=${2:-}
program=/root/rsd/program.hex
device=/dev/mmcblk0p1

# Serialize each resource, including boot file replacement against a reboot.
case "$action" in
    program/*) lock=/run/rsd-program.lock ;;
    boot/deploy|reboot) lock=/run/rsd-boot.lock ;;
    *) exit 2 ;;
esac
exec 9>"$lock"
flock -n 9 || { echo "Board is busy ($lock)." >&2; exit 1; }

verify() {
    printf '%s  %s\n' "$digest" "$1" | sha256sum -c - >/dev/null
}

case "$action" in
    reboot) exec reboot ;;
    program/run)
        [ -s "$program" ] || { echo "Deploy a HEX before running." >&2; exit 1; }
        if [ -n "$digest" ]; then verify "$program"; fi
        if pidof rsd-loader >/dev/null; then
            echo "An rsd-loader is already running." >&2
            exit 1
        fi
        # The loader polls forever. Treat the operator's Ctrl-C as a normal exit.
        trap 'exit 0' INT
        echo 'Press Ctrl-C to stop rsd-loader.' >&2
        rsd-loader "$program"
        exit $? ;;
esac

temp=
mount_dir=
mounted=
cleanup() {
    if [ -n "$temp" ]; then rm -f "$temp"; fi
    if [ -n "$mounted" ]; then umount "$mount_dir"; fi
    if [ -n "$mount_dir" ]; then rmdir "$mount_dir"; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

case "$action" in
    program/deploy)
        dest=$program
        mkdir -p "${dest%/*}" ;;
    boot/deploy)
        dir=$(awk -v dev="$device" '$1 == dev && $3 == "vfat" { print $2; exit }' /proc/mounts)
        if [ -z "$dir" ]; then
            mount_dir=$(mktemp -d)
            mount -t vfat "$device" "$mount_dir"
            mounted=yes
            dir=$mount_dir
        else
            dir=$(printf '%b' "$dir") # /proc/mounts escapes spaces and backslashes.
        fi
        dest=$dir/boot.bin
        [ -f "$dest" ] || { echo "No boot.bin on $device." >&2; exit 1; } ;;
    *) exit 2 ;;
esac

# Stage on the destination filesystem. A short upload must never replace the last good file.
temp=$(mktemp "${dest%/*}/.rsd-XXXXXX")
cat > "$temp"
verify "$temp"
if [ "$action" = boot/deploy ]; then sync; fi
mv -f "$temp" "$dest"
temp=
sync
printf 'Deployed %s\n' "${dest##*/}"
