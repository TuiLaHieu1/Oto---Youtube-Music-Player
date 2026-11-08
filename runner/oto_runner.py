#!/usr/bin/env python3
"""Điều phối Antigravity triển khai và Codex review cho từng task Oto."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timedelta
import fnmatch
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from typing import Any
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parent.parent
RUNNER_DIR = ROOT / "runner"
STATE_DIR = ROOT / ".oto-runner"
TIMEZONE = ZoneInfo("Asia/Ho_Chi_Minh")
SECRET_ENVIRONMENT_KEYS = {
    "OPENAI_API_KEY",
    "CODEX_API_KEY",
    "OPENAI_BASE_URL",
    "GEMINI_API_KEY",
    "GOOGLE_API_KEY",
    "GOOGLE_APPLICATION_CREDENTIALS",
    "GOOGLE_GENAI_USE_VERTEXAI",
}
SAFE_ENVIRONMENT_KEYS = {
    "PATH",
    "HOME",
    "USER",
    "LOGNAME",
    "SHELL",
    "TMPDIR",
    "LANG",
    "LC_ALL",
    "TERM",
    "DEVELOPER_DIR",
    "SDKROOT",
}
AUTHORIZED_REMOTE_URLS = {
    "https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player",
    "git@github.com:TuiLaHieu1/Oto---Youtube-Music-Player",
}
ACTIVE_PROCESS_GROUP: int | None = None


class RunnerError(RuntimeError):
    """Lỗi đã được chuẩn hóa để ghi handoff ngắn gọn."""


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RunnerError(f"Không đọc được {path.relative_to(ROOT)}: {error}") from error
    if not isinstance(value, dict):
        raise RunnerError(f"{path.relative_to(ROOT)} phải chứa JSON object.")
    return value


def scrubbed_environment() -> dict[str, str]:
    environment = {
        key: value
        for key, value in os.environ.items()
        if key in SAFE_ENVIRONMENT_KEYS and key not in SECRET_ENVIRONMENT_KEYS
    }
    environment["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
    return environment


def terminate_process_group(process_group: int) -> None:
    try:
        os.killpg(process_group, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        return
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            os.killpg(process_group, 0)
        except (ProcessLookupError, PermissionError):
            return
        time.sleep(0.1)
    try:
        os.killpg(process_group, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def run_command(
    arguments: list[str],
    *,
    timeout_seconds: int,
    input_text: str | None = None,
    cwd: Path = ROOT,
) -> CommandResult:
    global ACTIVE_PROCESS_GROUP
    try:
        process = subprocess.Popen(
            arguments,
            text=True,
            stdin=subprocess.PIPE if input_text is not None else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd,
            env=scrubbed_environment(),
            start_new_session=True,
        )
        ACTIVE_PROCESS_GROUP = process.pid
        stdout, stderr = process.communicate(input=input_text, timeout=timeout_seconds)
    except OSError as error:
        raise RunnerError(f"Không khởi chạy được lệnh {Path(arguments[0]).name}: {error}") from error
    except subprocess.TimeoutExpired as error:
        terminate_process_group(process.pid)
        process.wait()
        raise RunnerError(f"Lệnh {Path(arguments[0]).name} vượt timeout.") from error
    finally:
        ACTIVE_PROCESS_GROUP = None
    return CommandResult(process.returncode, stdout, stderr)


def git(*arguments: str, timeout_seconds: int = 120) -> str:
    result = run_command(
        ["git", *arguments], timeout_seconds=timeout_seconds, cwd=ROOT
    )
    if result.returncode != 0:
        message = last_safe_line(result.stderr) or "Git trả lỗi không xác định."
        raise RunnerError(f"Git {' '.join(arguments[:2])}: {message}")
    return result.stdout.strip()


def git_with_input(*arguments: str, input_text: str, timeout_seconds: int = 120) -> str:
    result = run_command(
        ["git", *arguments], timeout_seconds=timeout_seconds,
        input_text=input_text, cwd=ROOT,
    )
    if result.returncode != 0:
        message = last_safe_line(result.stderr) or "Git trả lỗi không xác định."
        raise RunnerError(f"Git {' '.join(arguments[:2])}: {message}")
    return result.stdout.strip()


def last_safe_line(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return ""
    return redact_text(lines[-1])[:500]


def redact_text(text: str) -> str:
    redacted = text
    patterns = (
        r"(?i)bearer\s+[A-Za-z0-9._~+/-]+=*",
        r"(?i)(authorization|cookie|token|api[_-]?key|password|secret)\s*[:=]\s*[^\s,;]+",
        r'(?i)"[^"\\]*(token|cookie|password|secret|api[_-]?key)[^"\\]*"\s*:\s*"[^"\\]*"',
        r"https://[^/@\s:]+:[^/@\s]+@",
    )
    for pattern in patterns:
        redacted = re.sub(pattern, "REDACTED", redacted)
    return redacted


def sanitized_json(value: Any) -> Any:
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, list):
        return [sanitized_json(item) for item in value]
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, item in value.items():
            string_key = str(key)
            if re.search(r"(?i)(token|cookie|password|secret|api[_-]?key)", string_key):
                result[string_key] = "REDACTED"
            else:
                result[string_key] = sanitized_json(item)
        return result
    return value


def compute_next_cutoff(now: datetime, stop_hour: int) -> datetime:
    local_now = now.astimezone(TIMEZONE)
    cutoff = local_now.replace(hour=stop_hour, minute=0, second=0, microsecond=0)
    if local_now >= cutoff:
        cutoff += timedelta(days=1)
    return cutoff


def parse_cutoff(value: str | None, stop_hour: int) -> datetime:
    if value is None:
        return compute_next_cutoff(datetime.now(TIMEZONE), stop_hour)
    try:
        cutoff = datetime.fromisoformat(value)
    except ValueError as error:
        raise RunnerError("Cutoff phải là ISO-8601, ví dụ 2026-11-09T05:00:00+07:00.") from error
    if cutoff.tzinfo is None:
        raise RunnerError("Cutoff phải có múi giờ.")
    local_cutoff = cutoff.astimezone(TIMEZONE)
    if (
        local_cutoff.hour != stop_hour
        or local_cutoff.minute != 0
        or local_cutoff.second != 0
        or local_cutoff.microsecond != 0
    ):
        raise RunnerError(f"Cutoff bắt buộc là {stop_hour:02d}:00:00 giờ Việt Nam.")
    return local_cutoff


def remaining_timeout_seconds(
    cutoff: datetime,
    margin: timedelta,
    requested_seconds: int,
) -> int:
    available = int((cutoff - margin - datetime.now(TIMEZONE)).total_seconds())
    if available <= 0:
        raise RunnerError("Đã đến vùng dừng trước cutoff.")
    return min(requested_seconds, available)


def matches_allowed_path(path: str, patterns: list[str]) -> bool:
    normalized = Path(path).as_posix()
    if normalized.startswith("./"):
        normalized = normalized[2:]
    return any(
        fnmatch.fnmatchcase(normalized, pattern)
        or (pattern.endswith("/**") and normalized == pattern[:-3])
        for pattern in patterns
    )


def repository_changes() -> list[str]:
    output = git("status", "--porcelain=v1", "-z", "--untracked-files=all")
    raw_entries = output.split("\0") if output else []
    paths: list[str] = []
    index = 0
    while index < len(raw_entries):
        entry = raw_entries[index]
        if not entry:
            index += 1
            continue
        status = entry[:2]
        path = entry[3:] if len(entry) > 3 else ""
        if path:
            paths.append(path)
        if len(status) == 2 and (status[0] in "RC" or status[1] in "RC"):
            index += 1
            if index < len(raw_entries) and raw_entries[index]:
                paths.append(raw_entries[index])
        index += 1
    return sorted(set(paths))


def ensure_isolated_repository() -> None:
    root = Path(git("rev-parse", "--show-toplevel")).resolve()
    if root != ROOT.resolve():
        raise RunnerError(f"Git root phải là {ROOT}, hiện tại là {root}.")


def normalize_remote_url(value: str) -> str:
    normalized = value.strip().rstrip("/")
    if normalized.endswith(".git"):
        normalized = normalized[:-4]
    return normalized


def ensure_authorized_git_target(config: dict[str, Any]) -> None:
    ensure_isolated_repository()
    branch = git("branch", "--show-current")
    if branch != config["branch"]:
        raise RunnerError(
            f"Nhánh hiện tại phải là {config['branch']}, hiện tại là {branch or 'detached HEAD'}."
        )
    fetch_urls = git("remote", "get-url", "--all", config["remote"]).splitlines()
    push_urls = git("remote", "get-url", "--push", "--all", config["remote"]).splitlines()
    if len(fetch_urls) != 1 or len(push_urls) != 1:
        raise RunnerError("Remote phải có đúng một fetch URL và một push URL.")
    for kind, value in (("fetch", fetch_urls[0]), ("push", push_urls[0])):
        remote_url = normalize_remote_url(value)
        if remote_url not in AUTHORIZED_REMOTE_URLS:
            raise RunnerError(f"Remote {kind} không được ủy quyền: {remote_url}")


def ensure_head_exists() -> None:
    result = run_command(
        ["git", "rev-parse", "--verify", "HEAD"], timeout_seconds=30
    )
    if result.returncode != 0:
        raise RunnerError("Runner cần ít nhất một commit nền trước khi chạy task.")


def ensure_clean_repository() -> None:
    changes = repository_changes()
    if changes:
        shown = ", ".join(changes[:8])
        raise RunnerError(f"Working tree chưa sạch: {shown}")


def ensure_no_pending_delivery() -> None:
    path = STATE_DIR / "checkpoint.json"
    if not path.exists():
        return
    state = load_json(path)
    if state.get("stage") == "delivery_pending":
        raise RunnerError("Có commit chưa push; chạy `Scripts/oto-runner retry-push` trước.")


def validate_scope(task: dict[str, Any]) -> list[str]:
    changed = repository_changes()
    patterns = task.get("allowed_paths", [])
    unexpected = [path for path in changed if not matches_allowed_path(path, patterns)]
    if unexpected:
        raise RunnerError("Task sửa ngoài scope: " + ", ".join(unexpected))
    if not changed:
        raise RunnerError("Task không tạo thay đổi nào để review.")
    return changed


def task_by_id(backlog: dict[str, Any], task_id: str) -> dict[str, Any]:
    tasks = backlog.get("tasks")
    if not isinstance(tasks, list):
        raise RunnerError("runner/backlog.json thiếu mảng tasks.")
    for task in tasks:
        if isinstance(task, dict) and task.get("id") == task_id:
            return task
    raise RunnerError(f"Không tìm thấy task {task_id}.")


def task_prompt(task: dict[str, Any], review: dict[str, Any] | None = None) -> str:
    criteria = "\n".join(f"- {item}" for item in task["acceptance_criteria"])
    references = "\n".join(f"- {item}" for item in task.get("references", []))
    scope = "\n".join(f"- {item}" for item in task["allowed_paths"])
    review_section = ""
    if review is not None:
        review_section = (
            "\nĐây là review JSON của Codex. Đánh giá từng finding, sửa finding hợp lệ, "
            "và giải thích finding bị bác trong kết quả cuối:\n"
            + json.dumps(review, ensure_ascii=False, indent=2)
        )
    return f"""
