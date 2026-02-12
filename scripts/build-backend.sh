#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../backend"

echo "==> Building Haskell Lambda in Docker..."
docker build --platform linux/amd64 -t analytics-builder .

echo "==> Extracting bootstrap binary..."
mkdir -p build
CONTAINER_ID=$(docker create analytics-builder)
docker cp "$CONTAINER_ID:/build/bootstrap" build/bootstrap
docker rm "$CONTAINER_ID"

echo "==> Creating function.zip..."
cd build
chmod +x bootstrap
zip function.zip bootstrap

echo "==> Backend build complete: backend/build/function.zip"
