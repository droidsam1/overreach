#!/usr/bin/env python3
"""Git merge driver for String Catalogs: merges per key, so parallel branches that add strings don't conflict.

Configured by scripts/check-local.py (or by hand):
  git config merge.xcstrings.driver "python3 scripts/merge-xcstrings.py %O %A %B"
Usage: scripts/merge-xcstrings.py BASE OURS THEIRS   (writes the result to OURS)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import xcstrings  # noqa: E402


def main(base, ours, theirs):
    paths = [Path(base), Path(ours), Path(theirs)]
    try:
        catalogs = [xcstrings.load(path) if path.stat().st_size else {} for path in paths]
    except ValueError as error:
        print(f"merge-xcstrings: not valid JSON ({error}); resolve by hand", file=sys.stderr)
        return 1
    merged, conflicts = xcstrings.merge(*catalogs)
    xcstrings.save(paths[1], merged)
    for key in conflicts:
        print(f"merge-xcstrings: both sides changed {key!r}; kept ours, check the other side", file=sys.stderr)
    return 1 if conflicts else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]) if len(sys.argv) == 4 else __doc__)
