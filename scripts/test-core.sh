#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if command -v swift >/dev/null 2>&1; then
  exec swift test --jobs 2
fi
if ! command -v docker >/dev/null 2>&1; then
  echo 'Install Swift 5.9+ or a working Docker engine to run the core tests.' >&2
  exit 1
fi
swift_image='swift@sha256:f19aea3f9a889df5884e1186e60be74869613477d99656b598c115a4b91af8a1'
docker info >/dev/null
if ! docker image inspect "$swift_image" >/dev/null 2>&1; then
  docker pull "$swift_image"
fi
mkdir -p .build
exec docker run --rm --user "$(id -u):$(id -g)" \
  -v "$repo_dir:/work" -w /work \
  -e CLANG_MODULE_CACHE_PATH=/work/.build/clang-modules \
  -e SWIFTPM_MODULECACHE_OVERRIDE=/work/.build/swift-modules \
  "$swift_image" swift test --jobs 2 \
  --cache-path /work/.build/cache --config-path /work/.build/config --security-path /work/.build/security
