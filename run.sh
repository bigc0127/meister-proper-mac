#!/bin/bash
# Build (if needed) and launch Meister Proper.app
set -e
cd "$(dirname "$0")"
APP="build/Meister Proper.app"
if [ ! -d "$APP" ] || [ "Sources/MeisterProper" -nt "$APP" ] || [ "Package.swift" -nt "$APP" ]; then
    ./build-app.sh release
fi
open "$APP"
