#!/usr/bin/env bash
# Runs the BunnListCore tests (product rules only). Passing here says nothing about the iOS build.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
package_dir="$repo_dir/Packages/BunnListCore"
cd "$package_dir"
if command -v swift >/dev/null 2>&1; then
  exec swift test --jobs 2
fi
if ! command -v docker >/dev/null 2>&1; then
  echo 'Install Swift 6.0.3 (or newer 6.0.x) or a working Docker engine to run the core tests.' >&2
  exit 1
fi
# swift:6.0.3-noble, pinned by digest.
swift_image='swift@sha256:f19aea3f9a889df5884e1186e60be74869613477d99656b598c115a4b91af8a1'
docker info >/dev/null
if ! docker image inspect "$swift_image" >/dev/null 2>&1; then
  docker pull "$swift_image"
fi
mkdir -p .build
exec docker run --rm --user "$(id -u):$(id -g)" \
  -v "$package_dir:/work" -w /work \
  -e CLANG_MODULE_CACHE_PATH=/work/.build/clang-modules \
  -e SWIFTPM_MODULECACHE_OVERRIDE=/work/.build/swift-modules \
  "$swift_image" swift test --jobs 2 \
  --cache-path /work/.build/cache --config-path /work/.build/config --security-path /work/.build/security
