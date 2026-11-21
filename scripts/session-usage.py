#!/usr/bin/env python3
"""Token use and estimated cost of the agent sessions on this project, read from the local session logs.

Shows where each session's tokens went: re-reading the cached context, writing to the cache, or output. Use it
before and after a change to how agents work, and in a retro (.agents/skills/retro).

Usage:
  scripts/session-usage.py [--days N] [--match TEXT] [--claude-dir DIR] [--codex-dir DIR]
  Defaults: the last 14 days, sessions whose folder or working directory contains "overreach".

Claude Code logs: ~/.claude/projects/<project>/*.jsonl (subagents in <session>/subagents/). Codex logs:
~/.codex/sessions/**/rollout-*.jsonl; Codex shows tokens only, without a cost. Cloud sessions keep their logs in
their own container, so run this on each machine where sessions ran. Cost uses API list prices: on a subscription,
read it as a share of the usage limit.
"""
import argparse
import json
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

# $ per million tokens: input, output, cache read. Cache writes cost 1.25x input (5 min) or 2x input (1 hour).
PRICES = {
    "opus": (4.00, 20.00, 0.20),
    "sonnet": (2.00, 10.00, 0.10),
    "haiku": (0.10, 0.50, 0.01),
    "fable": (8.00, 40.00, 0.20),
    "mythos": (8.00, 40.00, 0.20),
}
UNKNOWN_PRICE = PRICES["opus"]
LARGE_CONTEXT = 300_000


def price(model):
    return next((value for family, value in PRICES.items() if family in (model or "")), UNKNOWN_PRICE)


def parse_time(text):
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None


def read_lines(path):
    with open(path, encoding="utf-8", errors="replace") as file:
        for line in file:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


class Session:
    def __init__(self, source, key):
        self.source = source
        self.key = key
        self.title = ""
        self.cwd = ""
        self.start = None
        self.end = None
        self.requests = 0
        self.peak_context = 0
        self.prompts = 0
        self.cost = defaultdict(float)  # read, write, output, input, other_models
        self.tokens = defaultdict(int)

    def seen(self, moment):
        if moment:
            self.start = min(self.start or moment, moment)
            self.end = max(self.end or moment, moment)

    @property
    def total(self):
        return sum(self.cost.values())


