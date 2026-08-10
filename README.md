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

The `oak_webrtc` binaries in this repository handle WebRTC connection establishment and data streaming over the internet using Luxonis signaling infrastructure. The source code for this component is maintained in a private Luxonis repository and is not part of this public repository.

## ONNX Runtime (NPU) Variant

`Dockerfile.onnxruntime` extends the py312 image so `onnxruntime` with the
QNN execution provider runs on the OAK4 Hexagon NPU out of the box — no
in-app bootstrapping required. It adds:

- `libatomic1` (needed by the QNN EP CPU-side libraries),
- preinstalled `onnxruntime` + `onnxruntime-qnn`,
- `ADSP_LIBRARY_PATH=/opt/qnn-libs` pointing at the wheel's Hexagon skels,
- an `/etc/entrypoint.d/` hook that links the device-OS FastRPC user-space
  stack (`libcdsprpc.so` + its
  OE dependency chain) into the container's `/usr/lib` from the mounted
  device `/usr/lib`. The FastRPC libraries are proprietary device-OS
  binaries, so they are not shipped in this repository or the image;
  linking them at container start also guarantees they always match the
  running OS.

Apps must route through the standard entrypoint and pass the NPU devices
and the device `/usr/lib` through in `oakapp.toml`:

```toml
entrypoint = ["/entrypoint.sh", "python3.12", "-u", "/app/main.py"]
optional_devices = [
    "/dev/fastrpc-cdsp", # ONNX Runtime QNN device probe
    "/dev/adsprpc-smd",  # libcdsprpc.so FastRPC transport
    "/dev/dma_heap/qcom,system",
    "/dev/dma_heap/system",
]
# Device-OS FastRPC user-space libraries, linked in by the entrypoint hook.
optional_mounts = ["/usr/lib:/host_usr_lib:ro,rbind"]
# oak-agent mounts optional_devices but does not add device-cgroup allow
# rules for them; without these, opening the nodes fails with EPERM
# (FastRPC transport error 1002) and the QNN EP falls back to CPU.
# Grants read/write access to the devices mounted above without pinning
# OS-specific major numbers.
allowed_devices = [{ allow = true, access = "rw" }]
```

Build (linux/arm64 only):

```bash
docker build -f Dockerfile.onnxruntime --platform=linux/arm64 -t oakapp-base:onnxruntime .
```

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

## Luxonis Maintainer Release Steps

Only Luxonis maintainers with registry permissions should publish official images.

Build and push to Docker Hub:

```bash
docker buildx build -f ./Dockerfile.py312 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9 -t luxonis/oakapp-base:latest --push .
docker buildx build -f ./Dockerfile.py311 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-py311 --push .
docker buildx build -f ./Dockerfile.py310 --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-py310 --push .
docker buildx build -f ./Dockerfile.c++ --platform=linux/amd64,linux/arm64 -t luxonis/oakapp-base:1.2.9-cpp --push .
docker buildx build -f ./Dockerfile.onnxruntime --platform=linux/arm64 -t luxonis/oakapp-base:1.2.9-onnxruntime --push .
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
