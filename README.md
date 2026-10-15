# proxy-stack

Standardized authenticated proxy node for the lengoc.me fleet —
**SOCKS5 :1080 + HTTP CONNECT :3128**, fail2ban, and egress isolation that
makes the container unable to reach the internal network (same spirit as
the NetBird exit-node exitguard).

Fully self-contained: **no host prep, no SSH** — create the Portainer
stack, fill the env vars, deploy.

Canonical repo: `https://gitea.lengoc.me/apps/proxy-stack`
(GitHub `ngojclee/proxy-stack` is a push mirror.)

## Layout

| File | Purpose |
|---|---|
| `Dockerfile` | 3 build targets: `proxy` (3proxy + baked config + env creds), `f2b` (fail2ban + baked filter/jail), `guard` (egress isolation loop) |
| `entrypoint.sh` | renders `/tmp/passwd` from `PROXY_USER`/`PROXY_PASSWORD` env |
| `config/3proxy.cfg` | standard config — `auth strong`, `deny` all private/link-local/CGNAT destinations before `allow *`, public DNS only |
| `stack.yml` | Portainer repo-build stack — 3 services, all built from this repo |
| `fail2ban/` | filter + jail baked into the f2b image (ban via `DOCKER-USER`, `bantime = -1`) |
| `egress/proxy-egress.sh` | `DOCKER-USER` policy applied by the guard container every 60s |

## Deploy a node

Portainer → Stacks → Add stack → **Repository**:

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

Then verify:

```sh
curl -x socks5h://USER:PASS@<host-ip>:1080 https://api.ipify.org   # expect 200
curl -x http://USER:PASS@<host-ip>:3128 https://api.ipify.org     # expect 200
curl -x socks5h://USER:PASS@<host-ip>:1080 http://10.20.0.1       # must FAIL — internal isolation
```

## Update / reinstall / wipe

- **Update config or images**: push to this repo → Portainer stack → *Pull and redeploy* (rebuilds all 3 images on the host).
- **Wipe a node**: delete the stack → `rm -rf $DATA_DIR/3proxy $DATA_DIR/fail2ban` → redeploy.

## Security notes

- Proxy **clients can never edit config** — rootfs `read_only`, config baked
  into the image, no admin service, secrets come from env only.
- Two independent layers block pivoting into `10/8`, `192.168/16`,
  `172.16/12`, `100.64/10` (NetBird), loopback, link-local, multicast:
  the 3proxy `deny` ACL and the guard container's `DOCKER-USER` egress rules.
- fail2ban ignores internal ranges — LAN/mesh clients are never banned.
  It only matters if 1080/3128 ever get a WAN port-forward.
- Never publish the proxy ports on WAN without reviewing the deny list
  first — the ACL is the last line once creds leak.

## Fleet endpoints (current)

| Node | Address | Notes |
|---|---|---|
| VN saigon2 | `10.20.1.105:1080/3128` | CT105 alpine-docker |
| FR paris1 | `10.21.1.101:1080/3128` | CT101 alpine-docker (replaces old squid :3128) |
