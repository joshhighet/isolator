#!/bin/bash

set -e

source /home/toruser/logging.sh

cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════╗
║    ██╗███████╗ ██████╗ ██╗      █████╗ ████████╗ ██████╗ ██████╗     ║
║    ██║██╔════╝██╔═══██╗██║     ██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗    ║
║    ██║███████╗██║   ██║██║     ███████║   ██║   ██║   ██║██████╔╝    ║
║    ██║╚════██║██║   ██║██║     ██╔══██║   ██║   ██║   ██║██╔══██╗    ║
║    ██║███████║╚██████╔╝███████╗██║  ██║   ██║   ╚██████╔╝██║  ██║    ║
║    ╚═╝╚══════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝    ║
╚══════════════════════════════════════════════════════════════════════╝
EOF

VNC_RESOLUTION=${VNC_RESOLUTION:-2560x1600}
DEBUG_MODE=${DEBUG_MODE:-false}
MOUNT_PATH=${MOUNT_PATH:-/mount}
PASSTHROUGH_AUTH=${PASSTHROUGH_AUTH:-true}
EXPOSE_REMOTE_DEBUGGER=${EXPOSE_REMOTE_DEBUGGER:-false}
[ "$DEBUG_MODE" = "true" ] && set -x

# check VNC_RESOLUTION format (WIDTHxHEIGHT)
if ! echo "$VNC_RESOLUTION" | grep -qE '^[0-9]+x[0-9]+$'; then
    log_error "isolator" "VNC_RESOLUTION must be in format WIDTHxHEIGHT (e.g., 1920x1080), got: $VNC_RESOLUTION"
    exit 1
fi

# check width and height for bounds
WIDTH=$(echo "$VNC_RESOLUTION" | cut -d'x' -f1)
HEIGHT=$(echo "$VNC_RESOLUTION" | cut -d'x' -f2)
if [ "$WIDTH" -lt 800 ] || [ "$WIDTH" -gt 7680 ] || [ "$HEIGHT" -lt 600 ] || [ "$HEIGHT" -gt 4320 ]; then
    log_error "isolator" "VNC_RESOLUTION dimensions out of range (800x600 to 7680x4320), got: $VNC_RESOLUTION"
    exit 1
fi

SESSION_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n1)
export SESSION_ID
SESSION_DIR="$MOUNT_PATH/$SESSION_ID"
export SESSION_DIR
if [ "$PASSTHROUGH_AUTH" = "false" ]; then
    log_debug "isolator" "generated SESSION_ID: $SESSION_ID (use this id to authenticate)"
else
    log_debug "isolator" "generated SESSION_ID: $SESSION_ID"
fi
sed -i "s/\${SESSION_ID}/$SESSION_ID/g" /home/toruser/noVNC/index.html
sed -i "s/\${PASSTHROUGH_AUTH}/$PASSTHROUGH_AUTH/g" /home/toruser/noVNC/index.html

if [ -z "$BROWSER_URL" ]; then
    log_info "isolator" "starting entrypoint - BROWSER_URL=default"
else
    log_info "isolator" "starting entrypoint - BROWSER_URL=custom"
fi

if [ -n "$EXTERNAL_PROXY_HOST$EXTERNAL_PROXY_PORT" ]; then
    log_info "isolator" "starting entrypoint - EXTERNAL_PROXY=${EXTERNAL_PROXY_HOST}:${EXTERNAL_PROXY_PORT}"
    if ! echo "$EXTERNAL_PROXY_HOST" | grep -qE '^(([0-9]{1,3}\.){3}[0-9]{1,3}|(\[[0-9a-fA-F:]+\]))$'; then
        log_error "isolator" "EXTERNAL_PROXY_HOST needs to be an actual address (no FQDN), got: $EXTERNAL_PROXY_HOST"
        exit 1
    fi
else
    log_info "isolator" "starting entrypoint - EXTERNAL_PROXY=none (using internal tor circuits)"
fi

log_info "isolator" "starting entrypoint - RECORD_VIDEO=$RECORD_VIDEO, DEBUG=$EXPOSE_REMOTE_DEBUGGER"

if [ -z "$BROWSER_URL" ]; then
    export BROWSER_URL="http://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"
    log_info "isolator" "no BROWSER_URL set, using default duckduckgo onion"
