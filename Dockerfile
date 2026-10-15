# proxy-stack — standardized 3proxy image for the lengoc.me fleet
# Pin the busybox-based 0.9.5 image (':latest' is scratch without a shell).
FROM 3proxy/3proxy:0.9.5
COPY config/3proxy.cfg /etc/3proxy/3proxy.cfg
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
# Config is baked in; per-node secrets come from env at runtime.
ENTRYPOINT ["/entrypoint.sh"]
