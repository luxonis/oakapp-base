#!/usr/bin/env bash
# Downloads the released oak_webrtc binary from the Luxonis release bucket and
# verifies it against the published sha256 checksum.
#
# Inputs (environment):
#   TARGETARCH            docker build platform arch (amd64 | arm64)
#   OAK_WEBRTC_BASE_URL   base URL of the release bucket
#   OAK_WEBRTC_VERSION    version to install; empty means the current stable one
set -Eeuo pipefail

: "${TARGETARCH:?TARGETARCH must be set}"
: "${OAK_WEBRTC_BASE_URL:?OAK_WEBRTC_BASE_URL must be set}"

DESTINATION="${OAK_WEBRTC_DESTINATION:-/usr/local/bin/oak_webrtc}"
BASE_URL="${OAK_WEBRTC_BASE_URL%/}"

case "$TARGETARCH" in
    amd64) RELEASE_TARGET=linux_x86_64 ;;
    arm64) RELEASE_TARGET=linux_aarch64 ;;
    *) echo "oak_webrtc: unsupported architecture '$TARGETARCH'" >&2; exit 1 ;;
esac

VERSION="${OAK_WEBRTC_VERSION:-}"
if [[ -z "$VERSION" ]]; then
    VERSION=$(curl -fsSL --retry 5 --retry-all-errors "$BASE_URL/oak_webrtc/version")
fi

if [[ ! "$VERSION" =~ ^[0-9A-Za-z._-]+$ ]]; then
    echo "oak_webrtc: invalid version '$VERSION'" >&2
    exit 1
fi

RELEASE_URL="$BASE_URL/oak_webrtc/data/$VERSION/$RELEASE_TARGET"
echo "oak_webrtc: installing $VERSION ($RELEASE_TARGET) from $RELEASE_URL"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL --retry 5 --retry-all-errors -o "$TMP_DIR/oak_webrtc" "$RELEASE_URL/oak_webrtc"
curl -fsSL --retry 5 --retry-all-errors -o "$TMP_DIR/oak_webrtc.sha256" "$RELEASE_URL/oak_webrtc.sha256"

(cd "$TMP_DIR" && awk '{print $1 "  oak_webrtc"}' oak_webrtc.sha256 | sha256sum -c -)

install -m 755 "$TMP_DIR/oak_webrtc" "$DESTINATION"
printf '%s\n' "$VERSION" > /usr/local/share/oak_webrtc.version
