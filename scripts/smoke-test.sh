#!/bin/bash

set -euo pipefail

IMAGE_TAG=${IMAGE_TAG:-isolator:smoke}
RUNTIME_PLATFORM=${RUNTIME_PLATFORM:-linux/amd64}
WAIT_TIMEOUT=${WAIT_TIMEOUT:-120}
POLL_INTERVAL=${POLL_INTERVAL:-3}

declare -a containers=()

cleanup() {
    if [ "${containers+x}" != "x" ]; then
        return
    fi
    for cid in "${containers[@]}"; do
        if docker ps -aq --no-trunc | grep -q "^${cid}$"; then
            docker stop "$cid" >/dev/null 2>&1 || true
            docker rm "$cid" >/dev/null 2>&1 || true
        fi
    done
}

trap cleanup EXIT

log() {
    printf "%s | %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$1" >&2
}

wait_for_health() {
    local cid="$1"
    local waited=0
    while true; do
        status=$(docker inspect --format '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "starting")
        if [ "$status" = "healthy" ]; then
            return 0
        fi
        if [ "$status" = "unhealthy" ]; then
            docker logs "$cid"
            echo "container entered unhealthy state" >&2
            return 1
        fi
        if [ "$waited" -ge "$WAIT_TIMEOUT" ]; then
            docker logs "$cid"
            echo "timeout waiting for container to become healthy" >&2
            return 1
        fi
        sleep "$POLL_INTERVAL"
        waited=$((waited + POLL_INTERVAL))
    done
}

run_case() {
    local name="$1"
    shift
    log "Running smoke case: $name"
    local cid
    cid=$(docker run -d "$@" "$IMAGE_TAG")
    containers+=("$cid")
    wait_for_health "$cid"
    echo "$cid"
}

verify_no_remote_debug() {
    local cid="$1"
    if docker exec "$cid" pgrep -f "caddy" >/dev/null 2>&1; then
        echo "expected remote debugging proxy to be disabled" >&2
        return 1
    fi
    if docker exec "$cid" netstat -tln | grep -q ":9223"; then
        echo "expected no process to be listening on 9223" >&2
        return 1
    fi
}

verify_remote_debug_enabled() {
    local cid="$1"
    local waited=0
    while [ $waited -le 30 ]; do
        if docker exec "$cid" pgrep -f "caddy" >/dev/null 2>&1 && \
           docker exec "$cid" netstat -tln | grep -q ":9223"; then
            return 0
        fi
        sleep 3
        waited=$((waited + 3))
    done
    docker logs "$cid" | tail -n 200
    echo "expected caddy proxy to expose remote debugging within 30s" >&2
    return 1
}

build_image() {
    if [ "${SKIP_BUILD:-0}" = "1" ]; then
        log "Skipping image build as requested (SKIP_BUILD=1)"
        return
    fi
    log "Building image $IMAGE_TAG"
    docker build --platform "$RUNTIME_PLATFORM" -t "$IMAGE_TAG" .
}

main() {
    build_image

    local base_args=(
        --platform "$RUNTIME_PLATFORM"
        --publish 0:6080
        --publish 0:9222
        --tmpfs /mount
        --env USE_CLOUDFLARE_TUNNEL=false
        --env RECORD_VIDEO=false
        --env PASSTHROUGH_AUTH=true
    )

    local cid_disabled
    cid_disabled=$(run_case "remote debugger disabled" "${base_args[@]}" --env EXPOSE_REMOTE_DEBUGGER=false)
    verify_no_remote_debug "$cid_disabled"

    local cid_enabled
    cid_enabled=$(run_case "remote debugger enabled" \
        "${base_args[@]}" \
        --env EXPOSE_REMOTE_DEBUGGER=true)
    verify_remote_debug_enabled "$cid_enabled"

    log "Smoke test completed successfully"
}

main "$@"
