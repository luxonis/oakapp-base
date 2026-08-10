# `Dockerfile.onnxruntime`

`Dockerfile.onnxruntime` builds the ARM64-only `oakapp-base` variant for ONNX
Runtime with the QNN Execution Provider on the OAK4 Hexagon DSP. It extends
the normal Python 3.12 base image; it does not replace the normal application
entrypoint or package a model.

## Base image and architecture

```dockerfile
ARG BASE_IMAGE=luxonis/oakapp-base:1.2.9
FROM ${BASE_IMAGE} AS oakapp
```

The image starts from the released base image and layers QNN support on top.
It is intended for `linux/arm64`: the OAK4 FastRPC stack and Hexagon DSP are
ARM64-specific.

## Installed runtime dependencies

```dockerfile
RUN apt-get ... libatomic1
RUN pip install ... onnxruntime==1.28.0 onnxruntime-qnn==2.4.0
```

`libatomic1` is needed by QNN's CPU-side libraries. The two Python wheels are
installed in the image so every app using this base does not need to download
them during its own container preparation. Their versions are pinned and
should be upgraded as a tested pair.

## DSP-side QNN libraries

The QNN wheel contains both CPU-side libraries and the Hexagon DSP-side
libraries ("skels"). The Dockerfile determines the wheel's library directory,
creates the stable `/opt/qnn-libs` symlink to it, and sets:

```dockerfile
ENV ADSP_LIBRARY_PATH=/opt/qnn-libs
```

Using the wheel's directory ensures the DSP skels match the installed QNN
CPU-side stub.

## Container-start hook

At image build time the Dockerfile installs:

```text
npu/npu-setup.sh → /etc/entrypoint.d/10-npu-setup.sh
```

It also copies the hook-aware [`entrypoint.sh`](entrypoint.sh). At container
startup that entrypoint sources the hook before launching services and the
application. The hook:

- links the required FastRPC libraries from the device OS into the container;
- exports `ADSP_LIBRARY_PATH` for the application process.

See [`entrypoint.md`](entrypoint.md) for the hook lifecycle and
[`npu/README.md`](npu/README.md) for the hook's detailed behavior.

## What applications must still provide

Docker images cannot embed a particular device's nodes, cgroup permissions, or
proprietary device-OS libraries. Each QNN app must therefore use the image's
entrypoint and configure device and library passthrough in `oakapp.toml`:

```toml
entrypoint = ["/entrypoint.sh", "python3.12", "-u", "/app/main.py"]
optional_devices = [
    "/dev/fastrpc-cdsp", # ONNX Runtime QNN device probe
    "/dev/adsprpc-smd",  # libcdsprpc.so FastRPC transport
    "/dev/dma_heap/qcom,system",
    "/dev/dma_heap/system",
]
optional_mounts = ["/usr/lib:/host_usr_lib:ro,rbind"]
```

The app must also grant device-cgroup access through `allowed_devices`. The
device major numbers can vary by OS/kernel build, so inspect the target device
rather than assuming the example values in the main README are universal.

With that configuration, an app can use the slim helper:

```python
from oak4ort_slim import qnn_session

session = qnn_session("model.onnx")
```

## Build

Build on ARM64, or use an ARM64-capable builder/emulation:

```bash
docker build -f Dockerfile.onnxruntime \
  --platform=linux/arm64 \
  -t oakapp-base:onnxruntime .
```
