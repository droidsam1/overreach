# Runs the OverreachCore tests (domain, analytics, import, presentation) in the same Linux image as CI.
# Usage: ./scripts/test-core.ps1 [extra swift test arguments, e.g. --filter Exercises]
# Build products live in the `overreach-swift-build` volume, so later runs only rebuild what changed.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

docker run --rm `
    -v "${repo}:/src" `
    -v overreach-swift-build:/build `
    -w /src `
    swift:6.0 `
    swift test --package-path Packages/OverreachCore --scratch-path /build @args
exit $LASTEXITCODE