else
    # check BROWSER_URL format
    if ! echo "$BROWSER_URL" | grep -qE '^https?://[^[:space:]]+$'; then
        log_error "isolator" "BROWSER_URL must be a valid http/https url, got: $BROWSER_URL"
        exit 1
    fi
    # check v3 dir constraint
    if echo "$BROWSER_URL" | grep -q '\.onion' && ! echo "$BROWSER_URL" | grep -qE '^https?://[a-z2-7]{56}\.onion(/.*)?$'; then
        log_error "isolator" "not a v3 onion url, got: $BROWSER_URL"
        exit 1
    fi
fi

# generate proxy configuration
if [ -n "$EXTERNAL_PROXY_HOST$EXTERNAL_PROXY_PORT" ]; then
    [ -z "$EXTERNAL_PROXY_HOST" ] && { log_error "isolator" "EXTERNAL_PROXY_HOST required with EXTERNAL_PROXY_PORT"; exit 1; }
    [ -z "$EXTERNAL_PROXY_PORT" ] && { log_error "isolator" "EXTERNAL_PROXY_PORT required with EXTERNAL_PROXY_HOST"; exit 1; }
    [ "$EXTERNAL_PROXY_PORT" -lt 1 ] || [ "$EXTERNAL_PROXY_PORT" -gt 65535 ] 2>/dev/null && {
        log_error "isolator" "EXTERNAL_PROXY_PORT must be 1-65535, got: $EXTERNAL_PROXY_PORT"; exit 1; }
    log_debug "isolator" "configuring external socks5 proxy at $EXTERNAL_PROXY_HOST:$EXTERNAL_PROXY_PORT"
    PROXY_CONFIG=$(cat <<EOF
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "$EXTERNAL_PROXY_HOST");
user_pref("network.proxy.socks_port", $EXTERNAL_PROXY_PORT);
user_pref("network.proxy.socks_remote_dns", true);
user_pref("extensions.torlauncher.start_tor", false);
user_pref("extensions.torbutton.use_nontor_proxy", true);
EOF
)
else
    log_debug "isolator" "no external proxy configured - browser will build its own circuits"
    PROXY_CONFIG="// Using default Tor circuits - no proxy configuration needed"
fi

# generate final user.js
{
    grep -v '${PROXY_CONFIG}' /home/toruser/user.js
    echo "$PROXY_CONFIG"
} > /home/toruser/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/user.js

if [ "$RECORD_VIDEO" = "true" ] && [ ! -d "$MOUNT_PATH" ]; then
    log_error "isolator" "RECORD_VIDEO=true but MOUNT_PATH=$MOUNT_PATH not accessible. mount a volume to $MOUNT_PATH"
    exit 1
fi

log_info "vnc" "starting vnc server on resolution $VNC_RESOLUTION"
echo "$SESSION_ID" | tigervncpasswd -f > /home/toruser/.config/tigervnc/passwd
chmod 600 /home/toruser/.config/tigervnc/passwd
tigervncserver :1 -geometry $VNC_RESOLUTION -depth 24 -SecurityTypes VncAuth > /tmp/vnc.log 2>&1 &
VNC_PID=$!
log_debug "vnc" "vnc server started with pid: $VNC_PID"

# vnc logmonitor
tail -f /tmp/vnc.log | grep -i "error\|fail\|warn" | while read line; do
    log "WARN" "vnc" "$line"
done >&2 &

log_debug "isolator" "waiting for openbox to initialize..."
# wait for openbox windowmanager
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -m >/dev/null 2>&1; then
        log_debug "isolator" "openbox initialized successfully"
        break
    fi
    if [ $i -eq 10 ]; then
        log_error "isolator" "openbox failed to initialize after 10 attempts"
        exit 1
    fi
    sleep 1
done

log_info "browser" "launching tor browser"
DISPLAY=:1 /home/toruser/launch-browser.sh &
BROWSER_PID=$!
log_debug "browser" "browser started with pid: $BROWSER_PID"

