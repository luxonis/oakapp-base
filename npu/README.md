# NPU setup hook

`npu-setup.sh` prepares an `oakapp-base:onnxruntime` container to use the
OAK4 Hexagon DSP through ONNX Runtime's QNN Execution Provider. It is a
startup hook, not an inference launcher: it makes the host DSP device and its
FastRPC libraries available before the Python application starts.

## What it does

1. Links the FastRPC user-space library stack from `/host_usr_lib` into the
   container's `/usr/lib`, then runs `ldconfig`. This includes
   `libcdsprpc.so` and its OE dependencies. The host libraries are used
   rather than baked into the image so they match the currently running OS.
2. Exports `ADSP_LIBRARY_PATH=/opt/qnn-libs` unless the variable is already
   set. This locates the QNN wheel's DSP-side Hexagon skel libraries.

The hook is idempotent and treats setup failures as non-fatal. An app that
does not request the DSP can therefore use the same base image unchanged.

## When it runs

The ONNX Runtime image build copies this script to:

```text
/etc/entrypoint.d/10-npu-setup.sh
```

`/entrypoint.sh` sources every `*.sh` file in that directory before launching
the application. Sourcing is important: `ADSP_LIBRARY_PATH` remains in the
environment inherited by ONNX Runtime.

```text
oakapp.toml → /entrypoint.sh → 10-npu-setup.sh → Python app → qnn_session()
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
allowed_devices = [
    { allow = true, type = "c", major = 496, access = "rw" },
    { allow = true, type = "c", major = 248, access = "rw" },
]
```

Device major numbers are kernel/OS dependent. Confirm them on the target with
`ls -l /dev/fastrpc-cdsp /dev/adsprpc-smd` and the DMA-heap nodes; see a current consumer's
`oakapp.toml` for a complete example.

## LFM compatibility shim

Some previously deployed images contained this hook but had an older
`/entrypoint.sh` that did not source `/etc/entrypoint.d`. In that case,
`lfm2.5-vl-frontend/start.sh` explicitly sources this hook before delegating
to `/entrypoint.sh`. This is safe because the hook is idempotent.

## Typical failures

| Log message or symptom | Likely cause | Fix |
|---|---|---|
| `/dev/fastrpc-cdsp` or `/dev/adsprpc-smd` not present | Device was not passed through | Add both to `optional_devices`. |
| `/host_usr_lib/libcdsprpc.so not found` | Host library mount is missing | Add the `/usr/lib` mount above. |
| No QNN device is enumerated | `/dev/fastrpc-cdsp` was not passed through or is inaccessible | Verify device passthrough and access. |
| FastRPC permission error / CPU inference | Device cgroup access is denied | Correct `allowed_devices` for the running kernel. |
