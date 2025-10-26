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

verify_tarball_exists() {
    local version=$1
    local tarball_url="https://dist.torproject.org/torbrowser/${version}/tor-browser-linux-x86_64-${version}.tar.xz"
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" -I "$tarball_url")
    [ "$http_status" = "200" ]
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
# verify the linux tarball actually exists before updating (i.e not just a android release or similar)
if ! verify_tarball_exists "$TOR_VERSION"; then
    echo "warning: linux tarball not found for version $TOR_VERSION"
    echo "checking previous versions for a working release..."
    # get all versions, check in reverse order
    VERSIONS=$(curl -s https://dist.torproject.org/torbrowser/ \
        | grep '/icons/folder.gif' \
        | cut -d '>' -f 3 \
        | cut -d '<' -f 1 \
        | sed 's/\/$//' \
        | grep -v 'a' \
        | sort -Vr)
    TOR_VERSION=""
    for ver in $VERSIONS; do
        if verify_tarball_exists "$ver"; then
            TOR_VERSION="$ver"
            echo "found version: $TOR_VERSION"
            break
        fi
    done
    if [ -z "$TOR_VERSION" ]; then
        echo "error: no version with linux tarball found"
        exit 1
    fi
else
    echo "verified tarball exists for version: $TOR_VERSION"
fi

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
