#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../dashboard"

echo "==> Building Elm dashboard..."
mkdir -p build
elm make src/Main.elm --optimize --output=build/main.js

echo "==> Minifying..."
if command -v terser &> /dev/null; then
  terser build/main.js \
    --compress 'pure_funcs=[F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9],pure_getters,keep_fargs=false,unsafe_comps,unsafe' \
    | terser --mangle --output build/main.min.js
  mv build/main.min.js build/main.js
else
  echo "    (terser not found, skipping minification)"
fi

echo "==> Copying static assets..."
cp index.html build/
cp style.css build/

echo "==> Dashboard build complete: dashboard/build/"
