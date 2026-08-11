# OAK4 oakapp base images

This repository contains the Dockerfiles used to build Luxonis OAK4 oakapp
base images. Use a published image as the starting point for an oakapp, or
build one locally to inspect or customize it.

## Image variants

| Image | Dockerfile | Use case |
|---|---|---|
| `luxonis/oakapp-base:<version>` | `Dockerfile.py312` | Default Python 3.12 image |
| `luxonis/oakapp-base:<version>-py311` | `Dockerfile.py311` | Python 3.11 |
| `luxonis/oakapp-base:<version>-py310` | `Dockerfile.py310` | Python 3.10 |
| `luxonis/oakapp-base:<version>-cpp` | `Dockerfile.c++` | C++ applications |
| `luxonis/oakapp-base:<version>-onnxruntime` | `Dockerfile.onnxruntime` | ONNX Runtime QNN applications on the OAK4 NPU |

The Python images are based on `debian:bookworm-slim` and include Python built
for OAK4.

## Use a base image

Use a published image as the base for an app image:

```Dockerfile
FROM luxonis/oakapp-base:<version>

COPY . /app
WORKDIR /app

ENTRYPOINT ["/entrypoint.sh", "python3", "-u", "/app/main.py"]
```

Choose the tag matching the Python version or runtime your app needs from the
table above.

## ONNX Runtime QNN image

`Dockerfile.onnxruntime` extends the Python 3.12 image to run ONNX Runtime
with the QNN Execution Provider on the OAK4 Hexagon NPU.

### What it includes

- `libatomic1`, required by the QNN EP CPU-side libraries;
- preinstalled `onnxruntime` and `onnxruntime-qnn`;
- `ADSP_LIBRARY_PATH=/opt/qnn-libs`, pointing at the QNN wheel's Hexagon
  libraries;
- `LD_LIBRARY_PATH=/opt/luxonis/npu-runtime/lib`, resolving FastRPC from the
  OS-provided NPU runtime package.

The required FastRPC libraries are provided by the device OS in
`/opt/luxonis/npu-runtime/lib`; they are not included in this image. Mount the
NPU runtime package as shown below.

### App Dockerfile

Build an NPU-enabled app image from the ONNX Runtime base image:

```Dockerfile
FROM luxonis/oakapp-base:<version>-onnxruntime

COPY . /app
WORKDIR /app

ENTRYPOINT ["/entrypoint.sh", "python3.12", "-u", "/app/main.py"]
```

### `oakapp.toml` configuration

Apps must use the standard entrypoint and pass through the NPU devices and
the scoped device NPU runtime package in `oakapp.toml`:

```toml
entrypoint = ["/entrypoint.sh", "python3.12", "-u", "/app/main.py"]
optional_devices = [
    "/dev/fastrpc-cdsp", # ONNX Runtime QNN device probe
    "/dev/adsprpc-smd",  # libcdsprpc.so FastRPC transport
    "/dev/dma_heap/qcom,system",
    "/dev/dma_heap/system",
]

optional_mounts = ["/opt/luxonis/npu-runtime:/opt/luxonis/npu-runtime:ro,rbind"]

# Grants read/write access to the devices mounted above without pinning
# OS-specific major numbers.
allowed_devices = [{ allow = true, access = "rw" }]
```

`/dev/fastrpc-cdsp` is required for ONNX Runtime QNN device discovery, while
`libcdsprpc.so` uses `/dev/adsprpc-smd` for the actual FastRPC transport. Both
device entries are required.

### Build the ONNX Runtime image

```bash
docker build -f Dockerfile.onnxruntime --platform=linux/arm64 -t oakapp-base:onnxruntime .
```

## Build images locally

Build the standard images locally under your own tags:

```bash
docker buildx build -f Dockerfile.py312 --platform=linux/arm64 -t my-oakapp-base:py312 .
docker buildx build -f Dockerfile.py311 --platform=linux/arm64 -t my-oakapp-base:py311 .
docker buildx build -f Dockerfile.py310 --platform=linux/arm64 -t my-oakapp-base:py310 .
docker buildx build -f Dockerfile.c++ --platform=linux/arm64 -t my-oakapp-base:cpp .
```

To pin a specific `oak_webrtc` release instead of the current stable release:

```bash
docker buildx build -f Dockerfile.py312 --platform=linux/arm64 \
  --build-arg OAK_WEBRTC_VERSION=0.1.1 -t my-oakapp-base:py312 .
```

## Included components

- `nginx` for static files and reverse proxying; self-signed certificates are
  generated during the image build.
- `runit` for service supervision.

### `oak_webrtc`

`oak_webrtc` handles WebRTC connection establishment and data streaming over
the internet using Luxonis signaling infrastructure. Its source is maintained
in a private Luxonis repository and is not included here.

The binary is downloaded during image build from the Luxonis release bucket
and verified against its published SHA-256 checksum (see
[`scripts/fetch-oak-webrtc.sh`](scripts/fetch-oak-webrtc.sh)):

```text
<OAK_WEBRTC_BASE_URL>/oak_webrtc/version
<OAK_WEBRTC_BASE_URL>/oak_webrtc/data/<version>/<linux_x86_64|linux_aarch64>/oak_webrtc[.sha256]
```

| Argument | Default | Description |
|---|---|---|
| `OAK_WEBRTC_VERSION` | empty | Version to install; empty resolves the current stable version at build time. |
| `OAK_WEBRTC_BASE_URL` | `https://webrtc-releases.luxonis.com` | Release bucket base URL. |

The resolved version is recorded at
`/usr/local/share/oak_webrtc.version`, so a published image tag contains a
fixed `oak_webrtc` build.

## Maintainer documentation

Official releases use the **Release images** workflow
([`.github/workflows/release.yml`](.github/workflows/release.yml)). It builds
all image variants and publishes them to Docker Hub and Quay. See
[`MAINTAINERS.md`](MAINTAINERS.md) for workflow and manual release steps.
