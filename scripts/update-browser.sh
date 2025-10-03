#!/bin/bash

fetch_tor_version() {
    curl -s https://dist.torproject.org/torbrowser/ \
    | grep '/icons/folder.gif' \
    | cut -d '>' -f 3 \
    | cut -d '<' -f 1 \
    | sed 's/\/$//' \
    | grep -v 'a' \
    | sort -V \
    | tail -1
}

DOCKERFILE_PATH="dockerfile"
if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "missing target dockerfile at $DOCKERFILE_PATH"
    exit 1
fi

if grep -q "^ARG TOR_VERSION=" "$DOCKERFILE_PATH"; then
    OLD_VERSION=$(grep "^ARG TOR_VERSION=" "$DOCKERFILE_PATH" | cut -d '=' -f 2)
    echo "old TOR version: $OLD_VERSION"
else
    OLD_VERSION="none"
    echo "no existing TOR_VERSION found ?/ (old: $OLD_VERSION)"
fi

TOR_VERSION=$(fetch_tor_version)
if [ -z "$TOR_VERSION" ]; then
    echo "error fetching version"
    exit 1
fi

echo "fetched latest version: $TOR_VERSION"

if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^ARG TOR_VERSION[[:space:]]*=.*/ARG TOR_VERSION=$TOR_VERSION/" "$DOCKERFILE_PATH"
else
    sed -i "s/^ARG TOR_VERSION[[:space:]]*=.*/ARG TOR_VERSION=$TOR_VERSION/" "$DOCKERFILE_PATH"
fi

if [ "$OLD_VERSION" != "none" ] && [ "$OLD_VERSION" = "$TOR_VERSION" ]; then
    echo "no update needed, version is same: $TOR_VERSION"
else
    echo "updated ARG TOR_VERSION in dockerfile (new: $TOR_VERSION)"
fi
