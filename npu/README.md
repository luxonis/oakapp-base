# NPU setup hook

`npu-setup.sh` prepares an `oakapp-base:onnxruntime` container to use the
OAK4 Hexagon DSP through ONNX Runtime's QNN Execution Provider. It is a
startup hook, not an inference launcher: it links the host FastRPC libraries
before the Python application starts.

## What it does

1. Links the FastRPC user-space library stack from `/host_usr_lib` into the
   container's `/usr/lib`, then runs `ldconfig`. This includes
   `libcdsprpc.so` and its OE dependencies. The host libraries are used
   rather than baked into the image so they match the currently running OS.
The hook is idempotent and treats setup failures as non-fatal. An app that
does not request the DSP can therefore use the same base image unchanged.

## When it runs

The ONNX Runtime image build copies this source file into the image as:

```text
/etc/entrypoint.d/npu-setup.sh
```

`/entrypoint.sh` runs every `*.sh` hook in that directory before launching the
application. The main [`README.md`](../README.md) describes the ONNX Runtime
image and required application configuration.

```text
oakapp.toml → /entrypoint.sh → npu-setup.sh → Python app → qnn_session()
```

Use the base-image entrypoint in `oakapp.toml`:

```toml
entrypoint = ["/entrypoint.sh", "python3.12", "-u", "/app/main.py"]
```

## Application requirements

An image cannot supply host devices or host libraries. An app using QNN must
pass through the FastRPC and DMA-heap devices, allow access to them, and mount
the device OS libraries:

```toml
optional_devices = [
    "/dev/fastrpc-cdsp", # ONNX Runtime QNN device probe
    "/dev/adsprpc-smd",  # libcdsprpc.so FastRPC transport
    "/dev/dma_heap/qcom,system",
    "/dev/dma_heap/system",
]
optional_mounts = ["/usr/lib:/host_usr_lib:ro,rbind"]
allowed_devices = [{ allow = true, access = "rw" }]
```

This broad rule grants read/write cgroup access to devices already mounted in
the container; it does not mount any additional devices. It avoids coupling
the app configuration to OS-specific device major numbers.

## Typical failures

| Log message or symptom | Likely cause | Fix |
|---|---|---|
| `/host_usr_lib/libcdsprpc.so not found` | Host library mount is missing | Add the `/usr/lib` mount above. |
| No QNN device is enumerated | `/dev/fastrpc-cdsp` was not passed through or is inaccessible | Verify device passthrough and access. |
| FastRPC permission error / CPU inference | `/dev/adsprpc-smd` was not passed through or device cgroup access is denied | Verify both device entries and `allowed_devices`. |