Bạn là Gemini triển khai chính cho Oto, task {task['id']}: {task['title']}.

Đọc AGENTS.md và các tài liệu tham chiếu sau bằng công cụ đọc file:
{references}

Mục tiêu:
{task['prompt']}

Acceptance criteria:
{criteria}

Chỉ được sửa các path thuộc scope:
{scope}

Không commit, push, chạy UI test, cài lên thiết bị thật, thêm dependency bên thứ ba,
hoặc gửi request thay đổi tài khoản. Runner quản lý Git và Codex review.
Chạy kiểm tra phù hợp nếu chúng tồn tại. Nếu permission hoặc thông tin còn thiếu,
trả status blocked; không dùng cờ bypass quyền. Chú thích cần thiết bằng tiếng Việt đơn giản.
{review_section}
""".strip()


def call_gemini(
    task: dict[str, Any],
    config: dict[str, Any],
    run_dir: Path,
    review: dict[str, Any] | None,
    timeout_seconds: int,
) -> dict[str, Any]:
    prompt = task_prompt(task, review)
    result = run_command(
        [
            config["agy_path"],
            "--model", config["gemini_model"],
            "--effort", config["gemini_effort"],
            "--mode", "auto",
            "--sandbox",
            "--disable-slash-commands",
            "--output-format", "json",
            "--json-schema", str(RUNNER_DIR / "schemas/implement-result.schema.json"),
            "--print-timeout", f"{config['agent_timeout_minutes']}m",
            "-p", prompt,
        ],
        timeout_seconds=timeout_seconds,
    )
    if result.returncode != 0:
        raise RunnerError("Antigravity thất bại: " + (last_safe_line(result.stderr) or "không có chi tiết"))
    try:
        envelope = json.loads(result.stdout)
        if envelope.get("status") != "SUCCESS":
            raise RunnerError(f"Antigravity kết thúc với trạng thái {envelope.get('status')}.")
        response = envelope.get("response")
        parsed = json.loads(response) if isinstance(response, str) else response
        if not isinstance(parsed, dict):
            raise ValueError("response không phải object")
    except (json.JSONDecodeError, ValueError) as error:
        raise RunnerError("Không đọc được kết quả có cấu trúc từ Antigravity.") from error
    (run_dir / "gemini-status.json").write_text(
        json.dumps(
            {
                "status": parsed.get("status"),
                "summary": redact_text(str(parsed.get("summary", "")))[:1000],
                "check_count": len(parsed.get("checks_run", [])),
                "blocker_count": len(parsed.get("blockers", [])),
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    if parsed.get("status") != "completed":
        blockers = [redact_text(str(item)) for item in parsed.get("blockers", [])]
        raise RunnerError("Gemini bị chặn: " + "; ".join(blockers))
    return parsed


def run_checks(
    task: dict[str, Any],
    run_dir: Path,
    cutoff: datetime,
    margin: timedelta,
) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    checks = task.get("checks", [])
    if not isinstance(checks, list) or not checks:
        raise RunnerError("Task phải khai báo ít nhất một check dạng command array.")
    for index, command in enumerate(checks, start=1):
        if not isinstance(command, list) or not command or not all(isinstance(item, str) for item in command):
            raise RunnerError("Mỗi check phải là mảng chuỗi, không dùng shell string.")
        result = run_command(
            command,
            timeout_seconds=remaining_timeout_seconds(cutoff, margin, 20 * 60),
        )
        record: dict[str, Any] = {
            "command": command,
            "returncode": result.returncode,
        }
        if result.returncode != 0:
            record["error"] = last_safe_line(result.stderr) or last_safe_line(result.stdout)
        results.append(record)
        (run_dir / f"check-{index}.json").write_text(
            json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        if result.returncode != 0:
            raise RunnerError("Check thất bại: " + " ".join(command))
    return results


def call_codex_review(
    task: dict[str, Any],
    config: dict[str, Any],
    run_dir: Path,
    timeout_seconds: int,
) -> dict[str, Any]:
    criteria = "\n".join(f"- {item}" for item in task["acceptance_criteria"])
    prompt = f"""
