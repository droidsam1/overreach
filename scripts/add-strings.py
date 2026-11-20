#!/usr/bin/env python3
"""Adds translated strings to App/Resources/Localizable.xcstrings in canonical form (ADR-0015).

Usage:
  scripts/add-strings.py --template > strings.json   # keys the code uses that the catalog lacks
  scripts/add-strings.py strings.json                # add them after filling es and gl
  scripts/add-strings.py --prune                     # remove keys the code no longer uses

strings.json maps each English key to its translations: {"Add {1} weeks": {"es": "…", "gl": "…"}}.
A key that already exists is overwritten. Placeholders ({1}, %lld, %@) must match the key.
"""
import importlib.util
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import xcstrings  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("check_localization", ROOT / "scripts/check-localization.py")
check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check)


def used_keys():
    return {**check.presentation_keys(), **check.ui_keys()}


def entry(translations):
    return {
        "extractionState": "manual",
        "localizations": {
            language: {"stringUnit": {"state": "translated", "value": translations[language]}}
            for language in check.LANGUAGES
        },
    }


def template(catalog):
    missing = sorted(key for key in used_keys() if key not in catalog["strings"])
    print(json.dumps({key: {language: "" for language in check.LANGUAGES} for key in missing},
                     ensure_ascii=False, indent=2))
    return 0


def add(catalog, path):
    additions = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    problems = []
    for key, translations in additions.items():
        for language in check.LANGUAGES:
            value = translations.get(language, "")
            if not value:
                problems.append(f"Missing {language}: {key!r}")
            elif check.placeholders(value) != check.placeholders(key):
                problems.append(f"Different values in {language}: {key!r} -> {value!r}")
    if problems:
        print("\n".join(problems))
        return 1
    for key, translations in additions.items():
        catalog["strings"][key] = entry(translations)
    xcstrings.save(check.CATALOG, catalog)
    print(f"Added {len(additions)} strings.")
    return 0


def prune(catalog):
    used = used_keys()
    unused = [key for key in catalog["strings"] if key not in used]
    for key in unused:
        del catalog["strings"][key]
    xcstrings.save(check.CATALOG, catalog)
    print(f"Removed {len(unused)} strings." + "".join(f"\n  {key!r}" for key in unused))
    return 0


def main(args):
    sys.stdout.reconfigure(encoding="utf-8")
    catalog = xcstrings.load(check.CATALOG)
    if args == ["--template"]:
        return template(catalog)
    if args == ["--prune"]:
        return prune(catalog)
    if len(args) == 1 and not args[0].startswith("-"):
        return add(catalog, args[0])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