def add_claude_file(session, path, main_model_costs):
    messages = {}
    for entry in read_lines(path):
        session.seen(parse_time(entry.get("timestamp")))
        session.cwd = session.cwd or entry.get("cwd", "")
        kind = entry.get("type")
        if kind == "ai-title":
            session.title = entry.get("aiTitle", session.title)
        elif kind == "user" and not entry.get("isSidechain") and isinstance(entry.get("message", {}).get("content"), str):
            session.prompts += 1
        elif kind == "assistant":
            message = entry.get("message", {})
            if message.get("usage"):
                messages[message.get("id") or entry.get("uuid")] = message
    for message in messages.values():
        usage = message["usage"]
        model = message.get("model", "")
        if model == "<synthetic>":
            continue
        input_price, output_price, read_price = price(model)
        creation = usage.get("cache_creation") or {}
        write_1h = creation.get("ephemeral_1h_input_tokens", 0)
        write_5m = usage.get("cache_creation_input_tokens", 0) - write_1h
        costs = {
            "read": usage.get("cache_read_input_tokens", 0) * read_price,
            "write": write_5m * input_price * 1.25 + write_1h * input_price * 2,
            "output": usage.get("output_tokens", 0) * output_price,
            "input": usage.get("input_tokens", 0) * input_price,
        }
        context = sum(usage.get(field, 0) for field in
                      ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
        if main_model_costs:
            session.requests += 1
            session.peak_context = max(session.peak_context, context)
            for part, value in costs.items():
                session.cost[part] += value / 1e6
        else:
            session.cost["other_models"] += sum(costs.values()) / 1e6
        session.tokens["read"] += usage.get("cache_read_input_tokens", 0)
        session.tokens["output"] += usage.get("output_tokens", 0)


def claude_sessions(root, match, since):
    sessions = []
    for project in sorted(root.glob("*")) if root.is_dir() else []:
        for path in project.glob("*.jsonl"):
            if datetime.fromtimestamp(path.stat().st_mtime, timezone.utc) < since:
                continue
            session = Session("claude", path.stem)
            add_claude_file(session, path, main_model_costs=True)
            for subagent in (project / path.stem).glob("**/*.jsonl"):
                add_claude_file(session, subagent, main_model_costs=False)
            if match in (project.name + session.cwd).lower() and session.requests:
                sessions.append(session)
    return sessions


def codex_sessions(root, match, since):
    sessions = []
    for path in root.glob("**/rollout-*.jsonl") if root.is_dir() else []:
        if datetime.fromtimestamp(path.stat().st_mtime, timezone.utc) < since:
            continue
        session = Session("codex", path.stem.removeprefix("rollout-"))
        totals = {}
        for entry in read_lines(path):
            session.seen(parse_time(entry.get("timestamp")))
            payload = entry.get("payload") or {}
            if entry.get("type") == "session_meta":
                session.cwd = payload.get("cwd", "")
            elif payload.get("type") == "token_count":
                info = payload.get("info") or {}
                totals = info.get("total_token_usage") or totals
                last = info.get("last_token_usage") or {}
                session.requests += 1 if last else 0
                session.peak_context = max(session.peak_context, last.get("input_tokens", 0))
            elif payload.get("type") == "user_message":
                session.prompts += 1
        if match in session.cwd.lower() and totals:
            session.tokens["read"] = totals.get("cached_input_tokens", 0)
            session.tokens["input"] = totals.get("input_tokens", 0) - session.tokens["read"]
            session.tokens["output"] = totals.get("output_tokens", 0)
            sessions.append(session)
    return sessions


def share(part, total):
    return f"{100 * part / total:3.0f}%" if total else "  -"


def hours(session):
    return (session.end - session.start).total_seconds() / 3600 if session.start and session.end else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--days", type=int, default=14)
    parser.add_argument("--match", default="overreach")
    parser.add_argument("--claude-dir", type=Path, default=Path.home() / ".claude" / "projects")
    parser.add_argument("--codex-dir", type=Path, default=Path.home() / ".codex" / "sessions")
    args = parser.parse_args()
    since = datetime.now(timezone.utc) - timedelta(days=args.days)
    match = args.match.lower()

    claude = sorted(claude_sessions(args.claude_dir, match, since), key=lambda s: s.start or since)
    codex = sorted(codex_sessions(args.codex_dir, match, since), key=lambda s: s.start or since)

    if claude:
        print("Claude Code: estimated cost at API list prices; shares of each session's cost")
        print(f"{'start':16} {'hours':>5} {'prompts':>7} {'calls':>5} {'peak ctx':>8} {'cost $':>7} "
              f"{'reread':>6} {'cache':>6} {'output':>6} {'other':>6}  title")
        totals = defaultdict(float)
        for s in claude:
            for part, value in s.cost.items():
                totals[part] += value
            print(f"{s.start:%Y-%m-%d %H:%M} {hours(s):5.1f} {s.prompts:7} {s.requests:5} {s.peak_context // 1000:7}k "
                  f"{s.total:7.2f} {share(s.cost['read'], s.total):>6} {share(s.cost['write'], s.total):>6} "
                  f"{share(s.cost['output'], s.total):>6} {share(s.cost['other_models'], s.total):>6}  "
                  f"{(s.title or s.key)[:50]}")
        total = sum(totals.values())
        print(f"Total {len(claude)} sessions: ${total:.2f}; reread {share(totals['read'], total).strip()}, "
              f"cache writes {share(totals['write'], total).strip()}, output {share(totals['output'], total).strip()}, "
              f"subagents and other models {share(totals['other_models'], total).strip()}")
        large = [s for s in claude if s.peak_context > LARGE_CONTEXT]
        if large:
            cost = sum(s.total for s in large)
            print(f"{len(large)} sessions passed {LARGE_CONTEXT // 1000}k tokens of context and cost "
                  f"{share(cost, total).strip()} of the total.")
    if codex:
        print("\nCodex: tokens only")
        print(f"{'start':16} {'hours':>5} {'prompts':>7} {'calls':>5} {'peak ctx':>8} {'cached in':>10} "
              f"{'new in':>9} {'output':>9}  folder")
        for s in codex:
            print(f"{s.start:%Y-%m-%d %H:%M} {hours(s):5.1f} {s.prompts:7} {s.requests:5} {s.peak_context // 1000:7}k "
                  f"{s.tokens['read']:10} {s.tokens['input']:9} {s.tokens['output']:9}  {s.cwd.replace(chr(92), '/').rstrip('/').split('/')[-1]}")
    if not claude and not codex:
        print(f"No sessions matching '{args.match}' in the last {args.days} days under {args.claude_dir} "
              f"or {args.codex_dir}.")


if __name__ == "__main__":
    main()
