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
hook can therefore export variables that remain available to the app. This is
generic behavior for image variants; the ONNX Runtime image sets
`ADSP_LIBRARY_PATH` in its Dockerfile.

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
