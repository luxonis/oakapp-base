# Base Docker Image for OAK4 oakapps

This repository shows how the Luxonis OAK4 oakapp base images are built. It is public so users can inspect the image contents, reproduce the build locally, or use the published image as a base for their own oakapp image.

Publishing official `luxonis/oakapp-base` images to Docker Hub or Quay is a Luxonis maintainer task.

## Key Features

- Base image: `debian:bookworm-slim` for the Python images.
- Python: built from source with optimizations for OAK4. Images are provided for Python 3.12, 3.11, and 3.10.
- Included services:
  - `nginx` for serving static content and reverse proxying. Self-signed SSL certificates are generated during the build process.
  - `oak_webrtc` binary for DepthAI WebRTC functionality.
  - `runit` for service supervision.

## oak_webrtc Binary

`oak_webrtc` handles WebRTC connection establishment and data streaming over the internet using Luxonis signaling infrastructure. Its source code is maintained in a private Luxonis repository and is not part of this public repository.

The binary is no longer tracked here. It is downloaded during the image build from the Luxonis release bucket and verified against the published `sha256` checksum (see `scripts/fetch-oak-webrtc.sh`):

```text
<OAK_WEBRTC_BASE_URL>/oak_webrtc/version                                        # current stable version
<OAK_WEBRTC_BASE_URL>/oak_webrtc/data/<version>/<linux_x86_64|linux_aarch64>/oak_webrtc[.sha256]
```

Build arguments:

| Arg | Default | Description |
|---|---|---|
| `OAK_WEBRTC_VERSION` | empty | Version to install. Empty resolves the current stable version at build time. |
| `OAK_WEBRTC_BASE_URL` | `https://oakagent-releases.luxonis.com` | Release bucket base URL. |

The resolved version is recorded in the image at `/usr/local/share/oak_webrtc.version`. Because the version is resolved at build time, a published image tag always contains a fixed `oak_webrtc` build.

## Use As A Base Image

Use the published image as the base for your own app image:

```Dockerfile
FROM luxonis/oakapp-base:1.2.8

COPY . /app
WORKDIR /app

ENTRYPOINT ["/entrypoint.sh", "python3", "-u", "/app/main.py"]
```

Python-version-specific tags are also available:

- `luxonis/oakapp-base:1.2.8`
- `luxonis/oakapp-base:1.2.8-py311`
- `luxonis/oakapp-base:1.2.8-py310`
- `luxonis/oakapp-base:1.2.8-cpp`

## Build Locally

To build the images locally under your own tag:

```bash
docker buildx build -f ./Dockerfile.py312 --platform=linux/arm64 -t my-oakapp-base:py312 .
docker buildx build -f ./Dockerfile.py311 --platform=linux/arm64 -t my-oakapp-base:py311 .
docker buildx build -f ./Dockerfile.py310 --platform=linux/arm64 -t my-oakapp-base:py310 .
docker buildx build -f ./Dockerfile.c++ --platform=linux/arm64 -t my-oakapp-base:cpp .
```

To pin a specific `oak_webrtc` release instead of the stable one:

```bash
docker buildx build -f ./Dockerfile.py312 --platform=linux/arm64 --build-arg OAK_WEBRTC_VERSION=0.1.1 -t my-oakapp-base:py312 .
```

## Luxonis Maintainer Release Steps

Preferred path: run the **Release images** workflow (`.github/workflows/release.yml`) with the image version and, optionally, an explicit `oak_webrtc` version. It builds all four images for `linux/amd64,linux/arm64` and pushes them to Docker Hub and Quay.

The manual equivalent, for maintainers with registry permissions:

Build and push to Docker Hub:

```bash
docker buildx build -f ./Dockerfile.py312 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9 -t luxonis/oakapp-base:latest --push .
docker buildx build -f ./Dockerfile.py311 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-py311 --push .
docker buildx build -f ./Dockerfile.py310 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-py310 --push .
docker buildx build -f ./Dockerfile.c++ --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-cpp --push .
```

Log in and push to Quay:

```bash
docker login quay.io

docker buildx build -f ./Dockerfile.py312 --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9 -t quay.io/luxonis/oakapp-base:latest --push .
docker buildx build -f ./Dockerfile.py311 --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9-py311 --push .
docker buildx build -f ./Dockerfile.py310 --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9-py310 --push .
docker buildx build -f ./Dockerfile.c++ --platform=linux/amd64,linux/arm64 -t quay.io/luxonis/oakapp-base:1.2.9-cpp --push .
```

Create and push an annotated git tag for the new base image version:

```bash
git tag -a X.Y.Z <commit_hash> -m "<tagging_message>"
git push origin X.Y.Z
```
