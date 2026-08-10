# OAK4 oakapp base images

This repository contains the Dockerfiles used to build Luxonis OAK4 oakapp
base images. Use a published image as the starting point for an oakapp, or
build one locally to inspect or customize it.

## Image variants

| Image | Dockerfile | Use case |
|---|---|---|
| `luxonis/oakapp-base:1.2.9` | `Dockerfile.py312` | Default Python 3.12 image |
| `luxonis/oakapp-base:1.2.9-py311` | `Dockerfile.py311` | Python 3.11 |
| `luxonis/oakapp-base:1.2.9-py310` | `Dockerfile.py310` | Python 3.10 |
| `luxonis/oakapp-base:1.2.9-cpp` | `Dockerfile.c++` | C++ applications |
| `luxonis/oakapp-base:1.2.9-onnxruntime` | `Dockerfile.onnxruntime` | ONNX Runtime QNN applications on the OAK4 NPU |

The Python images are based on `debian:bookworm-slim` and include Python built
for OAK4.

## Use a base image

Use a published image as the base for an app image:

```Dockerfile
FROM luxonis/oakapp-base:1.2.9

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
- a startup hook that links the device OS FastRPC user-space stack into the
  container from a read-only host-library mount.

At startup, `/entrypoint.sh` sources shell hooks in `/etc/entrypoint.d`. The
ONNX Runtime image installs `npu-setup.sh` there; it links the mounted FastRPC
libraries before the application starts. `ADSP_LIBRARY_PATH` is set by the
image itself, so it is also available when an application uses a custom
entrypoint.

### App Dockerfile

Build an NPU-enabled app image from the ONNX Runtime base image:

```Dockerfile
FROM luxonis/oakapp-base:1.2.9-onnxruntime

COPY . /app
WORKDIR /app

ENTRYPOINT ["/entrypoint.sh", "python3.12", "-u", "/app/main.py"]
```

### `oakapp.toml` configuration

Apps must use the standard entrypoint and pass through the NPU devices and
device `/usr/lib` in `oakapp.toml`:

```toml
entrypoint = ["/entrypoint.sh", "python3.12", "-u", "/app/main.py"]

optional_devices = [
    "/dev/fastrpc-cdsp", # ONNX Runtime QNN device probe
    "/dev/adsprpc-smd",  # libcdsprpc.so FastRPC transport
    "/dev/dma_heap/qcom,system",
    "/dev/dma_heap/system",
]

optional_mounts = ["/usr/lib:/host_usr_lib:ro,rbind"]

# Grants read/write access to the devices mounted above without pinning
# OS-specific major numbers.
allowed_devices = [{ allow = true, access = "rw" }]
```

`/dev/fastrpc-cdsp` is required for ONNX Runtime QNN device discovery, while
`libcdsprpc.so` uses `/dev/adsprpc-smd` for the actual FastRPC transport. Both
device entries are required.

For hook details and troubleshooting, see [`npu/README.md`](npu/README.md).

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

## Included components

- `nginx` for static files and reverse proxying; self-signed certificates are
  generated during the image build.
- `oak_webrtc` for DepthAI WebRTC connection establishment and streaming. Its
  source is maintained in a private Luxonis repository and is not included
  here.
- `runit` for service supervision.

## Maintainer documentation

Publishing official images requires Luxonis registry permissions. See
[`MAINTAINERS.md`](MAINTAINERS.md) for release steps.
