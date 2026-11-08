import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

MODULE_PATH = Path(__file__).resolve().parents[2] / "runner/oto_runner.py"
SPEC = importlib.util.spec_from_file_location("oto_runner", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
oto_runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = oto_runner
SPEC.loader.exec_module(oto_runner)

TIMEZONE = ZoneInfo("Asia/Ho_Chi_Minh")


class FakeClock(oto_runner.Clock):
    def __init__(self, start_time: datetime):
        self._current = start_time.astimezone(TIMEZONE)

    def now(self) -> datetime:
        return self._current

    def advance(self, delta: timedelta) -> None:
        self._current += delta

    def set_time(self, new_time: datetime) -> None:
        self._current = new_time.astimezone(TIMEZONE)

    def sleep(self, seconds: float) -> None:
        self._current += timedelta(seconds=seconds)


class SchedulerPolicyTests(unittest.TestCase):
    def test_classify_codex_failure_quota(self):
        for phrase in ("insufficient_quota", "Rate limit exceeded", "Error 429", "exceeded your current quota", "out of credits", "usage limit"):
            res = oto_runner.CommandResult(1, "", phrase)
            self.assertEqual(oto_runner.classify_codex_failure(res), "quota")

    def test_classify_codex_failure_auth(self):
        for phrase in ("unauthorized access", "authentication failed", "401 Unauthorized", "login required", "invalid api key"):
            res = oto_runner.CommandResult(1, "", phrase)
            self.assertEqual(oto_runner.classify_codex_failure(res), "auth")

    def test_classify_codex_failure_network(self):
        for phrase in ("connection failed", "timeout occurred", "reconnecting to server", "dns resolution failed", "503 service unavailable", "502 Bad Gateway"):
            res = oto_runner.CommandResult(1, "", phrase)
            self.assertEqual(oto_runner.classify_codex_failure(res), "network/transient")

    def test_classify_codex_failure_tool_internal(self):
        res = oto_runner.CommandResult(2, "", "unexpected rust panic")
        self.assertEqual(oto_runner.classify_codex_failure(res), "tool/internal")

    def test_classify_codex_failure_review_finding(self):
        res = oto_runner.CommandResult(0, '{"approved": false}', "")
        self.assertEqual(oto_runner.classify_codex_failure(res), "review_finding")


class WorktreeAndQueueTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name).resolve()
        self.state_dir = self.root / ".oto-runner"
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.runner_dir = self.root / "runner"
        self.runner_dir.mkdir(parents=True, exist_ok=True)

        # Initialize real git repo in temp_dir
        subprocess.run(["git", "init", "-b", "main"], cwd=self.root, check=True, capture_output=True)
        subprocess.run(["git", "config", "user.name", "Tester"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.email", "tester@oto.test"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "commit.gpgsign", "false"], cwd=self.root, check=True)
        subprocess.run(["git", "remote", "add", "origin", "https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player"], cwd=self.root, check=True)

        self.config = {
            "agy_path": "/fake/agy",
            "codex_path": "/fake/codex",
            "gemini_model": "test-gemini",
            "gemini_effort": "high",
            "remote": "origin",
            "branch": "main",
            "max_repair_rounds": 2,
            "agent_timeout_minutes": 5,
            "stop_hour": 5,
            "shutdown_margin_minutes": 10,
        }

        # Create initial baseline commit
        (self.root / ".gitignore").write_text(".oto-runner/\n", encoding="utf-8")
        (self.root / "README.md").write_text("# Oto Test\n", encoding="utf-8")
        (self.runner_dir / "backlog.json").write_text(json.dumps({"tasks": []}), encoding="utf-8")
        (self.runner_dir / "config.json").write_text(json.dumps(self.config), encoding="utf-8")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-m", "Initial baseline"], cwd=self.root, check=True)

        # Patch ROOT and STATE_DIR and RUNNER_DIR in oto_runner
        self.patchers = [
            mock.patch.object(oto_runner, "ROOT", self.root),
            mock.patch.object(oto_runner, "STATE_DIR", self.state_dir),
            mock.patch.object(oto_runner, "RUNNER_DIR", self.runner_dir),
        ]
        for p in self.patchers:
            p.start()

    def tearDown(self):
        for p in reversed(self.patchers):
            p.stop()
        self.temp_dir.cleanup()

    def test_worktree_lifecycle(self):
        base_head = oto_runner.git("rev-parse", "HEAD")
        wt = oto_runner.create_task_worktree("TASK-01", base_head)
        self.assertTrue(wt.exists())
        self.assertTrue((wt / ".git").exists())

        # Check git status works inside worktree
        changes = oto_runner.repository_changes(cwd=wt)
        self.assertEqual(changes, [])

        # Remove worktree
        oto_runner.remove_task_worktree("TASK-01")
        self.assertFalse(wt.exists())

    def test_quota_exhaustion_transitions_to_awaiting_review(self):
        task = {
            "id": "TASK-01",
            "title": "Task 1",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": ["Tạo Sources/A.swift"],
            "checks": [["true"]],
            "commit_message": "feat: task 1",
        }
        clock = FakeClock(datetime(2026, 11, 9, 1, 0, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)

        def fake_gemini(t, c, run_dir, review, timeout, cwd=None):
            src_dir = cwd / "Sources"
            src_dir.mkdir(parents=True, exist_ok=True)
            (src_dir / "A.swift").write_text("// A\n", encoding="utf-8")
            return {"status": "completed"}

        with mock.patch.object(oto_runner, "call_gemini", side_effect=fake_gemini), \
             mock.patch.object(oto_runner, "call_codex_review", return_value=(None, "quota")):
            result = oto_runner.execute_task_in_worktree(task, self.config, cutoff, clock=clock)

        self.assertEqual(result, "AWAITING_REVIEW")

        # Worktree is preserved
        wt_dir = oto_runner.task_worktree_dir("TASK-01")
        self.assertTrue(wt_dir.exists())
        self.assertTrue((wt_dir / "Sources/A.swift").exists())

        # Checkpoint recorded correctly
        cp = oto_runner.load_task_checkpoint("TASK-01")
        self.assertIsNotNone(cp)
        self.assertEqual(cp["stage"], "AWAITING_REVIEW")
        self.assertEqual(cp["last_error_class"], "quota")
        self.assertIsNotNone(cp["candidate_tree"])

        # Main branch has NOT changed
        self.assertFalse((self.root / "Sources/A.swift").exists())

        # Handoff contains explanation
        handoff_content = (self.state_dir / "handoff.md").read_text(encoding="utf-8")
        self.assertIn("Codex hết quota", handoff_content)

    def test_worktree_isolation_between_tasks(self):
        task1 = {
            "id": "TASK-01",
            "title": "Task 1",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: task 1",
        }
        task2 = {
            "id": "TASK-02",
            "title": "Task 2",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: task 2",
        }
        clock = FakeClock(datetime(2026, 11, 9, 1, 0, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)

        def fake_gemini_1(t, c, run_dir, review, timeout, cwd=None):
            (cwd / "Sources").mkdir(parents=True, exist_ok=True)
            (cwd / "Sources/File1.swift").write_text("// File 1\n", encoding="utf-8")
            return {"status": "completed"}

        def fake_gemini_2(t, c, run_dir, review, timeout, cwd=None):
            (cwd / "Sources").mkdir(parents=True, exist_ok=True)
            (cwd / "Sources/File2.swift").write_text("// File 2\n", encoding="utf-8")
            return {"status": "completed"}

        with mock.patch.object(oto_runner, "call_gemini", side_effect=fake_gemini_1), \
             mock.patch.object(oto_runner, "call_codex_review", return_value=(None, "quota")):
            res1 = oto_runner.execute_task_in_worktree(task1, self.config, cutoff, clock=clock)
        self.assertEqual(res1, "AWAITING_REVIEW")

        with mock.patch.object(oto_runner, "call_gemini", side_effect=fake_gemini_2), \
             mock.patch.object(oto_runner, "call_codex_review", return_value=(None, "quota")):
            res2 = oto_runner.execute_task_in_worktree(task2, self.config, cutoff, clock=clock)
        self.assertEqual(res2, "AWAITING_REVIEW")

        wt1 = oto_runner.task_worktree_dir("TASK-01")
        wt2 = oto_runner.task_worktree_dir("TASK-02")

        self.assertTrue((wt1 / "Sources/File1.swift").exists())
        self.assertFalse((wt1 / "Sources/File2.swift").exists())

        self.assertTrue((wt2 / "Sources/File2.swift").exists())
        self.assertFalse((wt2 / "Sources/File1.swift").exists())

        self.assertFalse((self.root / "Sources/File1.swift").exists())
        self.assertFalse((self.root / "Sources/File2.swift").exists())

    def test_clock_retry_at_0345_triggers_exactly_once(self):
        clock = FakeClock(datetime(2026, 11, 9, 3, 30, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)
        retry_time = datetime(2026, 11, 9, 3, 45, tzinfo=TIMEZONE)

        backlog_path = self.runner_dir / "backlog.json"
        backlog_data = {
            "tasks": [
                {"id": "TASK-01", "status": "AWAITING_REVIEW", "title": "T1"}
            ]
        }
        backlog_path.write_text(json.dumps(backlog_data), encoding="utf-8")
        subprocess.run(["git", "commit", "-am", "Update backlog"], cwd=self.root, check=True)

        retry_count = 0
        def fake_retry(task, config, c, m, clock=None):
            nonlocal retry_count
            retry_count += 1
            return "AWAITING_REVIEW"

        # Advance to 03:45
        clock.set_time(datetime(2026, 11, 9, 3, 45, tzinfo=TIMEZONE))

        with mock.patch.object(oto_runner, "retry_awaiting_task", side_effect=fake_retry):
            # Run queue; it will retry once and then exit because no READY tasks exist
            oto_runner.run_queue(
                self.config,
                backlog_path,
                cutoff=cutoff,
                retry_time=retry_time,
                clock=clock,
            )

        self.assertEqual(retry_count, 1)

    def test_retry_0345_approval_delivers_to_main(self):
        task = {
            "id": "TASK-01",
            "title": "Task 1",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: deliver task 1",
        }
        clock = FakeClock(datetime(2026, 11, 9, 1, 0, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)

        def fake_gemini(t, c, run_dir, review, timeout, cwd=None):
            (cwd / "Sources").mkdir(parents=True, exist_ok=True)
            (cwd / "Sources/Deliver.swift").write_text("// Deliver\n", encoding="utf-8")
            return {"status": "completed"}

        # First run: Codex out of quota -> AWAITING_REVIEW
        with mock.patch.object(oto_runner, "call_gemini", side_effect=fake_gemini), \
             mock.patch.object(oto_runner, "call_codex_review", return_value=(None, "quota")):
            res = oto_runner.execute_task_in_worktree(task, self.config, cutoff, clock=clock)
        self.assertEqual(res, "AWAITING_REVIEW")

        # Advance clock to 03:45
        clock.set_time(datetime(2026, 11, 9, 3, 45, tzinfo=TIMEZONE))

        approved_review = {"approved": True, "summary": "Approved cleanly", "findings": []}
        with mock.patch.object(oto_runner, "call_codex_review", return_value=(approved_review, None)), \
             mock.patch.object(oto_runner, "push_revision") as mock_push:
            res_retry = oto_runner.retry_awaiting_task(
                task, self.config, cutoff, timedelta(minutes=10), clock=clock
            )

        self.assertEqual(res_retry, "DONE")
        # Check that candidate changes are delivered to main
        self.assertTrue((self.root / "Sources/Deliver.swift").exists())
        # Worktree is removed
        wt_dir = oto_runner.task_worktree_dir("TASK-01")
        self.assertFalse(wt_dir.exists())
        # push_revision was invoked
        mock_push.assert_called_once()

    def test_stop_accepting_at_0450(self):
        clock = FakeClock(datetime(2026, 11, 9, 4, 50, 5, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)
        stop_accepting = datetime(2026, 11, 9, 4, 50, tzinfo=TIMEZONE)

        backlog_path = self.runner_dir / "backlog.json"
        backlog_data = {
            "tasks": [
                {"id": "TASK-01", "status": "READY", "title": "T1"}
            ]
        }
        backlog_path.write_text(json.dumps(backlog_data), encoding="utf-8")
        subprocess.run(["git", "commit", "-am", "Update backlog"], cwd=self.root, check=True)

        with mock.patch.object(oto_runner, "execute_task_in_worktree") as mock_exec:
            oto_runner.run_queue(
                self.config,
                backlog_path,
                cutoff=cutoff,
                stop_accepting_time=stop_accepting,
                clock=clock,
            )
            mock_exec.assert_not_called()

        handoff_content = (self.state_dir / "handoff.md").read_text(encoding="utf-8")
        self.assertIn("Dừng nhận task mới (04:50/cutoff)", handoff_content)

    def test_inflight_task_stops_at_0500_cutoff_and_halts_queue(self):
        clock = FakeClock(datetime(2026, 11, 9, 4, 45, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)
        stop_accepting = datetime(2026, 11, 9, 4, 50, tzinfo=TIMEZONE)

        backlog_path = self.runner_dir / "backlog.json"
        backlog_data = {
            "tasks": [
                {"id": "TASK-01", "status": "READY", "title": "T1"},
                {"id": "TASK-02", "status": "READY", "title": "T2"},
            ]
        }
        backlog_path.write_text(json.dumps(backlog_data), encoding="utf-8")
        subprocess.run(["git", "commit", "-am", "Update backlog"], cwd=self.root, check=True)

        executed_tasks = []
        def fake_exec(task, config, c, clock=None):
            executed_tasks.append(task["id"])
            # While executing TASK-01, clock reaches cutoff 05:00!
            clock.set_time(datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE))
            return "DONE"

        with mock.patch.object(oto_runner, "execute_task_in_worktree", side_effect=fake_exec):
            oto_runner.run_queue(
                self.config,
                backlog_path,
                cutoff=cutoff,
                stop_accepting_time=stop_accepting,
                clock=clock,
            )

        # TASK-01 executed, and TASK-02 was NOT started because 05:00 cutoff was reached!
        self.assertEqual(executed_tasks, ["TASK-01"])
        handoff_content = (self.state_dir / "handoff.md").read_text(encoding="utf-8")
        self.assertIn("Dừng hàng đợi lúc cutoff (05:00)", handoff_content)

    def test_modified_working_tree_after_review_blocked_from_delivery(self):
        task = {
            "id": "TASK-01",
            "title": "Task 1",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: test modified",
        }
        base_head = oto_runner.git("rev-parse", "HEAD")
        wt = oto_runner.create_task_worktree("TASK-01", base_head)
        (wt / "Sources").mkdir(parents=True, exist_ok=True)
        (wt / "Sources/File.swift").write_text("// Original\n", encoding="utf-8")

        changed, candidate_tree, candidate_head = oto_runner.stage_review_snapshot(task, cwd=wt)

        # Tamper: modify the file after snapshot
        (wt / "Sources/File.swift").write_text("// Tampered after review!\n", encoding="utf-8")

        with self.assertRaises(oto_runner.RunnerError) as ctx:
            oto_runner.verify_review_snapshot(candidate_tree, candidate_head, cwd=wt)
        self.assertIn("Working tree thay đổi sau review", str(ctx.exception))

        oto_runner.remove_task_worktree("TASK-01")

    def test_no_secret_in_checkpoint_or_handoff(self):
        task = {
            "id": "TASK-01",
            "title": "Task 1",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: test secrets",
        }
        clock = FakeClock(datetime(2026, 11, 9, 1, 0, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)

        secret_str = "sensitive_bearer_token_xyz123"
        secret_summary = f"Bearer {secret_str} found in authorization header"

        def fake_gemini(t, c, run_dir, review, timeout, cwd=None):
            (cwd / "Sources").mkdir(parents=True, exist_ok=True)
            (cwd / "Sources/File.swift").write_text("// Ok\n", encoding="utf-8")
            return {"status": "completed"}

        def fake_codex(t, c, run_dir, timeout, cwd=None):
            return {"approved": False, "summary": secret_summary, "findings": []}, None

        with mock.patch.object(oto_runner, "call_gemini", side_effect=fake_gemini), \
             mock.patch.object(oto_runner, "call_codex_review", side_effect=fake_codex):
            oto_runner.execute_task_in_worktree(task, self.config, cutoff, clock=clock)

        cp = oto_runner.load_task_checkpoint("TASK-01")
        cp_str = json.dumps(cp)
        self.assertNotIn(secret_str, cp_str)

    def test_sequential_delivery_of_multiple_worktrees(self):
        base_head = oto_runner.git("rev-parse", "HEAD")
        clock = FakeClock(datetime(2026, 11, 9, 3, 50, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)

        # Worktree 1 for Task 1
        task1 = {
            "id": "TASK-01",
            "title": "Task 1",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: task 1 sequential",
        }
        wt1 = oto_runner.create_task_worktree("TASK-01", base_head)
        (wt1 / "Sources").mkdir(parents=True, exist_ok=True)
        (wt1 / "Sources/Task1.swift").write_text("// Task 1\n", encoding="utf-8")
        changed1, tree1, head1 = oto_runner.stage_review_snapshot(task1, cwd=wt1)

        # Worktree 2 for Task 2 (both from base_head)
        task2 = {
            "id": "TASK-02",
            "title": "Task 2",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: task 2 sequential",
        }
        wt2 = oto_runner.create_task_worktree("TASK-02", base_head)
        (wt2 / "Sources").mkdir(parents=True, exist_ok=True)
        (wt2 / "Sources/Task2.swift").write_text("// Task 2\n", encoding="utf-8")
        changed2, tree2, head2 = oto_runner.stage_review_snapshot(task2, cwd=wt2)

        # Deliver Task 1 to main
        with mock.patch.object(oto_runner, "push_revision"):
            rev1 = oto_runner.deliver_approved_worktree_task(
                task1, self.config, tree1, head1, base_head, cutoff, timedelta(minutes=10), cwd=wt1, clock=clock
            )
        self.assertTrue((self.root / "Sources/Task1.swift").exists())
        self.assertEqual(oto_runner.git("rev-parse", "HEAD"), rev1)

        # Now deliver Task 2 to main (where current_head != base_head)
        with mock.patch.object(oto_runner, "call_codex_review", return_value=({"approved": True, "findings": []}, None)), \
             mock.patch.object(oto_runner, "push_revision"):
            rev2 = oto_runner.deliver_approved_worktree_task(
                task2, self.config, tree2, head2, base_head, cutoff, timedelta(minutes=10), cwd=wt2, clock=clock
            )

        self.assertEqual(oto_runner.git("rev-parse", "HEAD"), rev2)
        # Both files are now present on main!
        self.assertTrue((self.root / "Sources/Task1.swift").exists())
        self.assertTrue((self.root / "Sources/Task2.swift").exists())

        oto_runner.remove_task_worktree("TASK-01")
        oto_runner.remove_task_worktree("TASK-02")

    def test_deliver_approved_worktree_task_blocks_if_rebase_review_exceeds_margin(self):
        clock = FakeClock(datetime(2026, 11, 9, 4, 30, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)
        margin = timedelta(minutes=10)
        base_head = oto_runner.git("rev-parse", "HEAD")

        task1 = {
            "id": "TASK-01",
            "title": "Task 1",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: task 1",
        }
        wt1 = oto_runner.create_task_worktree("TASK-01", base_head)
        (wt1 / "Sources").mkdir(parents=True, exist_ok=True)
        (wt1 / "Sources/Task1.swift").write_text("// Task 1\n", encoding="utf-8")
        changed1, tree1, head1 = oto_runner.stage_review_snapshot(task1, cwd=wt1)
        with mock.patch.object(oto_runner, "push_revision"):
            rev1 = oto_runner.deliver_approved_worktree_task(
                task1, self.config, tree1, head1, base_head, cutoff, margin, cwd=wt1, clock=clock
            )

        task2 = {
            "id": "TASK-02",
            "title": "Task 2",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: task 2",
        }
        wt2 = oto_runner.create_task_worktree("TASK-02", base_head)
        (wt2 / "Sources").mkdir(parents=True, exist_ok=True)
        (wt2 / "Sources/Task2.swift").write_text("// Task 2\n", encoding="utf-8")
        changed2, tree2, head2 = oto_runner.stage_review_snapshot(task2, cwd=wt2)

        def review_side_effect(*args, **kwargs):
            clock.set_time(datetime(2026, 11, 9, 4, 55, tzinfo=TIMEZONE))
            return ({"approved": True, "findings": []}, None)

        with mock.patch.object(oto_runner, "call_codex_review", side_effect=review_side_effect), \
             mock.patch.object(oto_runner, "push_revision"):
            with self.assertRaises(oto_runner.RunnerError):
                oto_runner.deliver_approved_worktree_task(
                    task2, self.config, tree2, head2, base_head, cutoff, margin, cwd=wt2, clock=clock
                )

        self.assertEqual(oto_runner.git("rev-parse", "HEAD"), rev1)
        self.assertFalse((self.root / "Sources/Task2.swift").exists())

        oto_runner.remove_task_worktree("TASK-01")
        oto_runner.remove_task_worktree("TASK-02")

    def test_push_revision_blocks_when_in_shutdown_margin(self):
        clock = FakeClock(datetime(2026, 11, 9, 4, 55, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)
        margin = timedelta(minutes=10) # shutdown margin starts at 04:50
        rev = oto_runner.git("rev-parse", "HEAD")

        with mock.patch.object(oto_runner, "ensure_authorized_git_target"), \
             mock.patch.object(oto_runner, "ensure_clean_repository"), \
             mock.patch.object(oto_runner, "git") as mock_git:
            mock_git.side_effect = lambda *args, **kwargs: rev if args[0] == "rev-parse" else ""
            with self.assertRaises(oto_runner.RunnerError) as ctx:
                oto_runner.push_revision(self.config, rev, cutoff, margin, clock=clock)
            self.assertIn("vùng dừng", str(ctx.exception))
            # Verify git push was not called in the shutdown margin
            self.assertFalse(any(call[0][0] == "push" for call in mock_git.call_args_list))

    def test_retry_0345_stops_if_clock_reaches_cutoff(self):
        task = {
            "id": "TASK-01",
            "title": "Task 1",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: test cutoff retry",
        }
        base_head = oto_runner.git("rev-parse", "HEAD")
        clock = FakeClock(datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)

        wt = oto_runner.create_task_worktree("TASK-01", base_head)
        (wt / "Sources").mkdir(parents=True, exist_ok=True)
        (wt / "Sources/A.swift").write_text("// A\n", encoding="utf-8")
        changed, tree, head = oto_runner.stage_review_snapshot(task, cwd=wt)
        oto_runner.unstage_paths(changed, cwd=wt)

        oto_runner.task_checkpoint(
            "TASK-01", "AWAITING_REVIEW", clock=clock,
            worktree_path=str(wt.resolve()),
            candidate_tree=tree,
            candidate_head=head,
            base_revision=base_head,
            changed_paths=changed,
            last_error_class="quota",
        )

        res = oto_runner.retry_awaiting_task(task, self.config, cutoff, timedelta(minutes=10), clock=clock)
        self.assertEqual(res, "BLOCKED")
        cp = oto_runner.load_task_checkpoint("TASK-01")
        self.assertEqual(cp["last_error_class"], "cutoff_exceeded")
        oto_runner.remove_task_worktree("TASK-01")

    def test_retry_0345_findings_executes_repair_loop_and_delivers(self):
        task = {
            "id": "TASK-01",
            "title": "Task 1",
            "allowed_paths": ["Sources/**"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: fix finding and deliver",
        }
        base_head = oto_runner.git("rev-parse", "HEAD")
        clock = FakeClock(datetime(2026, 11, 9, 3, 45, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)

        wt = oto_runner.create_task_worktree("TASK-01", base_head)
        (wt / "Sources").mkdir(parents=True, exist_ok=True)
        (wt / "Sources/A.swift").write_text("// Has typo\n", encoding="utf-8")
        changed, tree, head = oto_runner.stage_review_snapshot(task, cwd=wt)
        oto_runner.unstage_paths(changed, cwd=wt)

        oto_runner.task_checkpoint(
            "TASK-01", "AWAITING_REVIEW", clock=clock,
            worktree_path=str(wt.resolve()),
            candidate_tree=tree,
            candidate_head=head,
            base_revision=base_head,
            changed_paths=changed,
            last_error_class="quota",
        )

        review_findings = {
            "approved": False,
            "summary": "Fix typo in A.swift",
            "findings": [{"severity": "P2", "path": "Sources/A.swift", "line": 1, "summary": "Typo"}],
        }
        approved_review = {"approved": True, "summary": "Clean", "findings": []}

        def fake_gemini_fix(t, c, run_dir, review, timeout, cwd=None):
            (cwd / "Sources/A.swift").write_text("// Fixed typo\n", encoding="utf-8")
            return {"status": "completed"}

        call_count = 0
        def fake_codex_rounds(t, c, run_dir, timeout, cwd=None):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return review_findings, None
            return approved_review, None

        with mock.patch.object(oto_runner, "call_gemini", side_effect=fake_gemini_fix), \
             mock.patch.object(oto_runner, "call_codex_review", side_effect=fake_codex_rounds), \
             mock.patch.object(oto_runner, "push_revision"):
            res = oto_runner.retry_awaiting_task(task, self.config, cutoff, timedelta(minutes=10), clock=clock)

        self.assertEqual(res, "DONE")
        self.assertTrue((self.root / "Sources/A.swift").exists())
        self.assertEqual((self.root / "Sources/A.swift").read_text(encoding="utf-8"), "// Fixed typo\n")

    def test_sequential_delivery_conflict_blocks_task(self):
        base_head = oto_runner.git("rev-parse", "HEAD")
        clock = FakeClock(datetime(2026, 11, 9, 3, 50, tzinfo=TIMEZONE))
        cutoff = datetime(2026, 11, 9, 5, 0, tzinfo=TIMEZONE)

        # Initial shared file
        (self.root / "Shared.txt").write_text("Original line\n", encoding="utf-8")
        subprocess.run(["git", "add", "Shared.txt"], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-m", "add shared.txt"], cwd=self.root, check=True)
        common_base = oto_runner.git("rev-parse", "HEAD")

        task1 = {
            "id": "TASK-01",
            "title": "Task 1",
            "allowed_paths": ["Shared.txt"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: task 1 change shared",
        }
        wt1 = oto_runner.create_task_worktree("TASK-01", common_base)
        (wt1 / "Shared.txt").write_text("Conflicting line from Task 1\n", encoding="utf-8")
        changed1, tree1, head1 = oto_runner.stage_review_snapshot(task1, cwd=wt1)

        task2 = {
            "id": "TASK-02",
            "title": "Task 2",
            "allowed_paths": ["Shared.txt"],
            "acceptance_criteria": [],
            "checks": [["true"]],
            "commit_message": "feat: task 2 change shared",
        }
        wt2 = oto_runner.create_task_worktree("TASK-02", common_base)
        (wt2 / "Shared.txt").write_text("Conflicting line from Task 2\n", encoding="utf-8")
        changed2, tree2, head2 = oto_runner.stage_review_snapshot(task2, cwd=wt2)

        # Deliver Task 1
        with mock.patch.object(oto_runner, "push_revision"):
            oto_runner.deliver_approved_worktree_task(
                task1, self.config, tree1, head1, common_base, cutoff, timedelta(minutes=10), cwd=wt1, clock=clock
            )

        # Deliver Task 2 -> should raise RunnerError due to merge conflict
        with mock.patch.object(oto_runner, "push_revision"):
            with self.assertRaises(oto_runner.RunnerError) as ctx:
                oto_runner.deliver_approved_worktree_task(
                    task2, self.config, tree2, head2, common_base, cutoff, timedelta(minutes=10), cwd=wt2, clock=clock
                )
            self.assertIn("Conflict", str(ctx.exception))

        oto_runner.remove_task_worktree("TASK-01")
        oto_runner.remove_task_worktree("TASK-02")

    def test_ready_status_in_backlog_overrides_blocked_checkpoint(self):
        task = {
            "id": "TASK-BLOCK",
            "title": "Blocked task re-opened",
            "status": "READY",
        }
        # Initially blocked checkpoint
        oto_runner.task_checkpoint("TASK-BLOCK", "BLOCKED")
        self.assertEqual(oto_runner.load_task_checkpoint("TASK-BLOCK")["stage"], "BLOCKED")

        # When backlog says READY and not in current session blocked, get_task_stage returns READY
        self.assertEqual(oto_runner.get_task_stage(task), "READY")

        # When in session_blocked, it stays BLOCKED during that queue run
        self.assertEqual(oto_runner.get_task_stage(task, session_blocked={"TASK-BLOCK"}), "BLOCKED")

        # When backlog is DRAFT, blocked checkpoint or draft stays non-ready
        task_draft = {"id": "TASK-BLOCK", "status": "DRAFT"}
        self.assertEqual(oto_runner.get_task_stage(task_draft), "BLOCKED")

    def test_retry_push_updates_task_checkpoint_and_cleans_worktree(self):
        task_id = "TASK-PUSH-RETRY"
        base_head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=self.root, check=True, capture_output=True, text=True).stdout.strip()
        wt = oto_runner.create_task_worktree(task_id, base_head)
        self.assertTrue(wt.exists())

        # Set task checkpoint to DELIVERY_PENDING and global checkpoint to delivery_pending
        oto_runner.task_checkpoint(task_id, "DELIVERY_PENDING", revision=base_head)
        oto_runner.checkpoint(task_id, "delivery_pending", revision=base_head)

        with mock.patch.object(oto_runner, "push_revision"):
            with mock.patch("sys.argv", ["oto-runner", "retry-push", "--cutoff", "2026-11-10T05:00:00+07:00"]):
                exit_code = oto_runner.main()
                self.assertEqual(exit_code, 0)

        # Verify task checkpoint is DONE
        cp = oto_runner.load_task_checkpoint(task_id)
        self.assertIsNotNone(cp)
        self.assertEqual(cp["stage"], "DONE")

        # Verify worktree is removed
        self.assertFalse(wt.exists())

    def test_reset_task_clears_checkpoint_and_worktree(self):
        task_id = "TASK-RESET"
        base_head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=self.root, check=True, capture_output=True, text=True).stdout.strip()
        wt = oto_runner.create_task_worktree(task_id, base_head)
        oto_runner.task_checkpoint(task_id, "BLOCKED")
        oto_runner.checkpoint(task_id, "blocked")

        self.assertTrue(wt.exists())
        self.assertIsNotNone(oto_runner.load_task_checkpoint(task_id))

        # Reset single task
        ret = oto_runner.reset_task(task_id)
        self.assertEqual(ret, 0)
        self.assertFalse(wt.exists())
        self.assertIsNone(oto_runner.load_task_checkpoint(task_id))

        # Test reset --all
        wt2 = oto_runner.create_task_worktree("TASK-RESET-2", base_head)
        oto_runner.task_checkpoint("TASK-RESET-2", "APPROVED")
        self.assertTrue(wt2.exists())

        ret_all = oto_runner.reset_task(reset_all=True)
        self.assertEqual(ret_all, 0)
        self.assertFalse(wt2.exists())
        self.assertIsNone(oto_runner.load_task_checkpoint("TASK-RESET-2"))

    def test_validate_task_id_blocks_path_traversal(self):
        for bad_id in ("../..", "..", "/root", "foo/bar", "foo\\bar", ".hidden", "task/../sub", "", "   "):
            with self.assertRaises(oto_runner.RunnerError, msg=f"Should reject {bad_id}"):
                oto_runner.validate_task_id(bad_id)
            with self.assertRaises(oto_runner.RunnerError, msg=f"task_state_dir should reject {bad_id}"):
                oto_runner.task_state_dir(bad_id)
            with self.assertRaises(oto_runner.RunnerError, msg=f"task_worktree_dir should reject {bad_id}"):
                oto_runner.task_worktree_dir(bad_id)
            with self.assertRaises(oto_runner.RunnerError, msg=f"reset_task should reject {bad_id}"):
                oto_runner.reset_task(bad_id)

        # Valid task IDs
        for valid_id in ("TASK-01", "S1-001", "feat_login", "fix.issue-42"):
            self.assertEqual(oto_runner.validate_task_id(valid_id), valid_id)

    def test_handoff_includes_worktree_status(self):
        task_id = "TASK-WT-HANDOFF"
        base_head = oto_runner.git("rev-parse", "HEAD")
        wt = oto_runner.create_task_worktree(task_id, base_head)
        (wt / "NewFile.txt").write_text("Hello\n", encoding="utf-8")

        oto_runner.write_handoff("Test worktree handoff", task_id, "Details", worktree=wt)
        content = (self.state_dir / "handoff.md").read_text(encoding="utf-8")
        self.assertIn("Git status worktree", content)
        self.assertIn("NewFile.txt", content)

        oto_runner.remove_task_worktree(task_id)


if __name__ == "__main__":
    unittest.main()
