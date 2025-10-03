#!/bin/bash

log() {
    local level="$1"
    local component="$2"
    shift 2
    local message="$*"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf "%s | %-5s | %-10s | %s\n" "${timestamp}" "${level}" "${component}" "${message}"
}

log_info() { log "INFO" "$1" "${@:2}"; }
log_debug() { log "DEBUG" "$1" "${@:2}"; }
log_warn() { log "WARN" "$1" "${@:2}"; }
log_error() { log "ERROR" "$1" "${@:2}"; }