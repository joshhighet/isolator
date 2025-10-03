#!/bin/bash

source /home/toruser/logging.sh

log_debug "browser" "launching Tor Browser with URL: $BROWSER_URL"
log_debug "browser" "EXPOSE_REMOTE_DEBUGGER=${EXPOSE_REMOTE_DEBUGGER:-false}"

REMOTE_DEBUG_FLAG=""
case "${EXPOSE_REMOTE_DEBUGGER:-false}" in
    [Tt][Rr][Uu][Ee])
        REMOTE_DEBUG_FLAG="--remote-debugging-port=9223"
        ;;
esac

/home/toruser/tor-browser/Browser/start-tor-browser \
--new-window "$BROWSER_URL" ${REMOTE_DEBUG_FLAG:+$REMOTE_DEBUG_FLAG} &

for i in {1..6}; do
    sleep 5
    if wmctrl -l | grep -q "Tor Browser"; then
        log_debug "browser" "found Tor Browser window, setting fullscreen borderless"
        wmctrl -r "Tor Browser" -b add,fullscreen
        wmctrl -r "Tor Browser" -b remove,maximized_vert,maximized_horz
        exit 0
    fi
    log_debug "browser" "waiting for Tor Browser window... attempt $i/6"
done

log_error "browser" "could not find Tor Browser window to set fullscreen after 6 attempts"
exit 1
