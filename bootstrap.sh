#!/bin/sh
# bootstrap.sh — one-time host prep for the proxy-stack Portainer stack.
#
# Run on the docker host (Alpine CT or Debian VM):
#   wget -qO- https://gitea.lengoc.me/apps/proxy-stack/raw/branch/main/bootstrap.sh | sh
# or from a local clone:  sh bootstrap.sh
#
# What it does (idempotent):
#   1. Creates $DATA_DIR/3proxy/logs and $DATA_DIR/fail2ban/data with the
#      jail/filter files from this repo.
#   2. Installs proxy-egress.sh (DOCKER-USER egress isolation for the
#      proxynet bridge) and applies it now + on boot.
# It does NOT touch Portainer — create/redeploy the stack afterwards.
set -eu

REPO_RAW="${REPO_RAW:-https://gitea.lengoc.me/apps/proxy-stack/raw/branch/main}"
DATA_DIR="${DATA_DIR:-/home/Docker}"
PROXY_SUBNET="${PROXY_SUBNET:-172.31.255.0/24}"

fetch() {
  # fetch <repo-relative-path> <dest>
  if [ -f "$(dirname "$0")/$1" ]; then
    cp "$(dirname "$0")/$1" "$2"
  else
    wget -qO "$2" "$REPO_RAW/$1" || curl -fsSL "$REPO_RAW/$1" -o "$2"
  fi
}

echo "==> Creating $DATA_DIR/3proxy/logs and $DATA_DIR/fail2ban/data"
mkdir -p "$DATA_DIR/3proxy/logs" \
         "$DATA_DIR/fail2ban/data/jail.d" \
         "$DATA_DIR/fail2ban/data/filter.d" \
         "$DATA_DIR/fail2ban/data/action.d" \
         "$DATA_DIR/fail2ban/data/db"
chmod 777 "$DATA_DIR/3proxy/logs"

fetch fail2ban/filter.d/3proxy.conf "$DATA_DIR/fail2ban/data/filter.d/3proxy.conf"
fetch fail2ban/jail.d/3proxy.local   "$DATA_DIR/fail2ban/data/jail.d/3proxy.local"
echo "    fail2ban filter+jail installed"

echo "==> Installing egress isolation (subnet $PROXY_SUBNET)"
mkdir -p /usr/local/sbin
fetch egress/proxy-egress.sh /usr/local/sbin/proxy-egress.sh
chmod +x /usr/local/sbin/proxy-egress.sh

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  cat > /etc/systemd/system/proxy-egress.service <<'EOF'
[Unit]
Description=proxy-stack egress isolation (DOCKER-USER)
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/proxy-egress.sh

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable proxy-egress.service >/dev/null 2>&1 || true
  PERSIST="systemd unit proxy-egress.service"
elif command -v rc-update >/dev/null 2>&1; then
  mkdir -p /etc/local.d
  cat > /etc/local.d/proxy-egress.start <<'EOF'
#!/bin/sh
sleep 5
/usr/local/sbin/proxy-egress.sh
EOF
  chmod +x /etc/local.d/proxy-egress.start
  rc-update add local default >/dev/null 2>&1 || true
  PERSIST="Alpine local.d"
else
  PERSIST="NONE — re-run /usr/local/sbin/proxy-egress.sh manually after reboot"
fi

# Docker rewrites iptables when containers start; if dockerd is running,
# apply now too.
if iptables -L DOCKER-USER >/dev/null 2>&1; then
  PROXY_SUBNET="$PROXY_SUBNET" /usr/local/sbin/proxy-egress.sh
else
  echo "    (docker not up yet — rules apply on next boot via $PERSIST)"
fi

cat <<EOF

Done. Next steps in Portainer (https://<host>:9443):
  1. Stacks → Add stack → Repository
     URL:          https://gitea.lengoc.me/apps/proxy-stack
     Compose path: stack.yml
  2. Env vars:
       PROXY_USER=<user>        (default louis)
       PROXY_PASSWORD=<secret>  (REQUIRED)
       DATA_DIR=$DATA_DIR       (default)
       SOCKS_PORT=1080  HTTP_PORT=3128  (defaults; change if occupied)
  3. Deploy the stack, then test:
       curl -x socks5h://\$PROXY_USER:\$PROXY_PASSWORD@<host-ip>:1080 https://api.ipify.org
       curl -x http://\$PROXY_USER:\$PROXY_PASSWORD@<host-ip>:3128  https://api.ipify.org
       # must FAIL (internal-network isolation):
       curl -x socks5h://\$PROXY_USER:\$PROXY_PASSWORD@<host-ip>:1080 http://10.0.0.1

Persistence: $PERSIST
EOF
