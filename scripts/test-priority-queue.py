#!/usr/bin/env python3
"""Exercise priority selection without making GitHub requests."""

import contextlib
import importlib.util
import io
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from priority_queue import ready_issues

spec = importlib.util.spec_from_file_location("claim_task", Path(__file__).with_name("claim-task.py"))
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)

ISSUES = "repos/droidsam1/overreach/issues"


def row(rank, issue):
    return f"{rank}. [#{issue}](https://github.com/droidsam1/overreach/issues/{issue}) — Build the feature."


def queue(*rows):
    return "\n".join(["# Priorities", "", "## Ready to implement", "", *rows])


class PriorityQueueTests(unittest.TestCase):
    def test_ready_rows_keep_their_order_and_ignore_delivery_history(self):
        markdown = queue(row(1, 8), row(2, 2), "", "## Shipped", row(1, 9))
        self.assertEqual([task.number for task in ready_issues(markdown)], ["8", "2"])

    def test_rejects_rows_with_ambiguous_or_duplicate_issues(self):
        invalid = (
            row(1, 8) + " [#9](https://github.com/droidsam1/overreach/issues/9)",
            row(1, 8).replace("[#8]", "[#9]"),
            row(1, 8) + "\n    See #9 for the rest.",
            row(1, 8) + "\n" + row(2, 8),
        )
        for invalid_rows in invalid:
            with self.subTest(rows=invalid_rows), self.assertRaisesRegex(ValueError, r"docs/priorities\.md:\d+:"):
                ready_issues(queue(invalid_rows))

    def test_selects_the_first_available_issue_and_reports_each_skip(self):
        priorities = ready_issues(queue(*(row(rank, rank) for rank in range(1, 7))))
        pulls = [
            {"number": 12, "body": "Task: #3", "created_at": "2026-11-24T10:00:01Z"},
            {"number": 11, "body": "Task: #3", "created_at": "2026-11-24T10:00:00Z"},
        ]
        responses = {
            (f"{ISSUES}/1", False): {"state": "closed"},
            (f"{ISSUES}/2", False): {"state": "open", "sub_issues_summary": {"total": 1}},
            (f"{ISSUES}/4", False): {"state": "open"},
            (f"{ISSUES}/4/dependencies/blocked_by?per_page=100", True): [
                {"number": 7, "state": "open"},
                {"number": 8, "state": "closed"},
            ],
            (f"{ISSUES}/6", False): {"state": "open"},
            (f"{ISSUES}/6/dependencies/blocked_by?per_page=100", True): [{"number": 8, "state": "closed"}],
        }
        with patch.object(selector, "open_pulls", return_value=pulls), patch.object(
            selector.claims, "gh", side_effect=lambda path, paginate=False: responses[path, paginate]
        ):
            task, skipped = selector.next_task("droidsam1", "overreach", priorities, {"#5"})
        self.assertEqual(task.number, "6")
        self.assertEqual(skipped, [
            "SKIP #1 - closed",
            "SKIP #2 - umbrella issue with sub-issues",
            "SKIP #3 - claimed by PR #11",
            "SKIP #4 - blocked by #7",
            "SKIP #5 - already attempted this run",
        ])

    def test_dry_run_prints_the_choice_or_reasons_without_claiming(self):
        task = ready_issues(queue(row(1, 8)))[0]
        for selection, status, first_line in ((task, 0, "NEXT #8"), (None, 1, "NONE -")):
            with self.subTest(status=status), contextlib.redirect_stdout(io.StringIO()) as output, patch.object(
                sys, "argv", ["claim-task.py", "--next", "--dry-run"]
            ), patch.object(selector.claims, "repository", return_value=("droidsam1", "overreach")), patch.object(
                selector, "git", return_value=queue(row(1, 8))
            ), patch.object(selector, "next_task", return_value=(selection, ["SKIP #7 - closed"])), patch.object(
                selector, "claim"
            ) as claim:
                self.assertEqual(selector.main(), status)
                self.assertTrue(output.getvalue().startswith(first_line))
                self.assertIn("SKIP #7 - closed", output.getvalue())
                claim.assert_not_called()

    def test_dry_run_rejects_an_explicit_claim_before_running_git(self):
        with patch.object(sys, "argv", ["claim-task.py", "--none", "maintenance", "--dry-run"]), patch.object(
            selector, "git"
        ) as git, contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            selector.main()
        self.assertEqual(error.exception.code, 2)
        git.assert_not_called()


if __name__ == "__main__":
    unittest.main()
