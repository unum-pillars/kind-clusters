#!/bin/sh
# Put kind, kubectl and tilt in a directory (./bin unless given) for an agent that has Docker and none of them, skipping
# any that are on the PATH already. Usage: scripts/tools.sh [directory]. Pinned to what the clusters are tested with.
set -e

KIND=v0.33.0
KUBECTL=v1.35.0
TILT=0.34.0

DIR=${1:-bin}
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

case $(uname -m) in
x86_64 | amd64) ARCH=amd64; TILT_ARCH=x86_64 ;;
aarch64 | arm64) ARCH=arm64; TILT_ARCH=arm64 ;;
*) echo "no kind, kubectl or tilt for $(uname -m)"; exit 1 ;;
esac

TILT_OS=$OS
test "$OS" != darwin || TILT_OS=mac

mkdir -p "$DIR"

if ! command -v kind >/dev/null; then
    curl -fsSL -o "$DIR/kind" "https://kind.sigs.k8s.io/dl/$KIND/kind-$OS-$ARCH"
    chmod +x "$DIR/kind"
fi

if ! command -v kubectl >/dev/null; then
    curl -fsSL -o "$DIR/kubectl" "https://dl.k8s.io/release/$KUBECTL/bin/$OS/$ARCH/kubectl"
    chmod +x "$DIR/kubectl"
fi

if ! command -v tilt >/dev/null; then
    curl -fsSL "https://github.com/tilt-dev/tilt/releases/download/v$TILT/tilt.$TILT.$TILT_OS.$TILT_ARCH.tar.gz" | tar -xz -C "$DIR" tilt
fi

echo "kind, kubectl and tilt are in $DIR or on the PATH"
