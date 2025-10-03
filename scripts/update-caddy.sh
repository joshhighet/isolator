#!/bin/bash

fetch_caddy_version() {
    curl -s https://api.github.com/repos/caddyserver/caddy/releases/latest \
    | grep '"tag_name":' \
    | cut -d '"' -f 4 \
    | sed 's/^v//'
}

DOCKERFILE_PATH="dockerfile"
if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "missing target dockerfile at $DOCKERFILE_PATH"
    exit 1
fi

if grep -q "^ARG CADDY_VERSION=" "$DOCKERFILE_PATH"; then
    OLD_VERSION=$(grep "^ARG CADDY_VERSION=" "$DOCKERFILE_PATH" | cut -d '=' -f 2)
    echo "old Caddy version: $OLD_VERSION"
else
    OLD_VERSION="none"
    echo "no existing CADDY_VERSION found (old: $OLD_VERSION)"
fi

CADDY_VERSION=$(fetch_caddy_version)
if [ -z "$CADDY_VERSION" ]; then
    echo "error fetching version"
    exit 1
fi

echo "fetched latest version: $CADDY_VERSION"

if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^ARG CADDY_VERSION[[:space:]]*=.*/ARG CADDY_VERSION=$CADDY_VERSION/" "$DOCKERFILE_PATH"
else
    sed -i "s/^ARG CADDY_VERSION[[:space:]]*=.*/ARG CADDY_VERSION=$CADDY_VERSION/" "$DOCKERFILE_PATH"
fi

if [ "$OLD_VERSION" != "none" ] && [ "$OLD_VERSION" = "$CADDY_VERSION" ]; then
    echo "no update needed, version is same: $CADDY_VERSION"
else
    echo "updated ARG CADDY_VERSION in dockerfile (new: $CADDY_VERSION)"
fi