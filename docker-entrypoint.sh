#!/usr/bin/env bash
# Prepares SSH then runs the container command.
set -euo pipefail

# Host keys live in /etc/ssh/host_keys so they can be kept on a volume: the
# image ships none, and without persistence every container recreation would
# hand clients a new identity and trip their strict host-key checking.
mkdir -p /etc/ssh/host_keys
chmod 700 /etc/ssh/host_keys
if [ ! -f /etc/ssh/host_keys/ssh_host_ed25519_key ]; then
    ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/host_keys/ssh_host_ed25519_key
fi
if [ ! -f /etc/ssh/host_keys/ssh_host_rsa_key ]; then
    ssh-keygen -q -t rsa -b 4096 -N '' -f /etc/ssh/host_keys/ssh_host_rsa_key
fi
chmod 600 /etc/ssh/host_keys/*_key

# Install the operator's public key for the login user. Prefer an inline env
# var, otherwise a mounted file (default /authorized_keys). The key is copied
# into a file owned by that user with strict perms, so sshd StrictModes accepts
# it regardless of the source file's ownership on the host.
USER_NAME="${TOOLBOX_USER:-toolbox}"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
: "${USER_HOME:=/home/$USER_NAME}"
SSH_DIR="$USER_HOME/.ssh"

mkdir -p "$SSH_DIR"
KEYSRC="${SSH_PUBKEY_FILE:-/authorized_keys}"
if [ -n "${SSH_PUBKEY:-}" ]; then
    printf '%s\n' "$SSH_PUBKEY" > "$SSH_DIR/authorized_keys"
elif [ -f "$KEYSRC" ]; then
    cat "$KEYSRC" > "$SSH_DIR/authorized_keys"
fi
if [ -s "$SSH_DIR/authorized_keys" ]; then
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_DIR/authorized_keys"
    chown -R "$USER_NAME" "$SSH_DIR"
else
    echo "WARNING: no SSH public key provided; you cannot ssh in." >&2
    echo "         Mount one:  -v ~/.ssh/id_ed25519.pub:/authorized_keys:ro" >&2
    echo "         or pass:    -e SSH_PUBKEY=\"\$(cat ~/.ssh/id_ed25519.pub)\"" >&2
fi

echo "toolbox: ssh in as ${USER_NAME}@<host>; root shell via 'docker exec -u 0'" >&2

# Start sshd in the background; the container command is the real workload.
mkdir -p /run/sshd
/usr/sbin/sshd

exec "$@"
