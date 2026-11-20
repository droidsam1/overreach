# Runs the OverreachCore tests (domain, analytics, import, presentation) in the same Linux image as CI.
# Usage: ./scripts/test-core.ps1 [extra swift test arguments, e.g. --filter Exercises]
# Set OVERREACH_SWIFT_BUILD_VOLUME to isolate build products for a checkout.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$volume = if ($env:OVERREACH_SWIFT_BUILD_VOLUME) { $env:OVERREACH_SWIFT_BUILD_VOLUME } else { 'overreach-swift-build' }

docker run --rm `
    -v "${repo}:/src" `
    -v "${volume}:/build" `
    -w /src `
    swift:6.0 `
    swift test --package-path Packages/OverreachCore --scratch-path /build @args
exit $LASTEXITCODE
