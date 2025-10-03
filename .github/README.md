# isolator

isolator sets up a dockerized, minimal desktop with a pre-configured Tor Browser to access browser-in-browser with noVNC. It is designed for security research, hidden service exploration, file acquisition, and scenarios requiring strong isolation.

isolator ensures ephemeral sessions with optional configurable persistence for downloads and session recordings.

```
┌─ actions ─────────┐    ┌─ container ─────────┐    ┌─ external ──────┐
│ auto-updates      │───▶│ openbox             │───▶│ tor network     │
│ launch sessions   │    │ tor browser         │    │ socks5 proxy    │
│ build images      │    │ noVNC server        │◀───│ cf tunnels      │
│ bookmarks gen     │    │ caddy proxy         │    │ remote debugger │
└───────────────────┘    └─────────────────────┘    └─────────────────┘
```

### features

- isolation: runs in a containerized Debian 12 base
- remote: web-based VNC interface for browser-in-browser interaction
- modular: runtime flags for external Tor circuits, remote debugging, storage integration
- can run self-contained within GHA runners and accessed with free CF tunnels

### getting started

#### prereq's

- docker
- local clone: `git clone https://github.com/joshhighet/isolator.git`

## build

```shell
./scripts/build.sh
```

_image is pushed to `ghcr.io/joshhighet/isolator:latest`_

## run

### basic local run

_(access at https://localhost:6080)_

```shell
./scripts/run.sh
```

### using pre-built image

```shell
docker run -p 6080:6080 ghcr.io/joshhighet/isolator:latest
```

## environment options

|     name                | description                                           | default       |
|-------------------------|-------------------------------------------------------|---------------|
| PORT                    | noVNC web interface port                              | 6080          |
| MOUNT_PATH              | path inside container for mounted storage             | /mount        |
| DEBUG_MODE              | enable bash tracing (set -x) in entrypoint.sh.        | false         |
| BROWSER_URL             | URL to load on startup                                | DuckDuckGo    |
| RECORD_VIDEO            | record the X11 session directly to mount point        | false         |
| VNC_RESOLUTION          | desktop resolution (width x height)                   | 2560x1600     |
| EXTERNAL_PROXY_HOST     | hostname or IP of the SOCKS5 proxy                    |               |
| EXTERNAL_PROXY_PORT     | port of the SOCKS5 proxy                              |               |
| USE_CLOUDFLARE_TUNNEL   | use a free Cloudflare Tunnel for external access      | false         |
| EXPOSE_REMOTE_DEBUGGER  | enable Tor Browser remote debugging on port 9222      | false         |

## automatic maintenance

- `update-tor-browser.yml` runs daily to fetch latest Tor Browser version
- `update-caddy.yml` runs daily to fetch latest Caddy version
- `update-bookmarks.yml` runs upon changes to bookmarks.csv to format a NETSCAPE-Bookmark-file

## notes

- sessions use unique hex IDs (32 chars) for organizing files i.e `/mount/$SESSION_ID/file.ext`
- downloads and video files are written directly to mounted storage
- video recording uses FFmpeg with x11grab; output directly to mount point
- cleanup trap ensures graceful shutdown and process cleanup

### github actions as browser

- uses launch-session.yml workflow for on-demand sessions
- inputs: browser_url, vnc_resolution, use_cloudflare_tunnel, keep_alive_duration (seconds).
- runs on Ubuntu, pulls latest image, logs output, auto-stops after duration.
- can dispatch via GitHub UI or API.

### notable

- proxy resolution: if using external SOCKS5 proxy, both EXTERNAL_PROXY_HOST and EXTERNAL_PROXY_PORT must be set
- web debugger: enabling remote debugging shows a UI warning in Tor Browser (by design)
- tor config: internal Tor is disabled when you use an external proxy. custom user.js prefs _try_ enforce certain compensations
- debugging: set DEBUG_MODE=true for entrypoint traces; noVNC logs to /tmp/novnc.log.

### controlling

if you enable debug you can connect via web debugger at `https://localhost:9222`. this allows agentic tools and automation frameworks such as puppeteer to interface and control the browser via webdriver (bidi) or devtools (cdp).

caddy proxies the debugging interface outside of the container to handle the [remote security requirements](https://firefox-source-docs.mozilla.org/remote/Security.html) Tor Browser inherits from Firefox.

the examples below use [websockets/wscat](https://github.com/websockets/wscat) - `npm install -g wscat`

#### cdp

```bash
# list tabs
curl -s localhost:9222/json | jq
TAB_ID=$(curl -s localhost:9222/json | jq -r '.[0].id')
wscat -c "ws://localhost:9222/devtools/page/$TAB_ID"
# example
{"id":1,"method":"Page.getNavigationHistory"}
{"id":7,"method":"Page.captureScreenshot"}
```

#### bidi

```bash
wscat -c "ws://localhost:9222/session"
{"id":1,"method":"session.new","params":{"capabilities":{}}}
{"id":2,"method":"browsingContext.getTree","params":{}}
```
