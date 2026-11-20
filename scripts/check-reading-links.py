#!/usr/bin/env python3
"""Reports further-reading links (ADR-0024) that no longer resolve.

Reads the URLs from FurtherReading.swift and requests each one. Exit code 1 when any link fails.
Usage: python3 scripts/check-reading-links.py
"""
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Packages/OverreachCore/Sources/Presentation/PresentationKit/FurtherReading.swift"
BASES = {"fr": "https://www.fitnessrevolucionario.com"}


def urls():
    text = SOURCE.read_text(encoding="utf-8")
    found = re.findall(r'"(https://[^"]+)"', text)
    found += [BASES["fr"] + path for path in re.findall(r'"(/[a-z0-9/-]+/)"', text)]
    return sorted(set(url for url in found if url != BASES["fr"]))


def check(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (link check)"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, None
    except Exception as error:  # noqa: BLE001 — report every kind of failure
        return getattr(error, "code", None), str(error)


def main():
    failures = 0
    for url in urls():
        status, error = check(url)
        ok = status is not None and 200 <= status < 400 and error is None
        failures += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {status or '-'} {url}" + (f"  ({error})" if error else ""))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
