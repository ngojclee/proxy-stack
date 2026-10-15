#!/bin/sh
# fail2ban wrapper: make sure the 3proxy log exists before fail2ban reads
# its jails — the jail fails to configure if the logpath is missing at
# startup (e.g. first deploy before 3proxy has written anything).
set -eu
mkdir -p /var/log/3proxy 2>/dev/null || true
touch /var/log/3proxy/3proxy.log 2>/dev/null || true
exec /entrypoint.sh "$@"
