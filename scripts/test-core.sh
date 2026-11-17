#!/usr/bin/env sh
# Runs the OverreachCore tests (domain, analytics, import, presentation) in the same Linux image as CI.
# Works on macOS, Linux and Git Bash on Windows. Extra arguments go to `swift test` (e.g. --filter Exercises).
# Build products live in the `overreach-swift-build` volume, so later runs only rebuild what changed.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
if command -v cygpath >/dev/null 2>&1; then
    # Git Bash: give Docker a Windows path and stop MSYS from rewriting the container paths.
    repo="$(cygpath -m "$repo")"
    export MSYS_NO_PATHCONV=1
fi

exec docker run --rm \
    -v "$repo:/src" \
    -v overreach-swift-build:/build \
    -w /src \
    swift:6.0 \
    swift test --package-path Packages/OverreachCore --scratch-path /build "$@"