# start caddy
if [ "$EXPOSE_REMOTE_DEBUGGER" = "true" ]; then
    log_debug "caddy" "waiting 10s for browser debugging interface to start"
    sleep 10
    log_info "caddy" "starting reverse proxy for remote debugging"
    /usr/local/bin/caddy start --config /etc/caddy/caddyfile --adapter caddyfile 2>&1 | while read line; do
        # parse caddy logs
        if echo "$line" | grep -q '"level":'; then
            level=$(echo "$line" | sed -n 's/.*"level":"\([^"]*\)".*/\1/p' | tr '[:lower:]' '[:upper:]')
            msg=$(echo "$line" | sed -n 's/.*"msg":"\([^"]*\)".*/\1/p')
            log "${level:-INFO}" "caddy" "$msg"
        else
            log "INFO" "caddy" "$line"
        fi
    done &
    CADDY_STARTED=$?
    if [ $CADDY_STARTED -eq 0 ]; then
        log_info "caddy" "started successfully - browser debugging available on port 9222"
    else
        log_error "caddy" "failed to start reverse proxy"
    fi
else
    log_info "isolator" "remote debugging disabled - no reverse proxy started"
fi

# video recording
if [ "$RECORD_VIDEO" = "true" ]; then
    mkdir -p "$MOUNT_PATH/$SESSION_ID"
    VIDEO_OUTPUT="$MOUNT_PATH/$SESSION_ID/session.mp4"
    log_debug "ffmpeg" "starting video recording to $VIDEO_OUTPUT"
    ffmpeg \
    -f x11grab -s $VNC_RESOLUTION \
    -i :1 -r 30 -codec:v libx264 \
    -movflags frag_keyframe+empty_moov "$VIDEO_OUTPUT" -progress pipe:1 \
    -loglevel warning 2>&1 \
    | while read line; do
        # errors and warnings
        if echo "$line" | grep -qE 'error|Error|ERROR|warning|Warning|WARNING'; then
            log "WARN" "ffmpeg" "$line"
        # periodic progress (~10sec prints)
        elif echo "$line" | grep -q "time=" && [ $(($(date +%s) % 10)) -eq 0 ]; then
            duration=$(echo "$line" | grep -o 'time=[^ ]*' | cut -d= -f2)
            size=$(echo "$line" | grep -o 'total_size=[^ ]*' | cut -d= -f2)
            if [ -z "$size" ]; then
                size=$(echo "$line" | grep -o 'size=[^ ]*' | cut -d= -f2)
            fi
            if [ -n "$duration" ]; then
                if [ -n "$size" ] && [ "$size" != "N/A" ]; then
                    log "INFO" "ffmpeg" "recording progress: $duration (size: $size)"
                else
                    log "INFO" "ffmpeg" "recording progress: $duration"
                fi
            fi
        fi
    done &
    FFMPEG_PID=$!
    log_debug "ffmpeg" "ffmpeg started with pid: $FFMPEG_PID"
else
    log_debug "isolator" "video recording not enabled"
fi

# downloads dir mounting
if [ -d "$MOUNT_PATH" ] && [ -w "$MOUNT_PATH" ]; then
    # symlink for downloads -> mount
    mkdir -p "$SESSION_DIR"
    rm -rf /home/toruser/Downloads
    ln --symbolic "$SESSION_DIR" /home/toruser/Downloads
    log_debug "isolator" "downloads symlinked to $SESSION_DIR"
else
    log_debug "isolator" "mount path not available or not writable - downloads will remain local"
fi

NOVNC_PORT=${PORT:-6080}
log_info "novnc" "starting novnc web proxy on port $NOVNC_PORT"
/home/toruser/noVNC/utils/novnc_proxy --web /home/toruser/noVNC/ \
--cert /home/toruser/certs/cert.pem --key /home/toruser/certs/key.pem \
--vnc localhost:5901 --listen $NOVNC_PORT > /tmp/novnc.log 2>&1 &
NOVNC_PID=$!
log_debug "novnc" "started with pid: $NOVNC_PID"
# filter noVNC logs
tail -f /tmp/novnc.log | grep -v "SSL: SSLV3_ALERT_CERTIFICATE_UNKNOWN" | grep -v "SSL: UNEXPECTED_EOF_WHILE_READING" | grep -v "Using installed websockify" | grep -v "Starting webserver and WebSockets proxy" | grep -v "Navigate to this URL" | grep -v "Press Ctrl-C to exit" | grep -v "http.*vnc\.html" | while read line; do
    if [ -n "$line" ]; then
        log "INFO" "novnc" "$line"
    fi
