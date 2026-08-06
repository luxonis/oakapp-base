# `entrypoint.sh` changes for the ONNX Runtime base image

The `onnxruntime-base` branch adds a small, generic hook mechanism to
`entrypoint.sh`. This is the required link between the ONNX Runtime image and
the NPU/FastRPC setup script.

## Change from `main`

Immediately before helper services and the application start, `entrypoint.sh`
now sources every shell hook in `/etc/entrypoint.d`:

```bash
if [ -d /etc/entrypoint.d ]; then
  for hook in /etc/entrypoint.d/*.sh; do
    [ -e "$hook" ] || continue
    echo "[entrypoint] Running hook $hook"
    . "$hook" || echo "[entrypoint] Hook $hook failed (continuing)"
  done
fi
```

This is generic infrastructure; it is not specific to QNN. Base-image
variants can install startup setup hooks without replacing the application
entrypoint or adding per-app shell wrappers.

## Why hooks are sourced

The hooks are sourced (`. "$hook"`) rather than run as child processes. A
hook can therefore export variables that remain available to the app. The NPU
hook uses this for `ADSP_LIBRARY_PATH`, which the QNN runtime needs to find
its DSP-side Hexagon libraries.

The entrypoint logs and continues if a hook returns non-zero. This keeps the
mechanism safe for applications that do not use optional base-image features.

## ONNX Runtime / NPU usage

`Dockerfile.onnxruntime` installs
[`npu/npu-setup.sh`](npu/npu-setup.sh) as:

```text
/etc/entrypoint.d/10-npu-setup.sh
```

When an app uses the normal entrypoint:

```toml
entrypoint = ["/entrypoint.sh", "python3.12", "-u", "/app/main.py"]
```

startup order is:

```text
/entrypoint.sh
  → source /etc/entrypoint.d/10-npu-setup.sh
  → start runit helper services
  → start the application
```

See [`npu/README.md`](npu/README.md) for what the NPU hook configures and the
device, mount, and cgroup access required from `oakapp.toml`.

## Compatibility note

Some cached custom images predate this hook mechanism. Applications running
on one of those images must source `10-npu-setup.sh` themselves before
delegating to `/entrypoint.sh`. The LFM frontend's `start.sh` is an example.
The NPU hook is idempotent, so this compatibility source is also safe on a
newer hook-aware entrypoint.
