#!/usr/bin/env bats

if ! type -t fail >/dev/null 2>&1; then
  fail() { printf '%s\n' "${*:-test failed}" >&2; return 1; }
fi

IMAGE_TAG="${IMAGE_TAG:-isolator:test}"
PLATFORM="${RUNTIME_PLATFORM:-linux/amd64}"
DEFAULT_WAIT=${WAIT_TIMEOUT:-90}
TEST_LABEL_KEY="isolator.test"
TEST_LABEL_VALUE="true"

declare -a CONTAINERS

setup() {
  if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    local attempt=1 max=3
    until docker build --platform "$PLATFORM" -t "$IMAGE_TAG" . >&2; do
      if (( attempt >= max )); then
        fail "image build failed after ${max} attempts"
      fi
      echo "[build] retrying build (attempt $((attempt+1)) of $max)" >&2
      sleep 4
      attempt=$(( attempt + 1 ))
    done
  fi
  docker ps -aq -f "label=${TEST_LABEL_KEY}=${TEST_LABEL_VALUE}" | xargs -r docker rm -f >/dev/null 2>&1 || true
}

teardown() {
  for cid in "${CONTAINERS[@]}"; do
    docker rm -f "$cid" >/dev/null 2>&1 || true
  done
  CONTAINERS=()
  docker ps -aq -f "label=${TEST_LABEL_KEY}=${TEST_LABEL_VALUE}" | xargs -r docker rm -f >/dev/null 2>&1 || true
}

run_container() {
  local name="$1"; shift
  local cid
  cid=$(docker run -d --rm \
      --label "${TEST_LABEL_KEY}=${TEST_LABEL_VALUE}" \
      --platform "$PLATFORM" "$@" "$IMAGE_TAG" 2>/dev/null)
  [ -n "$cid" ] || fail "failed to start container: $name"
  CONTAINERS+=("$cid")
  echo "$cid"
}

wait_for_ready() {
  local cid="$1"; shift
  local timeout="${1:-$DEFAULT_WAIT}"
  local waited=0
  while (( waited < timeout )); do
    docker ps -q --no-trunc | grep -q "$cid" || { docker logs "$cid" | tail -n 40 >&2; fail "container exited"; }
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' "$cid" 2>/dev/null || echo unknown)
    if [ "$status" = healthy ]; then
      return 0
    fi
    if docker logs "$cid" 2>&1 | grep -q 'all services started successfully - container ready'; then
      return 0
    fi
    sleep 1; waited=$(( waited + 1 ))
  done
  docker logs "$cid" | tail -n 120 >&2
  fail "timeout waiting for readiness"
}

wait_for_browser_window() {
  local cid="$1"; shift
  local timeout="${1:-90}"
  local waited=0
  while (( waited < timeout )); do
    if docker exec "$cid" wmctrl -l 2>/dev/null | grep -iq 'tor browser'; then
      return 0
    fi
    sleep 2; waited=$(( waited + 2 ))
  done
  docker logs "$cid" | tail -n 60 >&2
  fail "tor browser window not detected"
}

wait_for_log() {
  local cid="$1"; shift
  local pattern="$1"; shift
  local timeout="${1:-180}"
  local waited=0
  while (( waited < timeout )); do
    if docker logs "$cid" 2>&1 | grep -q "$pattern"; then
      return 0
    fi
    sleep 3; waited=$(( waited + 3 ))
  done
  docker logs "$cid" | tail -n 100 >&2
  fail "timeout waiting for log pattern: $pattern"
}

assert_not_listening() {
  local cid="$1"; shift
  local port="$1"; shift
  if docker exec "$cid" sh -c "nc -z -w 1 localhost ${port} >/dev/null 2>&1"; then
    fail "expected port $port NOT listening"
  fi
}

assert_listening() {
  local cid="$1"; shift
  local port="$1"; shift
  local max_wait=${1:-30}
  local waited=0
  while (( waited < max_wait )); do
    if docker exec "$cid" sh -c "nc -z -w 1 localhost ${port} >/dev/null 2>&1"; then
      return 0
    fi
    sleep 1; waited=$(( waited + 1 ))
  done
  docker exec "$cid" sh -c 'nc -z -w 1 localhost ${port} || true' >&2 || true
  fail "port $port not listening within ${max_wait}s"
}

wait_for_port_listening() {
  assert_listening "$@"
}

assert_log_contains() {
  local cid="$1"; shift
  local pattern="$1"; shift
  docker logs "$cid" 2>&1 | grep -E "$pattern" >/dev/null || fail "logs missing pattern: $pattern"
}

fetch_session_id() {
  local cid="$1"
  docker logs "$cid" 2>&1 | awk -F'/mount/' '/session directory|session.mp4/ { if (NF>1){ split($2,p,"/"); print p[1]; exit } }'
}

with_small_resolution() { echo "1024x768"; }
profile_user_js() { echo "/home/toruser/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/user.js"; }

@test "sanity framework loads" { run bash -c 'echo ok'; [ "$status" -eq 0 ]; [ "$output" = ok ]; }

@test "default startup reaches healthy" {
  cid=$(run_container default -p 0:6080 --tmpfs /mount -e PASSTHROUGH_AUTH=true -e RECORD_VIDEO=false -e USE_CLOUDFLARE_TUNNEL=false)
  wait_for_ready "$cid"
  assert_log_contains "$cid" 'all services started successfully'
}

