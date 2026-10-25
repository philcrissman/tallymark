#!/usr/bin/env bash
set -euo pipefail

# Bundles everything needed to deploy Tallymark without building it:
#   dist/tallymark-<version>.tar.gz
# Usage: scripts/package-release.sh [version]   (defaults to the current git tag/commit)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(git -C "$ROOT" describe --tags --always)}"
NAME="tallymark-$VERSION"
STAGE="$ROOT/dist/$NAME"

for f in backend/build/function.zip dashboard/build/index.html; do
  if [ ! -f "$ROOT/$f" ]; then
    echo "Error: $f not found. Run 'make build' first."
    exit 1
  fi
done

rm -rf "$STAGE"
mkdir -p "$STAGE/backend/build" "$STAGE/dashboard" "$STAGE/infra" "$STAGE/scripts" "$STAGE/tracker"

cp "$ROOT/backend/build/function.zip" "$STAGE/backend/build/"
cp -r "$ROOT/dashboard/build" "$STAGE/dashboard/build"
cp "$ROOT/infra/template.yaml" "$STAGE/infra/"
cp "$ROOT/scripts/deploy.sh" "$STAGE/scripts/"
cp "$ROOT/tracker/tracker.js" "$STAGE/tracker/"
cp "$ROOT/tallymark.env.example" "$ROOT/LICENSE" "$ROOT/README.md" "$STAGE/"

tar -C "$ROOT/dist" -czf "$ROOT/dist/$NAME.tar.gz" "$NAME"
# Stable names so releases/latest/download/<file> links keep working
cp "$ROOT/dist/$NAME.tar.gz" "$ROOT/dist/tallymark.tar.gz"
cp "$ROOT/backend/build/function.zip" "$ROOT/dist/function.zip"

echo "==> Release bundle: dist/$NAME.tar.gz"
