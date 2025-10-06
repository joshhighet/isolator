#!/bin/bash

BROWSER_URL=${1:-http://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion}

if docker info --format '{{.Runtimes}}' | grep -q "runsc"; then
    echo "using gvisor runtime"
    RUNTIME_SCFLAG="--runtime=runsc"
else
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "gvisor runtime not detected - you should use gvisor for enhanced isolation"
        echo "ref: https://gvisor.dev/docs/user_guide/install/#install-latest"
        echo "using default runtime"
    fi
    RUNTIME_SCFLAG=""
fi

EXPOSE_REMOTE_DEBUGGER=${EXPOSE_REMOTE_DEBUGGER:-false}
if [[ "$EXPOSE_REMOTE_DEBUGGER" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
    PUBLISH_DEBUG_ARGS=("--publish" "9222:9222")
else
    PUBLISH_DEBUG_ARGS=()
fi

RUN_ARGS=(
    "--rm"
    "--platform" "linux/amd64"
    "--publish" "6080:6080"
    "--volume" "$(pwd)/mount:/mount"
    "--security-opt" "no-new-privileges"
    "--cap-drop" "NET_RAW"
    "--cap-drop" "SYS_PTRACE"
    "--cap-drop" "AUDIT_WRITE"
    "--cap-drop" "MKNOD"
    "--env" "DEBUG_MODE=false"
    "--env" "USE_CLOUDFLARE_TUNNEL=false"
    "--env" "EXPOSE_REMOTE_DEBUGGER=$EXPOSE_REMOTE_DEBUGGER"
    "--env" "BROWSER_URL=$BROWSER_URL"
    "--env" "RECORD_VIDEO=false"
    "--env" "VNC_RESOLUTION=1280x720"
    "--env" "PASSTHROUGH_AUTH=true"
)

if [ -n "$RUNTIME_SCFLAG" ]; then
    RUN_ARGS+=("$RUNTIME_SCFLAG")
fi

if [ ${#PUBLISH_DEBUG_ARGS[@]} -ne 0 ]; then
    RUN_ARGS+=("${PUBLISH_DEBUG_ARGS[@]}")
fi

docker run "${RUN_ARGS[@]}" isolator
