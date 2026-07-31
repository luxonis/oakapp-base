#!/usr/bin/env bash
# NPU (Hexagon DSP / FastRPC) container setup for the ONNX Runtime QNN EP.
#
# Sourced by /entrypoint.sh before the app starts (see /etc/entrypoint.d).
#
# The QNN EP only enumerates an NPU device if /dev/fastrpc-cdsp exists
# (onnxruntime soc_utils probes that exact path), but Luxonis OS names the
# FastRPC node /dev/adsprpc-smd. Create an alias: prefer a proper char
# device node (needs the mknod device-cgroup permission), fall back to a
# symlink (works with plain `optional_devices` passthrough).
#
# All failures are non-fatal: apps that do not use the NPU are unaffected.

_npu_setup() {
  local alias_node=/dev/fastrpc-cdsp
  local node=/dev/adsprpc-smd

  if [ -e "$alias_node" ]; then
    return 0
  fi
  if [ ! -e "$node" ]; then
    echo "[npu-setup] $node not present; add it to optional_devices in oakapp.toml to use the NPU"
    return 0
  fi

  local maj min
  maj=$((16#$(stat -c '%t' "$node")))
  min=$((16#$(stat -c '%T' "$node")))
  if mknod "$alias_node" c "$maj" "$min" 2>/dev/null; then
    echo "[npu-setup] created $alias_node (char $maj:$min, alias of $node)"
  elif ln -s "$node" "$alias_node" 2>/dev/null; then
    echo "[npu-setup] created symlink $alias_node -> $node (mknod not permitted)"
  else
    echo "[npu-setup] WARNING: could not create $alias_node; the QNN EP will not detect the NPU"
  fi
  return 0
}

# FastRPC user-space stack (libcdsprpc.so + its OE dependency chain). These
# are proprietary device-OS binaries, so they are NOT shipped in the image.
# Instead the app mounts the device /usr/lib read-only and this hook links
# the needed libraries into the container's /usr/lib -- they are therefore
# always the exact libraries of the running OS:
#
#   optional_mounts = ["/usr/lib:/host_usr_lib:ro,rbind"]
#
# The chain is closed: everything else these libraries need (glibc,
# libstdc++, libgcc) is already in the Debian base.
_fastrpc_setup() {
  local host_lib=/host_usr_lib
  local libs=(
    libcdsprpc.so     # FastRPC transport to the compute DSP (dlopened by the QNN stub)
    liblog.so.0       # OE/Android logging
    libcutils.so.0    # OE/Android utils
    libion.so.0       # ION shared-memory allocator
    libdmabufheap.so.0 # DMA-BUF heap allocator
    libvmmem.so.0     # VM memory helper
    libbase.so.0      # OE/Android base
  )

  if [ -e /usr/lib/libcdsprpc.so ]; then
    return 0
  fi
  if [ ! -e "$host_lib/libcdsprpc.so" ]; then
    echo "[npu-setup] $host_lib/libcdsprpc.so not found; add optional_mounts = [\"/usr/lib:/host_usr_lib:ro,rbind\"] to oakapp.toml to use the NPU"
    return 0
  fi

  local lib
  for lib in "${libs[@]}"; do
    if [ -e "$host_lib/$lib" ]; then
      ln -sf "$host_lib/$lib" "/usr/lib/$lib"
    else
      echo "[npu-setup] WARNING: $host_lib/$lib not found on the device OS"
    fi
  done
  ldconfig 2>/dev/null || true
  echo "[npu-setup] linked FastRPC user-space stack from $host_lib"
  return 0
}

_npu_setup
_fastrpc_setup

# Hexagon skels must match the CPU-side QNN stub; /opt/qnn-libs points at the
# preinstalled onnxruntime-qnn wheel libraries (see Dockerfile.onnxruntime).
export ADSP_LIBRARY_PATH="${ADSP_LIBRARY_PATH:-/opt/qnn-libs}"