done >&2 &

if [ "$USE_CLOUDFLARE_TUNNEL" = "true" ]; then
    log_debug "cloudflare" "setting up cloudflare tunnel"
    wget --quiet https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 --output-document=/tmp/cloudflared
    chmod +x /tmp/cloudflared
    /tmp/cloudflared tunnel --url http://localhost:6080 --logfile /tmp/cloudflared.log > /dev/null 2>&1 &
    TUNNEL_PID=$!
    log_debug "cloudflare" "tunnel started with pid: $TUNNEL_PID (subsequent logs will show public url)"
    # wait for logfile creation
    sleep 2
    while [ ! -f /tmp/cloudflared.log ]; do
        log_debug "cloudflare" "waiting for log file to be created..."
        sleep 0.5
    done
    log_debug "cloudflare" "log file found, starting log monitor"
    # normalize Cloudflare logs
    tail -f /tmp/cloudflared.log | while read line; do
        # skip empty
        [ -z "$line" ] && continue
        # parse JSON
        if echo "$line" | grep -q '^{.*}$'; then
            level=$(echo "$line" | sed -n 's/.*"level":"\([^"]*\)".*/\1/p' | tr '[:lower:]' '[:upper:]')
            msg=$(echo "$line" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
            # extract public URL
            if echo "$msg" | grep -q "trycloudflare.com"; then
                tunnel_url=$(echo "$msg" | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
                if [ -n "$tunnel_url" ]; then
                    log "INFO" "cloudflare" "⭐️ external URL: $tunnel_url"
                    continue
                fi
            fi
            # filter out noise
            case "$msg" in
                *"Thank you for trying Cloudflare Tunnel. Doing so, without a Cloudflare account"*)
                    # long disclaimer
                    continue ;;
                *"Cannot determine default origin certificate path"*|*"Cannot determine default configuration path"*)
                    # cert complaints
                    continue ;;
                *"+--------------------------------------------------------------------------------------------+"*|*"|  Your quick Tunnel has been created! Visit it at"*|*"| "*|*"+---"*)
                    # ascii tables
                    continue ;;
                *)
                    # log everything else
                    log "${level:-INFO}" "cloudflare" "$msg"
                    ;;
            esac
        fi
    done >&2 &
else
    log_debug "isolator" "cloudflare tunnel not enabled"
fi

cleanup() {
    log_debug "isolator" "received shutdown signal - cleaning up"
    kill -TERM $NOVNC_PID $BROWSER_PID $VNC_PID ${TUNNEL_PID:-} 2>/dev/null || true
    /usr/local/bin/caddy stop 2>/dev/null || true
    wait $NOVNC_PID $BROWSER_PID $VNC_PID ${TUNNEL_PID:-} 2>/dev/null || true
    if [ ! -z "${FFMPEG_PID:-}" ]; then
        log_debug "ffmpeg" "gracefully stopping ffmpeg"
        echo "q" > /proc/$FFMPEG_PID/fd/0 2>/dev/null || kill -INT $FFMPEG_PID 2>/dev/null
        sleep 5
        kill -9 $FFMPEG_PID 2>/dev/null || true
    fi
    # remove empty session directory (skip if video recording enabled)
    if [ "$RECORD_VIDEO" != "true" ] && [ -d "$SESSION_DIR" ]; then
        if [ -z "$(ls -A \"$SESSION_DIR\" 2>/dev/null)" ]; then
            log_info "isolator" "no downloads - removing empty session directory $SESSION_DIR"
            rmdir "$SESSION_DIR" 2>/dev/null || true
        fi
    fi
    log_debug "isolator" "cleanup complete"
    exit 0
}

# startup confirmation
sleep 2
log_info "isolator" "all services started successfully - container ready"
log_info "isolator" "⭐️ webservice: https://localhost:$NOVNC_PORT (session: $SESSION_ID)"
if [ "$EXPOSE_REMOTE_DEBUGGER" = "true" ]; then
    log_info "isolator" "⭐️ controlport: http://localhost:9222"
fi

trap cleanup INT TERM
wait $NOVNC_PID
