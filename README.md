# proxy-stack

Standardized authenticated proxy node for the lengoc.me fleet —
**SOCKS5 :1080 + HTTP CONNECT :3128**, fail2ban, and egress isolation that
makes the container unable to reach the internal network (same spirit as
the NetBird exit-node exitguard).

Canonical repo: `https://gitea.lengoc.me/apps/proxy-stack`
(GitHub `ngojclee/proxy-stack` is a push mirror.)

## Layout

| File | Purpose |
|---|---|
| `Dockerfile` | alpine + upstream 3proxy binary + baked config + env entrypoint |
| `entrypoint.sh` | renders `/tmp/passwd` from `PROXY_USER`/`PROXY_PASSWORD` env |
| `config/3proxy.cfg` | standard config — `auth strong`, `deny` all private/link-local/CGNAT destinations before `allow *`, public DNS only |
| `stack.yml` | Portainer repo-build stack (3proxy + fail2ban container) |
| `fail2ban/` | filter + jail (ban via `DOCKER-USER`, permanent `bantime = -1`) |
| `egress/proxy-egress.sh` | host `DOCKER-USER` rules: container subnet may only reach the Internet; DNS restricted to public resolvers |
| `bootstrap.sh` | one-time host prep: dirs, fail2ban files, persistent egress rules |

## Deploy a node (per host)

1. **Host prep** (once): on the docker host —

   ```sh
   wget -qO- https://gitea.lengoc.me/apps/proxy-stack/raw/branch/main/bootstrap.sh | sh
   ```

2. **Portainer** → Stacks → Add stack → **Repository**:
   - URL `https://gitea.lengoc.me/apps/proxy-stack`, compose path `stack.yml`, no auth (internal public repo)
   - Env:

     | Var | Required | Default |
     |---|---|---|
     | `PROXY_USER` | | `louis` |
     | `PROXY_PASSWORD` | **yes** | — |
     | `DATA_DIR` | | `/home/Docker` |
     | `SOCKS_PORT` | | `1080` |
     | `HTTP_PORT` | | `3128` |
     | `TZ` | | `Europe/Paris` |

3. **Verify**:

   ```sh
   curl -x socks5h://USER:PASS@<host-ip>:1080 https://api.ipify.org   # expect 200
   curl -x http://USER:PASS@<host-ip>:3128 https://api.ipify.org     # expect 200
   curl -x socks5h://USER:PASS@<host-ip>:1080 http://10.20.0.1       # must FAIL — internal isolation
   ```

## Reinstall / wipe

```sh
docker rm -f 3proxy fail2ban-3proxy
rm -rf "$DATA_DIR/3proxy" "$DATA_DIR/fail2ban"
# re-run bootstrap.sh, then redeploy the stack
```

## Security notes

- Proxy **clients can never edit config** — rootfs `read_only`, cfg baked
  into the image, no admin service, secrets come from env only.
- `deny` ACL + host egress both block pivoting into `10/8`, `192.168/16`,
  `172.16/12`, `100.64/10` (NetBird), link-local, multicast.
- fail2ban ignores internal ranges — LAN/mesh clients are never banned.
- Never publish 1080/3128 on a WAN port-forward without reviewing the deny
  list first — the ACL is the last line once creds leak.

## Fleet endpoints (current)

| Node | Address | Notes |
|---|---|---|
| VN saigon2 | `10.20.1.105:1080/3128` | CT105 alpine-docker, Portainer stack `3proxy` |
| FR paris1 | `10.21.1.101:1080/3128` | CT101 alpine-docker (replaces old squid :3128) |
