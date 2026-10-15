# proxy-stack — standardized 3proxy node for the lengoc.me fleet.
# Three build targets, all produced by the same repo-build stack:
#   proxy  — 3proxy with baked config + env-driven credentials
#   f2b    — fail2ban with baked filter/jail (only /data/db persisted on host)
#   guard  — tiny loop applying DOCKER-USER egress isolation on the host

# ---------- 3proxy ----------
# Pin the busybox-based 0.9.5 image (':latest' is scratch without a shell).
FROM 3proxy/3proxy:0.9.5 AS proxy
COPY config/3proxy.cfg /etc/3proxy/3proxy.cfg
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
# Config is baked in; per-node secrets come from env at runtime.
ENTRYPOINT ["/entrypoint.sh"]

# ---------- fail2ban ----------
FROM crazymax/fail2ban:latest AS f2b
COPY fail2ban/filter.d/3proxy.conf /data/filter.d/3proxy.conf
COPY fail2ban/jail.d/3proxy.local /data/jail.d/3proxy.local
COPY fail2ban/placeholder.log /data/placeholder.log
COPY f2b-init.sh /f2b-init.sh
RUN chmod +x /f2b-init.sh
ENTRYPOINT ["/f2b-init.sh"]
CMD ["fail2ban-server", "-f", "-x", "-v", "start"]

# ---------- egress guard ----------
FROM alpine:3.21 AS guard
RUN apk add --no-cache iptables ip6tables
COPY egress/proxy-egress.sh /proxy-egress.sh
RUN chmod +x /proxy-egress.sh
# Re-apply on a loop: dockerd restarts/reboots wipe DOCKER-USER contents.
CMD ["sh", "-c", "while :; do /proxy-egress.sh; sleep 60; done"]