Review các thay đổi uncommitted cho task {task['id']}: {task['title']}.
Đọc AGENTS.md và tài liệu tham chiếu của task. Chỉ review, không sửa code.
Tập trung correctness, security, concurrency, lifecycle, scope và regression.
Không báo style thuần túy. Viết findings bằng tiếng Việt đơn giản.
Chỉ approved=true khi không còn finding P0-P3 có thể hành động.

Acceptance criteria:
{criteria}
""".strip()
    result = run_command(
        [
            config["codex_path"], "exec",
            "--sandbox", "read-only",
            "review",
            "--uncommitted",
            "--ephemeral",
            "--output-schema", str(RUNNER_DIR / "schemas/review-result.schema.json"),
        ],
        input_text=prompt,
        timeout_seconds=timeout_seconds,
    )
    if result.returncode != 0:
        raise RunnerError("Codex review thất bại: " + (last_safe_line(result.stderr) or "không có chi tiết"))
    try:
        review = sanitized_json(json.loads(result.stdout))
    except json.JSONDecodeError as error:
        raise RunnerError("Không đọc được review JSON của Codex.") from error
    return review


def review_artifact(review: dict[str, Any]) -> dict[str, Any]:
    """Giữ kết luận cần thiết, không lưu evidence có thể chứa dữ liệu nhạy cảm."""
    findings: list[dict[str, Any]] = []
    for finding in review.get("findings", []):
        if not isinstance(finding, dict):
            continue
        findings.append({
            key: sanitized_json(finding.get(key))
            for key in ("severity", "path", "line", "summary")
            if key in finding
        })
    return {
        "approved": review.get("approved") is True,
        "summary": redact_text(str(review.get("summary", "")))[:1000],
        "findings": findings,
    }


def checkpoint(task_id: str, stage: str, **values: Any) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = STATE_DIR / "checkpoint.json"
    payload = {
        "task_id": task_id,
        "stage": stage,
        "updated_at": datetime.now(TIMEZONE).isoformat(),
        **sanitized_json(values),
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_handoff(reason: str, task_id: str | None, details: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    status = ""
    try:
        status = git("status", "--short")
    except RunnerError:
        status = "Không đọc được Git status."
    content = f"""# Handoff Oto runner