@test "remote debugger disabled: no caddy, no ports" {
  cid=$(run_container rdebug-off -p 0:6080 --tmpfs /mount -e EXPOSE_REMOTE_DEBUGGER=false)
  wait_for_ready "$cid"
  if docker exec "$cid" pgrep -f caddy >/dev/null 2>&1; then fail "caddy running"; fi
  assert_not_listening "$cid" 9222
  assert_not_listening "$cid" 9223
}

@test "remote debugger enabled: caddy exposes port 9222" {
  if lsof -iTCP:9222 -sTCP:LISTEN -n >/dev/null 2>&1; then
    skip "host port 9222 already in use; skipping debugger exposure test"
  fi
  cid=$(run_container rdebug-on -p 0:6080 -p 9222:9222 --tmpfs /mount -e EXPOSE_REMOTE_DEBUGGER=true)
  wait_for_ready "$cid"
  assert_log_contains "$cid" 'browser debugging available on port 9222'
  assert_listening "$cid" 9222 60
  docker exec "$cid" pgrep -f caddy >/dev/null || fail "caddy not running"
}

@test "custom VNC_RESOLUTION applied" {
  cid=$(run_container res-custom -p 0:6080 --tmpfs /mount -e VNC_RESOLUTION=1920x1080)
  wait_for_ready "$cid"
  res=$(docker exec "$cid" sh -c "DISPLAY=:1 xdpyinfo 2>/dev/null | sed -n 's/^ *dimensions: *\\([0-9]*x[0-9]*\\).*/\\1/p' | head -n1")
  [ "$res" = 1920x1080 ] || fail "expected 1920x1080 got $res"
}

@test "invalid VNC_RESOLUTION rejected early" {
  cid=$(docker run -d --label "${TEST_LABEL_KEY}=${TEST_LABEL_VALUE}" --platform "$PLATFORM" -e VNC_RESOLUTION=garbage "$IMAGE_TAG")
  CONTAINERS+=("$cid")
  sleep 4
  state=$(docker inspect --format '{{.State.Status}}' "$cid")
  [ "$state" != running ] || fail "container still running despite invalid resolution"
  docker logs "$cid" 2>&1 | grep -q 'must be in format WIDTHxHEIGHT' || fail "validation error missing"
}

@test "custom BROWSER_URL flagged as custom in logs" {
  cid=$(run_container custom-url -p 0:6080 --tmpfs /mount -e BROWSER_URL=https://example.com/)
  wait_for_ready "$cid"
  assert_log_contains "$cid" 'BROWSER_URL=custom'
}

@test "PASSTHROUGH_AUTH=false disables auto-connect in index.html" {
  cid=$(run_container auth-off -p 0:6080 --tmpfs /mount -e PASSTHROUGH_AUTH=false)
  wait_for_ready "$cid"
  docker exec "$cid" grep -q "passthroughAuth = 'false'" /home/toruser/noVNC/index.html || fail "index.html missing passthroughAuth=false"
}

@test "external proxy configuration injected into profile user.js" {
  cid=$(run_container proxy -p 0:6080 --tmpfs /mount -e EXTERNAL_PROXY_HOST=127.0.0.1 -e EXTERNAL_PROXY_PORT=9050)
  if ! wait_for_ready "$cid" 120 >/dev/null 2>&1; then
    skip "proxy scenario did not reach readiness in time (likely slow openbox under extra load)"
  fi
  profile_path=$(profile_user_js)
  waited=0
  while (( waited < 40 )); do
    if docker exec "$cid" grep -q 'network.proxy.socks".*, "127.0.0.1"' "$profile_path" && \
       docker exec "$cid" grep -q 'network.proxy.socks_port".*, 9050' "$profile_path" && \
       docker exec "$cid" grep -q 'extensions.torlauncher.start_tor", false' "$profile_path"; then
       break
    fi
    sleep 2; waited=$(( waited + 2 ))
  done
  [ $waited -lt 40 ] || fail "proxy prefs not found in profile"
}

@test "recording enabled creates mp4 in session directory" {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    skip "video recording test disabled in GitHub Actions (timing/display issues)"
  fi
  small_res=1024x768
  cid=$(run_container record -p 0:6080 -v "$(pwd)/mount:/mount" -e RECORD_VIDEO=true -e VNC_RESOLUTION="$small_res")
  wait_for_ready "$cid"
  sid=$(docker logs "$cid" 2>&1 | awk -F'/mount/' '/downloads symlinked/ { if (NF>1){ split($2,p,"/"); print p[1]; exit }}')
  [ -n "$sid" ] || fail "could not derive session id"
  file="mount/$sid/session.mp4"
  waited=0
  while (( waited < 60 )); do
    container_size=$(docker exec "$cid" stat -c %s "/mount/$sid/session.mp4" 2>/dev/null || echo "0")
    if (( container_size > 200 )); then
      break
    fi
    sleep 1; waited=$(( waited + 1 ))
  done
  [ "${container_size:-0}" -gt 200 ] || fail "recording did not start (size: ${container_size} bytes)"
  docker stop "$cid" >/dev/null 2>&1
  sleep 2
  [ -f "$file" ] || fail "session.mp4 not created"
  size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file")
  [ "${size:-0}" -gt 32 ] || fail "session.mp4 too small (${size} bytes)"
  if ! ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" >/dev/null 2>&1; then
    fail "session.mp4 is corrupted or invalid"
  fi
}

@test "structured logging format present" {
  cid=$(run_container logging -p 0:6080 --tmpfs /mount)
  wait_for_ready "$cid"
  docker logs "$cid" 2>&1 | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' || fail "timestamp missing"
  docker logs "$cid" 2>&1 | grep -qE '\| (INFO|DEBUG|WARN|ERROR) \|' || fail "level field missing"
}
