#!/bin/sh
set -eu

# Build on the host, not on the board. The prefix is fixed by buildroot.config.
"$HOST_DIR/bin/arm-buildroot-linux-musleabihf-gcc" -O2 -Wall -Wextra \
    "$RSD_ZYNQ_ROOT/ProgramLoader/loader.c" -o "$TARGET_DIR/usr/bin/rsd-loader"
install -m 0644 "$RSD_ZYNQ_ROOT/extlinux.conf" "$BINARIES_DIR/extlinux.conf"

# Root can operate the UIO devices. SSH only accepts the user's public key;
# the local serial console remains available for initial network setup.
cat > "$TARGET_DIR/etc/ssh/sshd_config" <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
Subsystem sftp /usr/libexec/sftp-server
EOF
install -d -m 0700 "$TARGET_DIR/root/.ssh"
rm -f "$TARGET_DIR/root/.ssh/authorized_keys"
if [ -n "${RSD_SSH_PUBLIC_KEY:-}" ]; then
    test -s "$RSD_SSH_PUBLIC_KEY"
    install -m 0600 "$RSD_SSH_PUBLIC_KEY" "$TARGET_DIR/root/.ssh/authorized_keys"
else
    echo 'No RSD_SSH_PUBLIC_KEY: use the serial console to install authorized_keys.' >&2
fi
