# isolator

isolator sets up a dockerized, minimal desktop with a pre-configured Tor Browser to access browser-in-browser with noVNC. It is designed for security research, hidden service exploration, file acquisition, and scenarios requiring strong isolation.

```
┌─ actions ─────────┐    ┌─ container ─────────┐    ┌─ external ──────┐
│ auto-updates      │───▶│ openbox             │───▶│ tor network     │
│ launch sessions   │    │ tor browser         │    │ socks5 proxy    │
│ build images      │    │ noVNC server        │◀───│ cf tunnels      │
│ bookmarks gen     │    │ caddy proxy         │    │ remote debugger │
└───────────────────┘    └─────────────────────┘    └─────────────────┘
```

## features

- **isolation**: runs in a containerized debian base
- **remote**: web-based VNC interface for browser-in-browser interaction
- **modular**: runtime flags for external tor circuits, remote debugging, storage integration
- **ephemeral**: unique session IDs with optional persistence for downloads/recordings
- **automated**: CI/CD for tor browser updates, testing, and container builds

## quick start

```shell
# build, test, run
make build
make test
make run        # access at https://localhost:6080

# see all commands
make

# or use pre-built image
docker run -p 6080:6080 ghcr.io/joshhighet/isolator:latest
```

## configuration

common environment variables:

| variable               | description                                    | default       |
|------------------------|------------------------------------------------|---------------|
| BROWSER_URL            | url to load on startup                         | duckduckgo    |
| VNC_RESOLUTION         | desktop resolution                             | 2560x1600     |
| RECORD_VIDEO           | record session to mount point                  | false         |
| EXPOSE_REMOTE_DEBUGGER | enable chrome devtools on port 9222            | false         |
| USE_CLOUDFLARE_TUNNEL  | expose via cloudflare tunnel                   | false         |
| EXTERNAL_PROXY_HOST    | use external socks5 proxy (ip)                 | -             |
| EXTERNAL_PROXY_PORT    | external proxy port                            | -             |
| PORT                   | noVNC web interface port                       | 6080          |
| MOUNT_PATH             | path inside container for mounted storage      | /mount        |
| DEBUG_MODE             | enable bash tracing in entrypoint              | false         |
| BROWSER_URL            | url to load on startup                         | duckduckgo    |
| RECORD_VIDEO           | record the x11 session to mount point          | false         |
| VNC_RESOLUTION         | desktop resolution (widthxheight)              | 2560x1600     |
| EXTERNAL_PROXY_HOST    | ipv4/6 addr of remote socks5 proxy             | -             |
| EXTERNAL_PROXY_PORT    | port of the remote socks5 proxy                | -             |
| USE_CLOUDFLARE_TUNNEL  | use free cloudflare tunnel for external access | false         |
| EXPOSE_REMOTE_DEBUGGER | enable tor browser remote debugging            | false         |
| PASSTHROUGH_AUTH       | auto-connect to vnc with session id            | true          |

## automation

- [`update-tor-browser.yml`](.github/workflows/update-tor-browser.yml) - daily tor browser version updates
- [`update-caddy.yml`](.github/workflows/update-caddy.yml) - daily caddy version updates
- [`update-bookmarks.yml`](.github/workflows/update-bookmarks.yml) - regenerate bookmarks on csv changes
- [`build-and-test.yml`](.github/workflows/build.yml) - build, test, push to ghcr on commits

## browser automation

enable remote debugging to control the browser via chrome devtools protocol (cdp) or webdriver bidi:

```shell
docker run -p 6080:6080 -p 9222:9222 \
  -e EXPOSE_REMOTE_DEBUGGER=true \
  ghcr.io/joshhighet/isolator:latest
```

### cdp examples

requires [wscat](https://github.com/websockets/wscat): `npm install -g wscat`

```bash
# list tabs
curl -s localhost:9222/json | jq
TAB_ID=$(curl -s localhost:9222/json | jq -r '.[0].id')

# connect to tab
wscat -c "ws://localhost:9222/devtools/page/$TAB_ID"

# example commands
{"id":1,"method":"Page.getNavigationHistory"}
{"id":2,"method":"Page.captureScreenshot"}
```

### bidi examples

```bash
wscat -c "ws://localhost:9222/session"
{"id":1,"method":"session.new","params":{"capabilities":{}}}
{"id":2,"method":"browsingContext.getTree","params":{}}
```

[`caddy`](config/caddy/caddyfile) proxies the debugging interface to handle [remote security requirements](https://firefox-source-docs.mozilla.org/remote/Security.html) tor browser inherits from firefox.

## github actions as browser

run ephemeral browser sessions directly in github actions runners using [`launch-session.yml`](.github/workflows/launch-session.yml):

- dispatch via github ui or api
- auto-stops after specified duration
- access via cloudflare tunnel url in logs

## notes

- sessions use unique 32-char hex ids for organizing files: `/mount/$SESSION_ID/file.ext`
- downloads symlinked to mounted storage for persistence
- video recording uses ffmpeg with x11grab
- cleanup trap ensures graceful shutdown
- custom [`user.js`](config/browser/user.js) prefs for tor browser hardening
- enabling remote debugging shows ui warning in tor browser (by design)
- when using external proxy, internal tor is disabled
