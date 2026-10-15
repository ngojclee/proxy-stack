#!/bin/sh
# proxy-egress.sh — host-side egress isolation for the proxy-stack container.
#
# Same spirit as exitguard on the NetBird exit CTs: the proxy container may
# reach the Internet, never the internal network. Installed persistently by
# bootstrap.sh; idempotent — safe to re-run any time.
#
# Scope: only packets FORWARDED out of the dedicated 'proxynet' docker bridge
# (subnet below). The host itself and other containers are untouched.
set -u

SUBNET="${PROXY_SUBNET:-172.31.255.0/24}"
CHAIN="PROXY_EGRESS"

if ! command -v iptables >/dev/null 2>&1; then
  echo "iptables not found — cannot apply egress rules" >&2
  exit 1
fi

iptables -N "$CHAIN" 2>/dev/null || true
iptables -F "$CHAIN"

# DNS: only the public resolvers baked into 3proxy.cfg
for ns in 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4; do
  iptables -A "$CHAIN" -p udp --dport 53 -d "$ns" -j ACCEPT
  iptables -A "$CHAIN" -p tcp --dport 53 -d "$ns" -j ACCEPT
done
iptables -A "$CHAIN" -p udp --dport 53 -j DROP
iptables -A "$CHAIN" -p tcp --dport 53 -j DROP

# No private / loopback / link-local / CGNAT / multicast destinations
for net in 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 \
           169.254.0.0/16 100.64.0.0/10 224.0.0.0/4 240.0.0.0/4; do
  iptables -A "$CHAIN" -d "$net" -j DROP
done

iptables -A "$CHAIN" -j RETURN

# DOCKER-USER sees ALL forwarded packets (inbound DNAT to the container and
# its outbound). Established/related must return first so client replies
# back to LAN clients still flow; then NEW outbound from our subnet jumps
# into the egress policy.
iptables -C DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null \
  || iptables -I DOCKER-USER 1 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -C DOCKER-USER -s "$SUBNET" -j "$CHAIN" 2>/dev/null \
  || iptables -I DOCKER-USER 2 -s "$SUBNET" -j "$CHAIN"

echo "proxy egress policy applied (subnet $SUBNET)"
