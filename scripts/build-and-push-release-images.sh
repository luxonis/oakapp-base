#!/usr/bin/env bash
# Builds and pushes all oakapp-base release images to Docker Hub and Quay.
set -Eeuo pipefail

VERSION="${1:-1.3.0}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
IMAGE_NAME="${IMAGE_NAME:-luxonis/oakapp-base}"
BUILDER_NAME="${BUILDER_NAME:-oakapp-base-multiarch}"

ensure_buildx_builder() {
    if docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
        docker buildx use "$BUILDER_NAME"
    else
        docker buildx create --name "$BUILDER_NAME" --driver docker-container --use
    fi

    docker buildx inspect --bootstrap
}

build_and_push() {
    local registry_prefix="$1"
    local image="${registry_prefix}${IMAGE_NAME}"

    docker buildx build -f ./Dockerfile.py312 --platform="$PLATFORMS" \
        -t "$image:$VERSION" \
        -t "$image:latest" \
        --push .

    docker buildx build -f ./Dockerfile.py311 --platform="$PLATFORMS" \
        -t "$image:$VERSION-py311" \
        --push .

    docker buildx build -f ./Dockerfile.py310 --platform="$PLATFORMS" \
        -t "$image:$VERSION-py310" \
        --push .

    docker buildx build -f ./Dockerfile.c++ --platform="$PLATFORMS" \
        -t "$image:$VERSION-cpp" \
        --push .
}

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ensure_buildx_builder

echo "Building and pushing Docker Hub images for $IMAGE_NAME:$VERSION"
build_and_push ""

echo "Logging in to Quay"
docker login quay.io

echo "Building and pushing Quay images for quay.io/$IMAGE_NAME:$VERSION"
build_and_push "quay.io/"
