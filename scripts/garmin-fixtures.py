#!/usr/bin/env python3
# Usage: python3 -I scripts/garmin-fixtures.py <dir with raw Garmin JSON responses> <output dir>
# Never commit the raw responses: they are personal health data.
"""Turn real Garmin Personal API responses into synthetic fixtures with the same shape.

Keeps keys, nesting, nulls, types and enum-like strings. Replaces every number with a seeded
synthetic value of the same type and similar magnitude, shifts every date and timestamp by a
fixed offset, and drops identifying text (names, descriptions, locations, URLs, ids)."""
import json, random, re, sys, datetime as dt, pathlib

SHIFT_DAYS = -315  # 2026-11-19 -> 2026-01-08
DATE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
DATETIME = re.compile(r'^(\d{4}-\d{2}-\d{2})([ T])(\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$')
KEEP_NUMBERS = {'sleepVersion', 'featureVersion', 'algorithmVersion', 'typeId', 'parentTypeId', 'sortOrder',
                'sportTypeId', 'lapCount', 'lapIndex', 'awakeCount', 'unitOfPoolLength', 'status'}
DROP_TEXT = {'activityName', 'description', 'locationName', 'ownerDisplayName', 'ownerFullName', 'ownerProfileImageUrlSmall',
             'ownerProfileImageUrlMedium', 'ownerProfileImageUrlLarge', 'uuid', 'activityUUID', 'manufacturer', 'userNote',
             'comments', 'activityLikeDisplayNames', 'activityLikeFullNames', 'activityLikeProfileImageUrls', 'activityLikeAuthors',
             'deviceId', 'productDisplayName'}
ID_KEYS = {'id', 'activityId', 'userProfilePk', 'userProfilePK', 'userProfileId', 'ownerId', 'parentId', 'deviceId', 'jti'}
GEO = re.compile(r'(?i)(latitude|longitude)')
rng = random.Random(42)
factor = 1.0  # one factor per record keeps sums (sleep stages) and 0-100 scales consistent
ids = {}

def shift_date(s):
    return (dt.date.fromisoformat(s) + dt.timedelta(days=SHIFT_DAYS)).isoformat()

def fake_id(v):
    return ids.setdefault(v, 10_000_000 + len(ids) + 1)

def number(key, v):
    if isinstance(v, bool):
        return v
    if key in KEEP_NUMBERS:
        return v
    if key in ID_KEYS:
        return fake_id(v)
    if isinstance(v, int) and abs(v) > 10**11:  # epoch milliseconds
        return v + SHIFT_DAYS * 86_400_000
    if isinstance(v, int):
        return int(round(v * factor))
    return round(v * factor, 3)

def string(key, v):
    if key in DROP_TEXT:
        return None if key not in ('uuid', 'activityUUID') else '00000000-0000-4000-8000-%012d' % fake_id(v)
    if DATE.match(v):
        return shift_date(v)
    m = DATETIME.match(v)
    if m:
        return shift_date(m.group(1)) + m.group(2) + m.group(3) + (m.group(4) or '') + (m.group(5) or '')
    if v.startswith('http'):
        return None
    return v  # enums, keys, qualifiers

def walk(v, key='', depth=0):
    global factor
    if depth <= 1 and isinstance(v, dict):
        factor = rng.uniform(0.88, 0.98)
    if isinstance(v, dict):
        return {k: (None if GEO.search(k) else walk(x, k, depth + 1)) for k, x in v.items()}
    if isinstance(v, list):
        return [walk(x, key, depth + 1) for x in v]
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return number(key, v)
    if isinstance(v, str):
        return string(key, v)
    return v

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
dst.mkdir(parents=True, exist_ok=True)
for f in sorted(src.glob('*.json')):
    if f.name.startswith('probe_') or f.stat().st_size == 0:
        continue
    data = json.loads(f.read_text())
    (dst / f.name).write_text(json.dumps(walk(data), indent=1, ensure_ascii=False) + '\n')
    print('wrote', f.name)
