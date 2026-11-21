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
if [ -z "${RSD_SSH_PUBLIC_KEY:-}" ]; then
    # Keep the client private key beside the images, never inside the rootfs.
    # Reuse it across builds so existing SSH clients keep working.
    key="$BINARIES_DIR/rsd-zedboard_ed25519"
    if [ ! -e "$key" ]; then
        test ! -e "$key.pub" || { echo "Private key missing for $key.pub" >&2; exit 1; }
        ssh-keygen -q -t ed25519 -N '' -C rsd-zedboard -f "$key"
    fi
    # Recover a missing public file and verify the private key before installing.
    public_key=$(ssh-keygen -y -P '' -f "$key")
    printf '%s\n' "$public_key" > "$key.pub"
    RSD_SSH_PUBLIC_KEY="$key.pub"
    echo "SSH client key: $key (keep private; only the .pub is installed)"
else
    # Expect one ssh-keygen .pub record. A fingerprint alone can pass for a mixed file.
    if ! awk 'END { exit (NR != 1) }' "$RSD_SSH_PUBLIC_KEY" ||
       ! ssh-keygen -lf - < "$RSD_SSH_PUBLIC_KEY" > /dev/null; then
        echo "Expected one OpenSSH public key in $RSD_SSH_PUBLIC_KEY" >&2
        exit 1
    fi
fi
install -m 0600 "$RSD_SSH_PUBLIC_KEY" "$TARGET_DIR/root/.ssh/authorized_keys"
