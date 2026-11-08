import importlib.util
from datetime import datetime, timedelta
from pathlib import Path
import sys
import unittest
from unittest import mock
from zoneinfo import ZoneInfo


MODULE_PATH = Path(__file__).resolve().parents[2] / "runner/oto_runner.py"
SPEC = importlib.util.spec_from_file_location("oto_runner", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
oto_runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = oto_runner
SPEC.loader.exec_module(oto_runner)


class RunnerPolicyTests(unittest.TestCase):
    def test_cutoff_la_05_gio_ke_tiep(self):
        timezone = ZoneInfo("Asia/Ho_Chi_Minh")
        before = datetime(2026, 11, 8, 23, 30, tzinfo=timezone)
        cutoff = oto_runner.compute_next_cutoff(before, 5)
        self.assertEqual(cutoff, datetime(2026, 11, 9, 5, 0, tzinfo=timezone))

    def test_cutoff_khi_dang_truoc_05_gio(self):
        timezone = ZoneInfo("Asia/Ho_Chi_Minh")
        before = datetime(2026, 11, 9, 1, 0, tzinfo=timezone)
        cutoff = oto_runner.compute_next_cutoff(before, 5)
        self.assertEqual(cutoff, datetime(2026, 11, 9, 5, 0, tzinfo=timezone))

    def test_scope_chap_nhan_file_con(self):
        self.assertTrue(oto_runner.matches_allowed_path("Oto/App/OtoApp.swift", ["Oto/**"]))

    def test_scope_tu_choi_repo_ke_ben(self):
        self.assertFalse(oto_runner.matches_allowed_path("../kaset/Package.swift", ["Oto/**"]))

    def test_scope_khong_nhan_ten_gan_giong(self):
        self.assertFalse(oto_runner.matches_allowed_path("OtoBackup/file.swift", ["Oto/**"]))

    def test_scope_giu_dau_cham_cua_gitignore(self):
        self.assertTrue(oto_runner.matches_allowed_path(".gitignore", [".gitignore"]))

    def test_cutoff_tu_choi_gio_khac_05_gio(self):
        with self.assertRaises(oto_runner.RunnerError):
            oto_runner.parse_cutoff("2026-11-09T17:00:00+07:00", 5)

    def test_remote_https_duoc_chuan_hoa(self):
        value = "https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player.git/"
        self.assertEqual(
            oto_runner.normalize_remote_url(value),
            "https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player",
        )

    def test_redact_token(self):
        self.assertNotIn(
            "abc123",
            oto_runner.redact_text("Authorization: Bearer abc123"),
        )

    def test_sanitized_json_che_gia_tri_theo_ten_khoa(self):
        value = oto_runner.sanitized_json({"access_token": "abc123", "name": "Oto"})
        self.assertEqual(value["access_token"], "REDACTED")
        self.assertEqual(value["name"], "Oto")

    def test_review_artifact_khong_luu_evidence(self):
        review = {
            "approved": False, "summary": "Cần sửa",
            "findings": [{"severity": "P1", "path": "runner/oto_runner.py",
                          "line": 1, "summary": "Lỗi",
                          "evidence": "cookie=secret-value"}],
        }
        artifact = oto_runner.review_artifact(review)
        self.assertNotIn("evidence", artifact["findings"][0])

    def test_ensure_authorized_git_target_tu_choi_nhieu_url(self):
        config = {"remote": "origin", "branch": "main"}
        with unittest.mock.patch.object(oto_runner, "ensure_isolated_repository"), \
             unittest.mock.patch.object(oto_runner, "git") as mock_git:
            mock_git.side_effect = lambda *args: {
                ("branch", "--show-current"): "main",
                ("remote", "get-url", "--all", "origin"): "https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player\nhttps://github.com/another/repo",
                ("remote", "get-url", "--push", "--all", "origin"): "https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player",
            }[args]
            with self.assertRaises(oto_runner.RunnerError) as context:
                oto_runner.ensure_authorized_git_target(config)
            self.assertIn("đúng một fetch URL và một push URL", str(context.exception))

    def test_ensure_authorized_git_target_tu_choi_push_url_ngoai_allowlist(self):
        config = {"remote": "origin", "branch": "main"}
        with unittest.mock.patch.object(oto_runner, "ensure_isolated_repository"), \
             unittest.mock.patch.object(oto_runner, "git") as mock_git:
            mock_git.side_effect = lambda *args: {
                ("branch", "--show-current"): "main",
                ("remote", "get-url", "--all", "origin"): "https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player",
                ("remote", "get-url", "--push", "--all", "origin"): "https://github.com/attacker/malicious-repo",
            }[args]
            with self.assertRaises(oto_runner.RunnerError) as context:
                oto_runner.ensure_authorized_git_target(config)
            self.assertIn("không được ủy quyền", str(context.exception))

    def test_verify_review_snapshot_phat_hien_tree_thay_doi(self):
        with unittest.mock.patch.object(oto_runner, "git") as mock_git:
            mock_git.side_effect = lambda *args: {
                ("write-tree",): "modified_tree_hash",
                ("rev-parse", "HEAD"): "head_hash",
            }[args]
            with self.assertRaises(oto_runner.RunnerError) as context:
                oto_runner.verify_review_snapshot("expected_tree_hash", "head_hash")
            self.assertIn("Snapshot đã thay đổi trong lúc review", str(context.exception))

    def test_verify_review_snapshot_phat_hien_working_tree_thay_doi(self):
        with unittest.mock.patch.object(oto_runner, "git") as mock_git:
            mock_git.side_effect = lambda *args: {
                ("write-tree",): "expected_tree_hash",
                ("rev-parse", "HEAD"): "head_hash",
                ("diff", "--name-only", "-z"): "modified.swift\0",
                ("ls-files", "--others", "--exclude-standard", "-z"): "",
            }[args]
            with self.assertRaises(oto_runner.RunnerError) as context:
                oto_runner.verify_review_snapshot("expected_tree_hash", "head_hash")
            self.assertIn("Working tree thay đổi sau review", str(context.exception))

    def test_timeout_kill_process_tree(self):
        with self.assertRaises(oto_runner.RunnerError) as context:
            oto_runner.run_command(["sleep", "10"], timeout_seconds=1)
        self.assertIn("vượt timeout", str(context.exception))

    def test_ensure_no_pending_delivery_chan_khi_co_commit_chua_push(self):
        with unittest.mock.patch.object(oto_runner.Path, "exists", return_value=True), \
             unittest.mock.patch.object(oto_runner, "load_json", return_value={"stage": "delivery_pending"}):
            with self.assertRaises(oto_runner.RunnerError) as context:
                oto_runner.ensure_no_pending_delivery()
            self.assertIn("Có commit chưa push", str(context.exception))

    def test_prepare_resume_tu_choi_task_id_khong_khop(self):
        with unittest.mock.patch.object(oto_runner, "load_json", return_value={"task_id": "OTHER-001", "stage": "checking"}):
            with self.assertRaises(oto_runner.RunnerError) as context:
                oto_runner.prepare_resume({"id": "S1-001"})
            self.assertIn("Checkpoint không thuộc task đang resume", str(context.exception))

    def test_prepare_resume_tu_choi_stage_delivery_pending(self):
        with unittest.mock.patch.object(oto_runner, "load_json", return_value={"task_id": "S1-001", "stage": "delivery_pending"}):
            with self.assertRaises(oto_runner.RunnerError) as context:
                oto_runner.prepare_resume({"id": "S1-001"})
            self.assertIn("Không thể resume task ở stage delivery_pending", str(context.exception))

    def test_malformed_model_json_antigravity(self):
        task = {
            "id": "T-1", "title": "Test", "acceptance_criteria": [],
            "allowed_paths": ["Oto/**"], "prompt": "Test",
        }
        config = {
            "agy_path": "/fake/agy", "gemini_model": "test-model",
            "gemini_effort": "high", "agent_timeout_minutes": 1,
        }
        with unittest.mock.patch.object(oto_runner, "run_command") as mock_run:
            mock_run.return_value = oto_runner.CommandResult(0, "not a valid json envelope", "")
            with self.assertRaises(oto_runner.RunnerError) as context:
                oto_runner.call_gemini(task, config, Path("/tmp"), None, 60)
            self.assertIn("Không đọc được kết quả có cấu trúc từ Antigravity", str(context.exception))

    def test_malformed_model_json_codex(self):
        task = {"id": "T-1", "title": "Test", "acceptance_criteria": []}
        config = {"codex_path": "/fake/codex"}
        with unittest.mock.patch.object(oto_runner, "run_command") as mock_run:
            mock_run.return_value = oto_runner.CommandResult(0, "not a valid json output", "")
            with self.assertRaises(oto_runner.RunnerError) as context:
                oto_runner.call_codex_review(task, config, Path("/tmp"), 60)
            self.assertIn("Không đọc được review JSON của Codex", str(context.exception))

    def test_run_command_chuyen_oserror_thanh_runner_error(self):
        with self.assertRaises(oto_runner.RunnerError) as context:
            oto_runner.run_command(["/duong_dan_khong_ton_tai/lenh"], timeout_seconds=10)
        self.assertIn("Không khởi chạy được lệnh", str(context.exception))

    def test_run_command_truyen_input_text_qua_stdin(self):
        result = oto_runner.run_command(["cat"], timeout_seconds=10, input_text="hello stdin")
        self.assertEqual(result.stdout.strip(), "hello stdin")

    def test_repository_changes_giu_ca_hai_phia_khi_rename(self):
        porcelain_output = "R  old_name.swift\0new_name.swift\0 M other.swift\0"
        with unittest.mock.patch.object(oto_runner, "git", return_value=porcelain_output):
            paths = oto_runner.repository_changes()
            self.assertIn("old_name.swift", paths)
            self.assertIn("new_name.swift", paths)
            self.assertIn("other.swift", paths)

    def test_repository_changes_doc_duong_dan_co_khoang_trang(self):
        porcelain_output = "?? path with spaces/file.swift\0"
        with unittest.mock.patch.object(oto_runner, "git", return_value=porcelain_output):
            paths = oto_runner.repository_changes()
            self.assertIn("path with spaces/file.swift", paths)

    def test_run_checks_tu_choi_checks_rong(self):
        task = {"id": "T-1", "checks": []}
        with self.assertRaises(oto_runner.RunnerError) as context:
            oto_runner.run_checks(task, Path("/tmp"), datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")), timedelta(minutes=10))
        self.assertIn("Task phải khai báo ít nhất một check", str(context.exception))

    def test_call_codex_review_chua_uncommitted(self):
        task = {"id": "T-1", "title": "Test", "acceptance_criteria": []}
        config = {"codex_path": "/fake/codex"}
        with unittest.mock.patch.object(oto_runner, "run_command") as mock_run:
            mock_run.return_value = oto_runner.CommandResult(0, '{"approved": true, "summary": "ok", "findings": []}', "")
            oto_runner.call_codex_review(task, config, Path("/tmp"), 60)
            args = mock_run.call_args[0][0]
            self.assertIn("--uncommitted", args)
            self.assertIn("--sandbox", args)
            sandbox_idx = args.index("--sandbox")
            self.assertEqual(args[sandbox_idx + 1], "read-only")
            self.assertNotIn("-", args)

    def test_commit_and_push_dung_reviewed_head(self):
        task = {"id": "T-1", "commit_message": "Test commit"}
        config = {"remote": "origin", "branch": "main"}
        reviewed_head = "head_hash_123"
        reviewed_tree = "tree_hash_456"
        with unittest.mock.patch.object(oto_runner, "ensure_authorized_git_target"), \
             unittest.mock.patch.object(oto_runner, "remaining_timeout_seconds", return_value=60), \
             unittest.mock.patch.object(oto_runner, "git_with_input", return_value="commit_rev_789") as mock_commit_tree, \
             unittest.mock.patch.object(oto_runner, "git", return_value=reviewed_tree) as mock_git, \
             unittest.mock.patch.object(oto_runner, "checkpoint"), \
             unittest.mock.patch.object(oto_runner, "push_revision"):
            rev = oto_runner.commit_and_push(task, config, reviewed_tree, reviewed_head, datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")), timedelta(minutes=10))
            self.assertEqual(rev, "commit_rev_789")
            commit_tree_args = mock_commit_tree.call_args[0]
            self.assertIn("-p", commit_tree_args)
            p_idx = commit_tree_args.index("-p")
            self.assertEqual(commit_tree_args[p_idx + 1], reviewed_head)


if __name__ == "__main__":
    unittest.main()
