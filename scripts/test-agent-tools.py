#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


usage = load("session-usage")
watcher = load("watch-prs")
NOW = "2026-11-25T12:00:00Z"


def record(kind, **payload):
    return {"type": kind, "timestamp": NOW, "payload": payload}


def token_stats(total, cached, output):
    return record("event_msg", type="token_count", info={"total_token_usage": {
        "input_tokens": total, "cached_input_tokens": cached, "output_tokens": output,
    }})


class SessionUsageTests(unittest.TestCase):
    def test_grouping_excludes_copied_history_with_rewritten_timestamps(self):
        root = record("session_meta", id="chat", cwd="/overreach", timestamp=NOW)
        child = record("session_meta", id="child", cwd="/elsewhere", timestamp=NOW, source={
            "subagent": {"thread_spawn": {"parent_thread_id": "chat", "agent_path": "/root/worker"}},
        })
        monitor = record("response_item", type="custom_tool_call", input="gh run watch 123")
        fork = [
            child, root, monitor, record("turn_context", model="parent-model"), token_stats(10, 5, 1),
            record("event_msg", type="thread_settings_applied", thread_id="child"),
            record("turn_context", model="small-model"), token_stats(20, 15, 3), token_stats(20, 15, 3),
        ]
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            for name, records in {"root": [root, monitor, token_stats(10, 5, 1)], "child": fork}.items():
                path = directory / f"rollout-{name}.jsonl"
                path.write_text("\n".join(map(json.dumps, records)), encoding="utf-8")
            observed = usage.codex_sessions(directory, "overreach", datetime.min.replace(tzinfo=timezone.utc), "chat")
        agents = {s.agent: s for s in observed}
        self.assertEqual(agents["root"].ci_calls, 1)
        worker = agents["/root/worker"]
        self.assertEqual(worker.ci_calls, 0)
        self.assertEqual(worker.models, {"small-model"})
        self.assertEqual(worker.requests, 1)
        self.assertEqual(dict(worker.tokens), {"read": 15, "input": 5, "output": 3})


class WatchTests(unittest.TestCase):
    def test_pending_failed_and_successful_checks(self):
        def pr(*checks, state="OPEN"):
            return {"state": state, "statusCheckRollup": checks}

        success = {"name": "linux", "status": "COMPLETED", "conclusion": "SUCCESS"}
        waiting = {"name": "macos", "status": "QUEUED", "conclusion": ""}
        failure = {"context": "external", "state": "FAILURE"}
        self.assertEqual(watcher.summarize(pr())[0], "pending")
        self.assertEqual(watcher.summarize(pr(success, waiting))[0], "pending")
        self.assertEqual(watcher.summarize(pr(success, failure))[0], "failed")
        self.assertEqual(watcher.summarize(pr(success))[0], "passed")
        self.assertEqual(watcher.summarize(pr(state="MERGED"))[0], "passed")
        self.assertEqual(watcher.summarize(pr(state="CLOSED"))[0], "failed")


if __name__ == "__main__":
    unittest.main()
