#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../backend"

# CI builds the image itself (with layer caching) and sets SKIP_IMAGE_BUILD=1
if [ -z "${SKIP_IMAGE_BUILD:-}" ]; then
  echo "==> Building Haskell Lambda in Docker..."
  docker build --platform linux/amd64 -t tallymark-builder .
fi

echo "==> Extracting bootstrap binary..."
mkdir -p build
CONTAINER_ID=$(docker create tallymark-builder)
docker cp "$CONTAINER_ID:/build/bootstrap" build/bootstrap
docker rm "$CONTAINER_ID"

echo "==> Creating function.zip..."
cd build
chmod +x bootstrap
rm -f function.zip
zip function.zip bootstrap

echo "==> Backend build complete: backend/build/function.zip"
