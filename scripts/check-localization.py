#!/usr/bin/env python3
"""Checks that every user-facing string is in App/Resources/Localizable.xcstrings, translated (ADR-0015).

Usage: scripts/check-localization.py [--list]
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App/Resources/Localizable.xcstrings"
INFO_PLIST_CATALOG = ROOT / "App/Resources/InfoPlist.xcstrings"
LANGUAGES = ["es", "gl"]
PRESENTATION = ROOT / "Packages/OverreachCore/Sources/Presentation"
UI_ROOTS = [
    ROOT / "App/Sources",
    ROOT / "Packages/OverreachKit/Sources/DesignSystem",
    *sorted((ROOT / "Packages/OverreachKit/Sources").glob("Feature*")),
]
UI_SKIPPED_FILES = {"AppContainer.swift", "OverreachApp.swift", "StrongHistoryImporter.swift"}

LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')
MULTILINE = re.compile(r'"""\n(.*?)\n\s*"""', re.S)
L10N_CALL = re.compile(r'L10n\.(?:text|format)\(\s*("(?:[^"\\\n]|\\.)*"(?:\s*\+\s*"(?:[^"\\\n]|\\.)*")*)')
NOT_UI_TEXT = re.compile(r'(systemImage|systemName|symbol|forInfoDictionaryKey):\s*$')
SYMBOL = re.compile(r'^(circle|[a-z0-9]+(\.[a-z0-9]+)+)$')
FORMATTED_TEXT = re.compile(r'formatted|remaining|lastPathComponent')
SWIFT_FORMAT = re.compile(r'%(?:\d+\$)?(?:lld|@|lf)')
TEMPLATE_VALUE = re.compile(r'\{\d+\}')


def unescape(literal):
    return literal.replace('\\"', '"').replace("\\\\", "\\")


def interpolation_end(text, start):
    depth = 1
    index = start
    while index < len(text) and depth:
        depth += {"(": 1, ")": -1}.get(text[index], 0)
        index += 1
    return index


def to_key(body):
    """Turns `Sets: \\(count)` into the key SwiftUI looks up: `Sets: %lld`."""
    key, index = "", 0
    while index < len(body):
        if body.startswith("\\(", index):
            end = interpolation_end(body, index + 2)
            key += "%@" if FORMATTED_TEXT.search(body[index + 2:end - 1]) else "%lld"
            index = end
        else:
            key += body[index]
            index += 1
    return unescape(key)


def strip_comments(text):
    lines = [line for line in text.split("\n") if not line.lstrip().startswith("//")]
    return "\n".join(lines)


def read(path):
    return strip_comments(path.read_text(encoding="utf-8").replace("\r\n", "\n"))


def presentation_keys():
    keys = {}
    for path in PRESENTATION.rglob("*.swift"):
        for match in L10N_CALL.finditer(read(path)):
            key = "".join(unescape(part[1:-1]) for part in LITERAL.findall(match.group(1)))
            keys[key] = path
    return keys


def ui_keys():
    keys = {}
    for root in UI_ROOTS:
        for path in root.rglob("*.swift"):
            if path.name in UI_SKIPPED_FILES:
                continue
            text = read(path).split("#Preview")[0]
            for match in MULTILINE.finditer(text):
                lines = [line.strip() for line in match.group(1).split("\n")]
                keys[to_key(" ".join(line.rstrip("\\").rstrip() for line in lines))] = path
            text = MULTILINE.sub('""', text)
            for match in LITERAL.finditer(text):
                body = match.group()[1:-1]
                if NOT_UI_TEXT.search(text[:match.start()]) or SYMBOL.match(body):
                    continue
                key = to_key(body)
                if re.search("[A-Za-z]", SWIFT_FORMAT.sub("", key)):
                    keys[key] = path
    return keys


def placeholders(text):
    found = SWIFT_FORMAT.findall(text) + TEMPLATE_VALUE.findall(text)
    return sorted(re.sub(r'\d+\$', "", item) for item in found)


def main():
    keys = {**presentation_keys(), **ui_keys()}
    if "--list" in sys.argv:
        print(json.dumps(sorted(keys), ensure_ascii=False, indent=0))
        return 0
    strings = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    problems = [f"Not in the catalog: {key!r} ({path.relative_to(ROOT)})"
                for key, path in sorted(keys.items()) if key not in strings]
    problems += [f"No longer used: {key!r}" for key in sorted(strings) if key not in keys]
    for key, entry in sorted(strings.items()):
        if "%" in SWIFT_FORMAT.sub("", key):
            problems.append(f"Literal % in a key: {key!r}. Pass it as a value.")
        for language in LANGUAGES:
            unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
            value = unit.get("value", "")
            if unit.get("state") != "translated" or not value:
                problems.append(f"Missing {language}: {key!r}")
            elif placeholders(value) != placeholders(key):
                problems.append(f"Different values in {language}: {key!r}")
    for key, entry in sorted(json.loads(INFO_PLIST_CATALOG.read_text(encoding="utf-8"))["strings"].items()):
        for language in LANGUAGES:
            if not entry.get("localizations", {}).get(language, {}).get("stringUnit", {}).get("value"):
                problems.append(f"Missing {language} in InfoPlist: {key!r}")
    print("\n".join(problems) or f"{len(strings)} strings translated into {', '.join(LANGUAGES)}.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