- Thời gian: {datetime.now(TIMEZONE).isoformat()}
- Lý do dừng: {reason}
- Task: {task_id or 'chưa chọn'}
- Chi tiết: {redact_text(details)}

## Git status

```text
{status or 'Sạch'}
```

## Tiếp tục

Đọc `.oto-runner/checkpoint.json` và xử lý blocker trước khi chạy lại. Runner không tự
coi task dang dở là hoàn tất và không tự đổi sang API trả phí.
"""
    (STATE_DIR / "handoff.md").write_text(content, encoding="utf-8")


def stage_review_snapshot(task: dict[str, Any]) -> tuple[list[str], str, str]:
    changed = validate_scope(task)
    git("add", "--", *changed)
    unstaged = git("diff", "--name-only", "-z")
    untracked_raw = git("ls-files", "--others", "--exclude-standard", "-z")
    untracked = [p for p in untracked_raw.split("\0") if p and p not in changed]
    if unstaged or untracked:
        raise RunnerError("Không tạo được snapshot sạch để review.")
    return changed, git("write-tree"), git("rev-parse", "HEAD")


def verify_review_snapshot(reviewed_tree: str, reviewed_head: str) -> None:
    if git("write-tree") != reviewed_tree or git("rev-parse", "HEAD") != reviewed_head:
        raise RunnerError("Snapshot đã thay đổi trong lúc review; không được commit.")
    unstaged = git("diff", "--name-only", "-z")
    untracked = git("ls-files", "--others", "--exclude-standard", "-z")
    if unstaged or untracked:
        raise RunnerError("Working tree thay đổi sau review; không được commit.")


def staged_paths() -> list[str]:
    output = git("diff", "--cached", "--name-only", "-z", "--diff-filter=ACDMRTUXB")
    return sorted(path for path in output.split("\0") if path)


def unstage_paths(paths: list[str]) -> None:
    git("restore", "--staged", "--", *paths)


def commit_and_push(
    task: dict[str, Any],
    config: dict[str, Any],
    reviewed_tree: str,
    reviewed_head: str,
    cutoff: datetime,
    margin: timedelta,
) -> str:
    ensure_authorized_git_target(config)
    remaining_timeout_seconds(cutoff, margin, 1)
    revision = git_with_input(
        "commit-tree", reviewed_tree, "-p", reviewed_head,
        input_text=task["commit_message"] + "\n",
        timeout_seconds=remaining_timeout_seconds(cutoff, margin, 180),
    )
    git("update-ref", f"refs/heads/{config['branch']}", revision, reviewed_head)
    if git("rev-parse", "HEAD^{tree}") != reviewed_tree:
        raise RunnerError("Commit không trùng tree đã review; không được push.")
    checkpoint(task["id"], "delivery_pending", revision=revision)
    push_revision(config, revision, cutoff, margin)
    return revision


def push_revision(
    config: dict[str, Any],
    revision: str,
    cutoff: datetime,
    margin: timedelta,
) -> None:
    ensure_authorized_git_target(config)
    if git("rev-parse", "HEAD") != revision:
        raise RunnerError("HEAD không còn trùng commit chờ push.")
    ensure_clean_repository()
    git(
        "push",
        config["remote"],
        f"{revision}:refs/heads/{config['branch']}",
        timeout_seconds=remaining_timeout_seconds(cutoff, margin, 10 * 60),
    )
    remote_revision = git(
        "ls-remote",
        config["remote"],
        f"refs/heads/{config['branch']}",
        timeout_seconds=remaining_timeout_seconds(cutoff, margin, 120),
    )
    if not remote_revision.startswith(revision + "\t"):
        raise RunnerError("Không xác minh được revision trên remote sau push.")


def doctor(config: dict[str, Any]) -> int:
    problems: list[str] = []
    try:
        ensure_authorized_git_target(config)
        print(f"PASS Git root: {ROOT}")
    except RunnerError as error:
        problems.append(str(error))
    for label, path in (("Antigravity", config["agy_path"]), ("Codex", config["codex_path"])):
        if Path(path).is_file() and os.access(path, os.X_OK):
            print(f"PASS {label}: {path}")
        else:
            problems.append(f"Không tìm thấy executable {label}: {path}")
    try:
        remote_url = git("remote", "get-url", config["remote"])
        print(f"PASS remote {config['remote']}: {remote_url}")
    except RunnerError as error:
        problems.append(str(error))
    if repository_changes():
        print("INFO Working tree đang có thay đổi; lệnh run sẽ từ chối cho đến khi sạch.")
    if problems:
        for problem in problems:
            print("FAIL", problem)
        return 1
    print("Doctor hoàn tất. Không gọi model, không sửa code, không push.")
    return 0


def list_tasks(backlog: dict[str, Any]) -> int:
    for task in backlog.get("tasks", []):
        print(f"{task.get('id')}\t{task.get('status')}\t{task.get('title')}")
    return 0


def prepare_resume(task: dict[str, Any]) -> None:
    state = load_json(STATE_DIR / "checkpoint.json")
    if state.get("task_id") != task.get("id"):
        raise RunnerError("Checkpoint không thuộc task đang resume.")
    if state.get("stage") in {"done", "delivery_pending"}:
        raise RunnerError(f"Không thể resume task ở stage {state.get('stage')}.")
    changed = repository_changes()
    if changed:
        validate_scope(task)
        staged = staged_paths()
        if staged:
            unstage_paths(staged)


def execute_task(
    task: dict[str, Any],
    config: dict[str, Any],
    cutoff: datetime,
    *,
    resume: bool,
) -> str:
    if task.get("status") != "READY":
        raise RunnerError(f"Task {task.get('id')} phải ở trạng thái READY.")
    ensure_authorized_git_target(config)
    ensure_head_exists()
    ensure_no_pending_delivery()
    if resume:
        prepare_resume(task)
    else:
        ensure_clean_repository()
    margin = timedelta(minutes=config["shutdown_margin_minutes"])
    if datetime.now(TIMEZONE) >= cutoff - margin:
        raise RunnerError("Không đủ thời gian trước cutoff để nhận task mới.")

    run_dir = STATE_DIR / "runs" / f"{datetime.now(TIMEZONE).strftime('%Y%m%d-%H%M%S')}-{task['id']}"
    run_dir.mkdir(parents=True, exist_ok=False)
    checkpoint(task["id"], "implementing", cutoff=cutoff.isoformat(), run_dir=str(run_dir))
    review: dict[str, Any] | None = None
    for round_index in range(config["max_repair_rounds"] + 1):
        if datetime.now(TIMEZONE) >= cutoff - margin:
            raise RunnerError("Đã đến vùng dừng trước cutoff; task được checkpoint.")
        agent_timeout = remaining_timeout_seconds(
            cutoff,
            margin,
            config["agent_timeout_minutes"] * 60 + 30,
        )
        call_gemini(task, config, run_dir, review, agent_timeout)
        validate_scope(task)
        checkpoint(task["id"], "checking", round=round_index)
        run_checks(task, run_dir, cutoff, margin)
        changed, reviewed_tree, reviewed_head = stage_review_snapshot(task)
        checkpoint(task["id"], "reviewing", round=round_index)
        review_timeout = remaining_timeout_seconds(
            cutoff,
            margin,
            config["agent_timeout_minutes"] * 60 + 30,
        )
        try:
            review = call_codex_review(task, config, run_dir, review_timeout)
        except RunnerError:
            unstage_paths(changed)
            raise
        safe_review = review_artifact(review)
        (run_dir / f"review-{round_index}.json").write_text(
            json.dumps(safe_review, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        if review.get("approved") is True and not review.get("findings"):
            verify_review_snapshot(reviewed_tree, reviewed_head)
            checkpoint(
                task["id"],
                "committing",
                changed=changed,
                reviewed_tree=reviewed_tree,
            )
            revision = commit_and_push(task, config, reviewed_tree, reviewed_head, cutoff, margin)
            checkpoint(task["id"], "done", revision=revision)
            write_handoff("Hoàn tất task", task["id"], f"Đã push revision {revision}.")
            return revision
        if round_index >= config["max_repair_rounds"]:
            raise RunnerError("Hết số vòng sửa nhưng Codex chưa approve.")
        unstage_paths(changed)
        checkpoint(task["id"], "repairing", round=round_index, review=safe_review)
    raise RunnerError("Runner rơi vào trạng thái không hợp lệ.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("doctor", help="Kiểm tra môi trường, không gọi model")
    subparsers.add_parser("list", help="Liệt kê task")
    run_parser = subparsers.add_parser("run", help="Chạy một task READY")
    run_parser.add_argument("task_id")
    run_parser.add_argument("--cutoff", help="ISO-8601 có múi giờ; mặc định 05:00 kế tiếp")
    run_parser.add_argument(
        "--resume",
        action="store_true",
        help="Tiếp tục task từ checkpoint và thay đổi đúng scope",
    )
    retry_parser = subparsers.add_parser("retry-push", help="Push lại commit đã tạo nhưng giao thất bại")
    retry_parser.add_argument("--cutoff", help="ISO-8601 có múi giờ; mặc định 05:00 kế tiếp")
    arguments = parser.parse_args()

    config = load_json(RUNNER_DIR / "config.json")
    backlog = load_json(RUNNER_DIR / "backlog.json")
    active_task: str | None = None

    def handle_signal(signum: int, _frame: Any) -> None:
        if ACTIVE_PROCESS_GROUP is not None:
            terminate_process_group(ACTIVE_PROCESS_GROUP)
        write_handoff(f"Nhận signal {signum}", active_task, "Tiến trình bị ngắt có kiểm soát.")
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    try:
        if arguments.command == "doctor":
            return doctor(config)
        if arguments.command == "list":
            return list_tasks(backlog)
        if arguments.command == "retry-push":
            state = load_json(STATE_DIR / "checkpoint.json")
            if state.get("stage") != "delivery_pending" or not isinstance(state.get("revision"), str):
                raise RunnerError("Không có commit delivery_pending để push lại.")
            active_task = str(state.get("task_id"))
            cutoff = parse_cutoff(arguments.cutoff, config["stop_hour"])
            margin = timedelta(minutes=config["shutdown_margin_minutes"])
            push_revision(config, state["revision"], cutoff, margin)
            checkpoint(active_task, "done", revision=state["revision"])
            write_handoff("Đã giao commit chờ push", active_task, f"Đã push {state['revision']}.")
            print(f"DONE {active_task}: {state['revision']}")
            return 0
        active_task = arguments.task_id
        task = task_by_id(backlog, active_task)
        cutoff = parse_cutoff(arguments.cutoff, config["stop_hour"])
        print(f"Task {active_task}; cutoff {cutoff.isoformat()}")
        revision = execute_task(task, config, cutoff, resume=arguments.resume)
        print(f"DONE {active_task}: {revision}")
        return 0
    except RunnerError as error:
        write_handoff("Runner dừng", active_task, str(error))
        print(f"DỪNG: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
