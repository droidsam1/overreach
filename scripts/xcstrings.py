"""Reads and writes String Catalogs in the repository's canonical form: keys sorted, two-space indent."""
import json

MISSING = object()


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def dumps(catalog):
    return json.dumps(sort(catalog), ensure_ascii=False, indent=2) + "\n"


def sort(catalog):
    return {**catalog, "strings": dict(sorted(catalog.get("strings", {}).items()))} if "strings" in catalog else catalog


def save(path, catalog):
    path.write_text(dumps(catalog), encoding="utf-8", newline="\n")


def merge(base, ours, theirs):
    """Three-way merge per key. Returns the merged catalog and the keys both sides changed differently."""
    merged, conflicts = {}, []
    for field in dict.fromkeys([*ours, *theirs, *base, "strings"]):
        if field == "strings":
            merged["strings"] = {}
            continue
        value = _pick(base.get(field, MISSING), ours.get(field, MISSING), theirs.get(field, MISSING))
        if value is _CONFLICT:
            conflicts.append(field)
            value = ours.get(field, MISSING)
        if value is not MISSING:
            merged[field] = value
    strings = {}
    base_s, ours_s, theirs_s = (catalog.get("strings", {}) for catalog in (base, ours, theirs))
    for key in dict.fromkeys([*ours_s, *theirs_s, *base_s]):
        value = _pick(base_s.get(key, MISSING), ours_s.get(key, MISSING), theirs_s.get(key, MISSING))
        if value is _CONFLICT:
            conflicts.append(key)
            value = ours_s.get(key, MISSING)
        if value is not MISSING:
            strings[key] = value
    merged["strings"] = strings
    return sort(merged), conflicts


_CONFLICT = object()


def _pick(base, ours, theirs):
    if ours == theirs or theirs == base:
        return ours
    if ours == base:
        return theirs
    return _CONFLICT
