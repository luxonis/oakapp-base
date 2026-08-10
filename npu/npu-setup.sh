#!/usr/bin/env bash
# NPU (Hexagon DSP / FastRPC) container setup for the ONNX Runtime QNN EP.
#
# Sourced by /entrypoint.sh before the app starts (see /etc/entrypoint.d).
#
# All failures are non-fatal: apps that do not use the NPU are unaffected.

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

_fastrpc_setup

# Hexagon skels must match the CPU-side QNN stub; /opt/qnn-libs points at the
# preinstalled onnxruntime-qnn wheel libraries (see Dockerfile.onnxruntime).
export ADSP_LIBRARY_PATH="${ADSP_LIBRARY_PATH:-/opt/qnn-libs}"
