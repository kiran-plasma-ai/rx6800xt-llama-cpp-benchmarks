#!/usr/bin/env bash
# Build llama.cpp with the Vulkan backend and install it into a prefix.
#
# Usage: build-llama-vulkan.sh <tag> [install-prefix]
#   tag             upstream tag, e.g. b12669
#   install-prefix  default: ~/.local/share/llama.cpp
#
# Why the Vulkan backend: on RDNA2 (RX 6000) it needs no ROCm, and ROCm 10.1
# segfaults on hipStreamCreate on this machine, so HIP is not an option.
#
# Requirements: cmake 3.24+, ninja, a C++17 compiler, and Vulkan headers.
# The headers are not packaged in some distros; this script clones them into
# /tmp. SPIRV-Headers are built into /tmp when the distro has no config for them.
#
# The installed binaries have their RUNPATH stripped by CMake ("Set
# non-toolchain portion of runtime path ... to ''"), so every invocation needs
# LD_LIBRARY_PATH=<prefix>/lib. That is not a broken build.
set -euo pipefail

TAG=${1:?usage: $0 <tag> [install-prefix]}
PREFIX=${2:-$HOME/.local/share/llama.cpp}
SRC=${BUILD_DIR:-/tmp/llama.cpp-src-$TAG}
JOBS=${JOBS:-$(nproc)}

if ! command -v cmake >/dev/null; then
  echo "cmake not found; install it (e.g. 'uv tool install cmake' or your package manager)" >&2
  exit 1
fi

CMAKE_ARGS=(-G Ninja -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF -DCMAKE_INSTALL_PREFIX="$PREFIX")

# --- Vulkan headers (distro packages often lack the SDK) ---------------------
if [ ! -f /usr/include/vulkan/vulkan.h ]; then
  if [ ! -f /tmp/Vulkan-Headers/include/vulkan/vulkan.h ]; then
    rm -rf /tmp/Vulkan-Headers
    git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers /tmp/Vulkan-Headers
  fi
  CMAKE_ARGS+=(-DVulkan_INCLUDE_DIR=/tmp/Vulkan-Headers/include)
fi

if [ ! -f /usr/share/cmake/SPIRV-Headers/SPIRV-HeadersConfig.cmake ] \
   && [ ! -f /usr/lib/cmake/SPIRV-Headers/SPIRV-HeadersConfig.cmake ]; then
  if [ ! -f /tmp/spirv-headers-install/share/cmake/SPIRV-Headers/SPIRV-HeadersConfig.cmake ]; then
    rm -rf /tmp/SPIRV-Headers /tmp/spirv-headers-install
    git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Headers /tmp/SPIRV-Headers
    cmake -S /tmp/SPIRV-Headers -B /tmp/SPIRV-Headers/build \
      -DCMAKE_INSTALL_PREFIX=/tmp/spirv-headers-install >/dev/null
    cmake --install /tmp/SPIRV-Headers/build >/dev/null
  fi
  CMAKE_ARGS+=(-DCMAKE_PREFIX_PATH=/tmp/spirv-headers-install)
fi

# --- fetch, build, install ---------------------------------------------------
rm -rf "$SRC"
git clone --depth 1 --branch "$TAG" https://github.com/ggml-org/llama.cpp "$SRC"
cmake -S "$SRC" -B "$SRC/build" "${CMAKE_ARGS[@]}"
cmake --build "$SRC/build" -j"$JOBS"
cmake --install "$SRC/build"

echo "installed $TAG into $PREFIX"
echo "verify:"
echo "  LD_LIBRARY_PATH=$PREFIX/lib $PREFIX/bin/llama-server --version"
echo "  LD_LIBRARY_PATH=$PREFIX/lib $PREFIX/bin/llama-bench --list-devices"
