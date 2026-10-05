#!/usr/bin/env bash
set -euo pipefail

cd /src

# Configure the ARM64 build with CPU and Hexagon support
cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_COMPILER_TARGET=aarch64-linux-gnu \
    -DCMAKE_CXX_COMPILER_TARGET=aarch64-linux-gnu \
    -DCMAKE_C_FLAGS="-march=armv8.2-a+fp16+dotprod" \
    -DCMAKE_CXX_FLAGS="-march=armv8.2-a+fp16+dotprod" \
    -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld \
    -DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld \
    -DCMAKE_INSTALL_RPATH=/opt/llama.cpp/lib \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8.2-a+fp16+dotprod \
    -DGGML_OPENMP=OFF -DGGML_LLAMAFILE=OFF -DGGML_OPENCL=OFF \
    -DGGML_HEXAGON=ON \
    -DHEXAGON_SDK_ROOT="$HEXAGON_SDK_ROOT" \
    -DHEXAGON_TOOLS_ROOT="$HEXAGON_TOOLS_ROOT" \
    -DPREBUILT_LIB_DIR=linux_aarch64 \
    -DLLAMA_BUILD_IS_DEV=OFF -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_APP=OFF \
    -DLLAMA_BUILD_UI=OFF -DLLAMA_OPENSSL=OFF

# Build the command-line tools and v73 DSP kernels
cmake --build build --target llama-server llama-cli llama-bench htp-v73 -j "${BUILD_JOBS:-4}"

# Package runtime binaries and libraries, including only v73 DSP kernels
# Upstream's full install also expects v75/v79/v81 artifacts.
mkdir -p /out/{bin,lib,include,licenses}
cp build/bin/{llama-server,llama-cli,llama-bench} /out/bin/
find build -type f -name '*.so*' -exec cp -a {} /out/lib/ \;
find build -type l -name '*.so*' -exec cp -a {} /out/lib/ \;
test -s /out/lib/libggml-htp-v73.so

# Include development headers and upstream licenses
cp include/llama*.h ggml/include/*.h tools/mtmd/{mtmd.h,mtmd-helper.h} /out/include/
cp LICENSE /out/licenses/llama.cpp-LICENSE
cp -r licenses /out/licenses/upstream

# Strip unnecessary symbols from ARM64 binaries and libraries
for artifact in /out/bin/* /out/lib/*; do
    if aarch64-linux-gnu-readelf -h "$artifact" | grep -q 'Machine:.*AArch64'; then
        aarch64-linux-gnu-strip --strip-unneeded "$artifact"
    fi
done

# Record the source revision, toolchain, and enabled features
python3 - <<'PY'
import json, os
from pathlib import Path
Path('/out/build-info.json').write_text(json.dumps({
    'version': os.environ['LLAMA_VERSION'],
    'commit': os.environ['LLAMA_COMMIT'],
    'source': 'https://github.com/ggml-org/llama.cpp',
    'local_patches': [],
    'target': 'linux/arm64',
    'runtime_abi': 'Debian 12 (bookworm)',
    'backends': ['CPU', 'Hexagon v73'],
    'hexagon_sdk': '6.6.0.0',
    'hexagon_tools': '19.0.07',
    'https_model_download': False,
}, indent=2) + '\n')
PY
