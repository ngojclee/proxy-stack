#!/bin/sh
set -eu

PROXY_USER="${PROXY_USER:-louis}"
PROXY_PASSWORD="${PROXY_PASSWORD:-}"

if [ -z "$PROXY_PASSWORD" ]; then
  echo "ERROR: PROXY_PASSWORD env is required (set it in the Portainer stack env)." >&2
  exit 1
fi

# 3proxy 'users' file — container rootfs is read_only, /tmp is a tmpfs mount.
printf '%s:CL:%s\n' "$PROXY_USER" "$PROXY_PASSWORD" > /tmp/passwd
chmod 644 /tmp/passwd

exec /bin/3proxy /etc/3proxy/3proxy.cfg
