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

# Install the operator's public key. Prefer an inline env var, otherwise a
# mounted file (default /authorized_keys). The key is copied into a root-owned
# file with strict perms so sshd StrictModes accepts it regardless of the
# source file's host ownership.
mkdir -p /root/.ssh
KEYSRC="${SSH_PUBKEY_FILE:-/authorized_keys}"
if [ -n "${SSH_PUBKEY:-}" ]; then
    printf '%s\n' "$SSH_PUBKEY" > /root/.ssh/authorized_keys
elif [ -f "$KEYSRC" ]; then
    cat "$KEYSRC" > /root/.ssh/authorized_keys
fi
if [ -s /root/.ssh/authorized_keys ]; then
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    chown -R root:root /root/.ssh
else
    echo "WARNING: no SSH public key provided; you cannot ssh in." >&2
    echo "         Mount one:  -v ~/.ssh/id_ed25519.pub:/authorized_keys:ro" >&2
    echo "         or pass:    -e SSH_PUBKEY=\"\$(cat ~/.ssh/id_ed25519.pub)\"" >&2
fi

# Start sshd in the background; the container command is the real workload.
mkdir -p /run/sshd
/usr/sbin/sshd

exec "$@"
