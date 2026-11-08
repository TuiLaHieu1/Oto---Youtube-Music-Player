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


class Clock:
    def now(self) -> datetime:
        return datetime.now(TIMEZONE)

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)


DEFAULT_CLOCK = Clock()


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
        try:
            rel = path.relative_to(ROOT)
        except ValueError:
            rel = path
        raise RunnerError(f"Không đọc được {rel}: {error}") from error
    if not isinstance(value, dict):
        try:
            rel = path.relative_to(ROOT)
        except ValueError:
            rel = path
        raise RunnerError(f"{rel} phải chứa JSON object.")
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
    cwd: Path | None = None,
) -> CommandResult:
    target_cwd = cwd if cwd is not None else ROOT
    global ACTIVE_PROCESS_GROUP
    try:
        process = subprocess.Popen(
            arguments,
            text=True,
            stdin=subprocess.PIPE if input_text is not None else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=target_cwd,
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


def git(*arguments: str, timeout_seconds: int = 120, cwd: Path | None = None, strip_output: bool = True) -> str:
    result = run_command(
        ["git", *arguments], timeout_seconds=timeout_seconds, cwd=cwd
    )
    if result.returncode != 0:
        message = last_safe_line(result.stderr) or "Git trả lỗi không xác định."
        raise RunnerError(f"Git {' '.join(arguments[:2])}: {message}")
    return result.stdout.strip() if strip_output else result.stdout


def git_with_input(*arguments: str, input_text: str, timeout_seconds: int = 120, cwd: Path | None = None) -> str:
    result = run_command(
        ["git", *arguments], timeout_seconds=timeout_seconds,
        input_text=input_text, cwd=cwd,
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


def parse_cutoff(value: str | None, stop_hour: int, clock: Clock | None = None) -> datetime:
    ref_clock = clock or DEFAULT_CLOCK
    if value is None:
        return compute_next_cutoff(ref_clock.now(), stop_hour)
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
    clock: Clock | None = None,
) -> int:
    ref_clock = clock or DEFAULT_CLOCK
    available = int((cutoff - margin - ref_clock.now()).total_seconds())
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


def repository_changes(cwd: Path | None = None) -> list[str]:
    kwargs = {"cwd": cwd} if cwd is not None and cwd != ROOT else {}
    output = git("status", "--porcelain=v1", "-z", "--untracked-files=all", strip_output=False, **kwargs)
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


def validate_scope(task: dict[str, Any], cwd: Path | None = None) -> list[str]:
    changed = repository_changes(cwd=cwd)
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
    cwd: Path | None = None,
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
        cwd=cwd,
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
    cwd: Path | None = None,
    clock: Clock | None = None,
) -> list[dict[str, Any]]:
    ref_clock = clock or DEFAULT_CLOCK
    results: list[dict[str, Any]] = []
    checks = task.get("checks", [])
    if not isinstance(checks, list) or not checks:
        raise RunnerError("Task phải khai báo ít nhất một check dạng command array.")
    for index, command in enumerate(checks, start=1):
        if not isinstance(command, list) or not command or not all(isinstance(item, str) for item in command):
            raise RunnerError("Mỗi check phải là mảng chuỗi, không dùng shell string.")
        result = run_command(
            command,
            timeout_seconds=remaining_timeout_seconds(cutoff, margin, 20 * 60, clock=ref_clock),
            cwd=cwd,
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


def classify_codex_failure(result: CommandResult) -> str:
    """Phân loại lỗi của Codex: quota, auth, network/transient, tool/internal, review_finding."""
    combined = f"{result.stdout}\n{result.stderr}".lower()
    if any(keyword in combined for keyword in (
        "insufficient_quota", "quota", "rate limit", "exceeded your current quota",
        "429", "out of credits", "resource_exhausted", "usage limit"
    )):
        return "quota"
    if any(keyword in combined for keyword in (
        "unauthorized", "authentication failed", "login required", "401", "invalid api key",
        "permission denied", "forbidden", "403"
    )):
        return "auth"
    if any(keyword in combined for keyword in (
        "connection failed", "timeout", "reconnecting", "network error", "dns", "503", "502",
        "temporary failure", "connection reset", "could not resolve"
    )):
        return "network/transient"
    if result.returncode != 0:
        return "tool/internal"
    return "review_finding"


def call_codex_review(
    task: dict[str, Any],
    config: dict[str, Any],
    run_dir: Path,
    timeout_seconds: int,
    cwd: Path | None = None,
) -> tuple[dict[str, Any] | None, str | None]:
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
        cwd=cwd,
    )
    if result.returncode != 0:
        err_class = classify_codex_failure(result)
        if err_class in ("quota", "auth", "network/transient"):
            return None, err_class
        raise RunnerError(f"Codex review thất bại ({err_class}): " + (last_safe_line(result.stderr) or "không có chi tiết"))
    try:
        review = sanitized_json(json.loads(result.stdout))
        return review, None
    except json.JSONDecodeError as error:
        raise RunnerError("Không đọc được review JSON của Codex.") from error


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


def checkpoint(task_id: str, stage: str, clock: Clock | None = None, **values: Any) -> None:
    ref_clock = clock or DEFAULT_CLOCK
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = STATE_DIR / "checkpoint.json"
    payload = {
        "task_id": task_id,
        "stage": stage,
        "updated_at": ref_clock.now().isoformat(),
        **sanitized_json(values),
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def validate_task_id(task_id: str) -> str:
    """Xác thực task_id hợp lệ, ngăn chặn path traversal."""
    if not isinstance(task_id, str) or not task_id.strip():
        raise RunnerError("Task ID không được để trống.")
    cleaned = task_id.strip()
    if "/" in cleaned or "\\" in cleaned or ".." in cleaned or cleaned.startswith("."):
        raise RunnerError(f"Task ID không hợp lệ: {task_id}")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", cleaned):
        raise RunnerError(f"Task ID chứa ký tự không hợp lệ: {task_id}")
    return cleaned


def task_state_dir(task_id: str) -> Path:
    valid_id = validate_task_id(task_id)
    base = (STATE_DIR / "tasks").resolve()
    target = (base / valid_id).resolve()
    if target.parent != base:
        raise RunnerError(f"Đường dẫn trạng thái task không hợp lệ: {task_id}")
    return target


def task_checkpoint(task_id: str, stage: str, clock: Clock | None = None, **values: Any) -> dict[str, Any]:
    ref_clock = clock or DEFAULT_CLOCK
    task_dir = task_state_dir(task_id)
    task_dir.mkdir(parents=True, exist_ok=True)
    path = task_dir / "checkpoint.json"
    existing: dict[str, Any] = {}
    if path.exists():
        try:
            existing = load_json(path)
        except RunnerError:
            existing = {}
    payload = {
        **existing,
        "task_id": task_id,
        "stage": stage,
        "updated_at": ref_clock.now().isoformat(),
        **sanitized_json(values),
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checkpoint(task_id, stage, clock=ref_clock, **values)
    return payload


def load_task_checkpoint(task_id: str) -> dict[str, Any] | None:
    try:
        path = task_state_dir(task_id) / "checkpoint.json"
    except RunnerError:
        return None
    if not path.exists():
        return None
    try:
        return load_json(path)
    except RunnerError:
        return None


def task_worktree_dir(task_id: str) -> Path:
    valid_id = validate_task_id(task_id)
    base = (STATE_DIR / "worktrees").resolve()
    target = (base / valid_id).resolve()
    if target.parent != base:
        raise RunnerError(f"Đường dẫn worktree task không hợp lệ: {task_id}")
    return target


def write_handoff(
    reason: str,
    task_id: str | None,
    details: str,
    clock: Clock | None = None,
    worktree: Path | None = None,
) -> None:
    ref_clock = clock or DEFAULT_CLOCK
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    status = ""
    try:
        status = git("status", "--short")
    except RunnerError:
        status = "Không đọc được Git status."

    wt_path = worktree
    if wt_path is None and task_id:
        try:
            candidate = task_worktree_dir(task_id)
            if candidate.exists():
                wt_path = candidate
        except RunnerError:
            pass

    wt_section = ""
    if wt_path is not None and wt_path.exists():
        try:
            wt_status = git("status", "--short", cwd=wt_path)
        except RunnerError:
            wt_status = "Không đọc được Git status của worktree."
        wt_section = f"""

## Git status worktree ({wt_path})

```text
{wt_status or 'Sạch'}
```"""

    content = f"""# Handoff Oto runner

- Thời gian: {ref_clock.now().isoformat()}
- Lý do dừng: {reason}
- Task: {task_id or 'chưa chọn'}
- Chi tiết: {redact_text(details)}

## Git status

```text
{status or 'Sạch'}
```{wt_section}

## Tiếp tục

Đọc `.oto-runner/checkpoint.json` và xử lý blocker trước khi chạy lại. Runner không tự
coi task dang dở là hoàn tất và không tự đổi sang API trả phí.
"""
    (STATE_DIR / "handoff.md").write_text(content, encoding="utf-8")


def create_task_worktree(task_id: str, base_revision: str) -> Path:
    wt_dir = task_worktree_dir(task_id)
    if wt_dir.exists():
        remove_task_worktree(task_id)
    wt_dir.parent.mkdir(parents=True, exist_ok=True)
    git("worktree", "add", "--detach", str(wt_dir.resolve()), base_revision)
    return wt_dir


def remove_task_worktree(task_id: str) -> None:
    wt_dir = task_worktree_dir(task_id)
    if wt_dir.exists():
        try:
            git("worktree", "remove", "--force", str(wt_dir.resolve()))
        except RunnerError:
            pass
        git("worktree", "prune")
    if wt_dir.exists():
        import shutil
        shutil.rmtree(wt_dir, ignore_errors=True)
        git("worktree", "prune")


def reset_task(task_id: str | None = None, *, reset_all: bool = False) -> int:
    """Xóa checkpoint và worktree của task để cho phép chạy lại từ đầu."""
    import shutil
    if reset_all:
        tasks_dir = STATE_DIR / "tasks"
        if tasks_dir.exists():
            for p in list(tasks_dir.iterdir()):
                if p.is_dir():
                    remove_task_worktree(p.name)
            shutil.rmtree(tasks_dir, ignore_errors=True)
        worktrees_dir = STATE_DIR / "worktrees"
        if worktrees_dir.exists():
            shutil.rmtree(worktrees_dir, ignore_errors=True)
            try:
                git("worktree", "prune")
            except RunnerError:
                pass
        global_cp = STATE_DIR / "checkpoint.json"
        if global_cp.exists():
            global_cp.unlink()
        print("RESET: Đã xóa toàn bộ checkpoint và worktree của tất cả task.")
        return 0

    if not task_id:
        raise RunnerError("Cần cung cấp task_id hoặc cờ --all để reset.")
    validate_task_id(task_id)
    remove_task_worktree(task_id)
    task_dir = task_state_dir(task_id)
    if task_dir.exists():
        shutil.rmtree(task_dir, ignore_errors=True)
    global_cp = STATE_DIR / "checkpoint.json"
    if global_cp.exists():
        try:
            g_state = load_json(global_cp)
            if g_state.get("task_id") == task_id:
                global_cp.unlink()
        except RunnerError:
            pass
    print(f"RESET {task_id}: Đã xóa checkpoint và worktree của task.")
    return 0


def update_task_status_in_backlog(backlog_path: Path, task_id: str, new_status: str) -> None:
    backlog = load_json(backlog_path)
    tasks = backlog.get("tasks", [])
    found = False
    for task in tasks:
        if isinstance(task, dict) and task.get("id") == task_id:
            task["status"] = new_status
            found = True
            break
    if found:
        backlog_path.write_text(
            json.dumps(backlog, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )


def stage_review_snapshot(task: dict[str, Any], cwd: Path | None = None) -> tuple[list[str], str, str]:
    kwargs = {"cwd": cwd} if cwd is not None and cwd != ROOT else {}
    changed = validate_scope(task, cwd=cwd)
    git("add", "--", *changed, **kwargs)
    unstaged = git("diff", "--name-only", "-z", **kwargs)
    untracked_raw = git("ls-files", "--others", "--exclude-standard", "-z", **kwargs)
    untracked = [p for p in untracked_raw.split("\0") if p and p not in changed]
    if unstaged or untracked:
        raise RunnerError("Không tạo được snapshot sạch để review.")
    return changed, git("write-tree", **kwargs), git("rev-parse", "HEAD", **kwargs)


def verify_review_snapshot(reviewed_tree: str, reviewed_head: str, cwd: Path | None = None) -> None:
    kwargs = {"cwd": cwd} if cwd is not None and cwd != ROOT else {}
    if git("write-tree", **kwargs) != reviewed_tree or git("rev-parse", "HEAD", **kwargs) != reviewed_head:
        raise RunnerError("Snapshot đã thay đổi trong lúc review; không được commit.")
    unstaged = git("diff", "--name-only", "-z", **kwargs)
    untracked = git("ls-files", "--others", "--exclude-standard", "-z", **kwargs)
    if unstaged or untracked:
        raise RunnerError("Working tree thay đổi sau review; không được commit.")


def staged_paths(cwd: Path | None = None) -> list[str]:
    kwargs = {"cwd": cwd} if cwd is not None and cwd != ROOT else {}
    output = git("diff", "--cached", "--name-only", "-z", "--diff-filter=ACDMRTUXB", **kwargs)
    return sorted(path for path in output.split("\0") if path)


def unstage_paths(paths: list[str], cwd: Path | None = None) -> None:
    kwargs = {"cwd": cwd} if cwd is not None and cwd != ROOT else {}
    git("restore", "--staged", "--", *paths, **kwargs)


def commit_and_push(
    task: dict[str, Any],
    config: dict[str, Any],
    reviewed_tree: str,
    reviewed_head: str,
    cutoff: datetime,
    margin: timedelta,
    clock: Clock | None = None,
) -> str:
    ref_clock = clock or DEFAULT_CLOCK
    ensure_authorized_git_target(config)
    remaining_timeout_seconds(cutoff, margin, 1, clock=ref_clock)
    revision = git_with_input(
        "commit-tree", reviewed_tree, "-p", reviewed_head,
        input_text=task["commit_message"] + "\n",
        timeout_seconds=remaining_timeout_seconds(cutoff, margin, 180, clock=ref_clock),
    )
    git("update-ref", f"refs/heads/{config['branch']}", revision, reviewed_head)
    if git("rev-parse", "HEAD^{tree}") != reviewed_tree:
        raise RunnerError("Commit không trùng tree đã review; không được push.")
    checkpoint(task["id"], "delivery_pending", revision=revision, clock=ref_clock)
    push_revision(config, revision, cutoff, margin, clock=ref_clock)
    return revision


def push_revision(
    config: dict[str, Any],
    revision: str,
    cutoff: datetime,
    margin: timedelta,
    clock: Clock | None = None,
) -> None:
    ref_clock = clock or DEFAULT_CLOCK
    ensure_authorized_git_target(config)
    if git("rev-parse", "HEAD") != revision:
        raise RunnerError("HEAD không còn trùng commit chờ push.")
    ensure_clean_repository()
    push_timeout = remaining_timeout_seconds(cutoff, margin, 10 * 60, clock=ref_clock)
    git(
        "push",
        config["remote"],
        f"{revision}:refs/heads/{config['branch']}",
        timeout_seconds=push_timeout,
    )
    verify_timeout = remaining_timeout_seconds(cutoff, margin, 120, clock=ref_clock)
    remote_revision = git(
        "ls-remote",
        config["remote"],
        f"refs/heads/{config['branch']}",
        timeout_seconds=verify_timeout,
    )
    if not remote_revision.startswith(revision + "\t"):
        raise RunnerError("Không xác minh được revision trên remote sau push.")


def deliver_approved_worktree_task(
    task: dict[str, Any],
    config: dict[str, Any],
    candidate_tree: str,
    candidate_head: str,
    base_revision: str,
    cutoff: datetime,
    margin: timedelta,
    cwd: Path | None = None,
    clock: Clock | None = None,
) -> str:
    ref_clock = clock or DEFAULT_CLOCK
    ensure_authorized_git_target(config)
    ensure_clean_repository()
    remaining_timeout_seconds(cutoff, margin, 1, clock=ref_clock)
    current_head = git("rev-parse", "HEAD")
    wt = cwd if cwd is not None else ROOT
    commit_timeout = remaining_timeout_seconds(cutoff, margin, 180, clock=ref_clock)

    if current_head == base_revision:
        revision = git_with_input(
            "commit-tree", candidate_tree, "-p", current_head,
            input_text=task["commit_message"] + "\n",
            timeout_seconds=commit_timeout,
        )
        git("update-ref", f"refs/heads/{config['branch']}", revision, current_head)
        if git("rev-parse", "HEAD^{tree}") != candidate_tree:
            raise RunnerError("Commit trên main không trùng tree đã review; không được push.")

        git("reset", "--hard", revision)
        checkpoint(task["id"], "delivery_pending", revision=revision, clock=ref_clock)
        task_checkpoint(task["id"], "DELIVERY_PENDING", revision=revision, clock=ref_clock)
        push_revision(config, revision, cutoff, margin, clock=ref_clock)
        return revision

    # Trường hợp nhiều worktree cùng baseline: main đã tiến về phía trước
    candidate_commit = git_with_input(
        "commit-tree", candidate_tree, "-p", base_revision,
        input_text=task["commit_message"] + "\n",
        timeout_seconds=commit_timeout,
        cwd=wt,
    )
    git("reset", "--hard", cwd=wt)
    git("checkout", "--detach", current_head, cwd=wt)
    cp_result = run_command(
        ["git", "cherry-pick", "--no-commit", candidate_commit],
        timeout_seconds=remaining_timeout_seconds(cutoff, margin, 120, clock=ref_clock),
        cwd=wt,
    )
    if cp_result.returncode != 0:
        run_command(["git", "cherry-pick", "--abort"], timeout_seconds=30, cwd=wt)
        raise RunnerError(f"Conflict khi tích hợp task {task['id']} lên HEAD mới ({current_head}). Cần xử lý.")

    rebase_run_dir = STATE_DIR / "runs" / f"{ref_clock.now().strftime('%Y%m%d-%H%M%S')}-{task['id']}-rebase-check"
    rebase_run_dir.mkdir(parents=True, exist_ok=True)
    run_checks(task, rebase_run_dir, cutoff, margin, cwd=wt, clock=ref_clock)

    # Review độc lập lại tree kết hợp sau cherry-pick theo AGENTS.md
    rebased_changed, rebased_tree, rebased_head = stage_review_snapshot(task, cwd=wt)
    review_available = int((cutoff - margin - ref_clock.now()).total_seconds())
    if review_available <= 0:
        unstage_paths(rebased_changed, cwd=wt)
        raise RunnerError("Đã đến vùng dừng trước cutoff; không kịp review tree sau rebase.")

    review_timeout = min(config["agent_timeout_minutes"] * 60 + 30, review_available)
    rebase_review, err_class = call_codex_review(task, config, rebase_run_dir, review_timeout, cwd=wt)
    if err_class is not None:
        unstage_paths(rebased_changed, cwd=wt)
        raise RunnerError(f"Review tree sau rebase thất bại ({err_class}).")
    assert rebase_review is not None
    if rebase_review.get("approved") is not True or rebase_review.get("findings"):
        unstage_paths(rebased_changed, cwd=wt)
        raise RunnerError("Tree sau rebase có findings; cần sửa trước khi giao.")

    verify_review_snapshot(rebased_tree, rebased_head, cwd=wt)
    try:
        rebase_commit_timeout = remaining_timeout_seconds(cutoff, margin, 180, clock=ref_clock)
    except RunnerError:
        unstage_paths(rebased_changed, cwd=wt)
        raise
    rebased_revision = git_with_input(
        "commit-tree", rebased_tree, "-p", current_head,
        input_text=task["commit_message"] + "\n",
        timeout_seconds=rebase_commit_timeout,
    )
    git("update-ref", f"refs/heads/{config['branch']}", rebased_revision, current_head)
    git("reset", "--hard", rebased_revision)

    checkpoint(task["id"], "delivery_pending", revision=rebased_revision, clock=ref_clock)
    task_checkpoint(task["id"], "DELIVERY_PENDING", revision=rebased_revision, clock=ref_clock)
    push_revision(config, rebased_revision, cutoff, margin, clock=ref_clock)
    return rebased_revision


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
            review, err_class = call_codex_review(task, config, run_dir, review_timeout)
        except RunnerError:
            unstage_paths(changed)
            raise
        if err_class is not None:
            unstage_paths(changed)
            raise RunnerError(f"Codex review không thành công: {err_class}")
        assert review is not None
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


def run_worktree_repair_loop(
    task: dict[str, Any],
    config: dict[str, Any],
    cutoff: datetime,
    wt_dir: Path,
    base_revision: str,
    initial_review: dict[str, Any],
    start_round: int = 1,
    clock: Clock | None = None,
) -> str:
    ref_clock = clock or DEFAULT_CLOCK
    review: dict[str, Any] | None = initial_review
    run_dir = STATE_DIR / "runs" / f"{ref_clock.now().strftime('%Y%m%d-%H%M%S')}-{task['id']}"
    run_dir.mkdir(parents=True, exist_ok=True)
    margin = timedelta(minutes=config["shutdown_margin_minutes"])

    for round_index in range(start_round, config["max_repair_rounds"] + 1):
        available_seconds = int((cutoff - ref_clock.now()).total_seconds())
        if available_seconds <= 0:
            task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class="cutoff_exceeded")
            write_handoff("Chạm cutoff 05:00", task["id"], "Dừng sửa task do đã chạm cutoff.", clock=ref_clock)
            return "BLOCKED"

        agent_timeout = min(config["agent_timeout_minutes"] * 60 + 30, available_seconds)
        call_gemini(task, config, run_dir, review, agent_timeout, cwd=wt_dir)
        changed = validate_scope(task, cwd=wt_dir)
        task_checkpoint(task["id"], "CHECKING", clock=ref_clock, round=round_index, changed_paths=changed)

        check_available = int((cutoff - ref_clock.now()).total_seconds())
        if check_available <= 0:
            task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class="cutoff_exceeded")
            return "BLOCKED"
        run_checks(task, run_dir, cutoff, timedelta(0), cwd=wt_dir, clock=ref_clock)

        changed, candidate_tree, candidate_head = stage_review_snapshot(task, cwd=wt_dir)
        task_checkpoint(
            task["id"],
            "REVIEWING",
            clock=ref_clock,
            round=round_index,
            candidate_tree=candidate_tree,
            candidate_head=candidate_head,
            changed_paths=changed,
        )

        review_available = int((cutoff - ref_clock.now()).total_seconds())
        if review_available <= 0:
            unstage_paths(changed, cwd=wt_dir)
            task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class="cutoff_exceeded")
            return "BLOCKED"

        review_timeout = min(config["agent_timeout_minutes"] * 60 + 30, review_available)
        try:
            review_result, err_class = call_codex_review(task, config, run_dir, review_timeout, cwd=wt_dir)
        except RunnerError:
            unstage_paths(changed, cwd=wt_dir)
            raise

        if err_class == "quota":
            unstage_paths(changed, cwd=wt_dir)
            task_checkpoint(
                task["id"],
                "AWAITING_REVIEW",
                clock=ref_clock,
                candidate_tree=candidate_tree,
                candidate_head=candidate_head,
                changed_paths=changed,
                last_error_class="quota",
            )
            write_handoff(
                "Codex hết quota",
                task["id"],
                f"Task {task['id']} chuyển sang AWAITING_REVIEW.",
                clock=ref_clock,
            )
            return "AWAITING_REVIEW"

        if err_class is not None:
            unstage_paths(changed, cwd=wt_dir)
            task_checkpoint(
                task["id"],
                "BLOCKED",
                clock=ref_clock,
                candidate_tree=candidate_tree,
                candidate_head=candidate_head,
                changed_paths=changed,
                last_error_class=err_class,
            )
            write_handoff("Codex review lỗi", task["id"], f"Codex gặp lỗi {err_class}.", clock=ref_clock)
            return "BLOCKED"

        assert review_result is not None
        safe_review = review_artifact(review_result)
        (run_dir / f"review-{round_index}.json").write_text(
            json.dumps(safe_review, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

        if review_result.get("approved") is True and not review_result.get("findings"):
            verify_review_snapshot(candidate_tree, candidate_head, cwd=wt_dir)
            task_checkpoint(
                task["id"],
                "APPROVED",
                clock=ref_clock,
                candidate_tree=candidate_tree,
                candidate_head=candidate_head,
                review_artifact=safe_review,
            )
            revision = deliver_approved_worktree_task(
                task,
                config,
                candidate_tree,
                candidate_head,
                base_revision,
                cutoff,
                margin,
                cwd=wt_dir,
                clock=ref_clock,
            )
            task_checkpoint(task["id"], "DONE", clock=ref_clock, revision=revision)
            remove_task_worktree(task["id"])
            write_handoff("Hoàn tất task", task["id"], f"Đã push revision {revision}.", clock=ref_clock)
            return "DONE"

        unstage_paths(changed, cwd=wt_dir)
        task_checkpoint(task["id"], "REPAIRING", clock=ref_clock, round=round_index, review_artifact=safe_review)
        review = safe_review

    task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class="max_repair_rounds_exceeded")
    return "BLOCKED"


def execute_task_in_worktree(
    task: dict[str, Any],
    config: dict[str, Any],
    cutoff: datetime,
    *,
    clock: Clock | None = None,
) -> str:
    ref_clock = clock or DEFAULT_CLOCK
    margin = timedelta(minutes=config["shutdown_margin_minutes"])
    ensure_authorized_git_target(config)
    ensure_head_exists()
    ensure_clean_repository()
    base_revision = git("rev-parse", "HEAD")

    available_seconds = int((cutoff - ref_clock.now()).total_seconds())
    if available_seconds <= 0:
        task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class="cutoff_exceeded")
        write_handoff("Chạm cutoff 05:00", task["id"], "Dừng task do đã chạm cutoff.", clock=ref_clock)
        return "BLOCKED"

    wt_dir = create_task_worktree(task["id"], base_revision)
    run_dir = STATE_DIR / "runs" / f"{ref_clock.now().strftime('%Y%m%d-%H%M%S')}-{task['id']}"
    run_dir.mkdir(parents=True, exist_ok=True)

    task_checkpoint(
        task["id"],
        "IMPLEMENTING",
        clock=ref_clock,
        base_revision=base_revision,
        worktree_path=str(wt_dir.resolve()),
        run_dir=str(run_dir),
    )

    agent_timeout = min(config["agent_timeout_minutes"] * 60 + 30, available_seconds)
    call_gemini(task, config, run_dir, None, agent_timeout, cwd=wt_dir)
    changed = validate_scope(task, cwd=wt_dir)
    task_checkpoint(task["id"], "CHECKING", clock=ref_clock, round=0, changed_paths=changed)

    check_available = int((cutoff - ref_clock.now()).total_seconds())
    if check_available <= 0:
        task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class="cutoff_exceeded")
        return "BLOCKED"
    run_checks(task, run_dir, cutoff, timedelta(0), cwd=wt_dir, clock=ref_clock)

    changed, candidate_tree, candidate_head = stage_review_snapshot(task, cwd=wt_dir)
    task_checkpoint(
        task["id"],
        "REVIEWING",
        clock=ref_clock,
        round=0,
        candidate_tree=candidate_tree,
        candidate_head=candidate_head,
        changed_paths=changed,
    )

    review_available = int((cutoff - ref_clock.now()).total_seconds())
    if review_available <= 0:
        unstage_paths(changed, cwd=wt_dir)
        task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class="cutoff_exceeded")
        return "BLOCKED"

    review_timeout = min(config["agent_timeout_minutes"] * 60 + 30, review_available)
    try:
        review, err_class = call_codex_review(task, config, run_dir, review_timeout, cwd=wt_dir)
    except RunnerError:
        unstage_paths(changed, cwd=wt_dir)
        raise

    if err_class == "quota":
        unstage_paths(changed, cwd=wt_dir)
        task_checkpoint(
            task["id"],
            "AWAITING_REVIEW",
            clock=ref_clock,
            candidate_tree=candidate_tree,
            candidate_head=candidate_head,
            changed_paths=changed,
            last_error_class="quota",
        )
        write_handoff(
            "Codex hết quota",
            task["id"],
            f"Task {task['id']} chuyển sang AWAITING_REVIEW. Đợi retry lúc 03:45.",
            clock=ref_clock,
            worktree=wt_dir,
        )
        return "AWAITING_REVIEW"

    if err_class is not None:
        unstage_paths(changed, cwd=wt_dir)
        task_checkpoint(
            task["id"],
            "BLOCKED",
            clock=ref_clock,
            candidate_tree=candidate_tree,
            candidate_head=candidate_head,
            changed_paths=changed,
            last_error_class=err_class,
        )
        write_handoff("Codex review lỗi", task["id"], f"Codex gặp lỗi {err_class}.", clock=ref_clock)
        return "BLOCKED"

    assert review is not None
    safe_review = review_artifact(review)
    (run_dir / "review-0.json").write_text(
        json.dumps(safe_review, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    if review.get("approved") is True and not review.get("findings"):
        verify_review_snapshot(candidate_tree, candidate_head, cwd=wt_dir)
        task_checkpoint(
            task["id"],
            "APPROVED",
            clock=ref_clock,
            candidate_tree=candidate_tree,
            candidate_head=candidate_head,
            review_artifact=safe_review,
        )
        revision = deliver_approved_worktree_task(
            task,
            config,
            candidate_tree,
            candidate_head,
            base_revision,
            cutoff,
            margin,
            cwd=wt_dir,
            clock=ref_clock,
        )
        task_checkpoint(task["id"], "DONE", clock=ref_clock, revision=revision)
        remove_task_worktree(task["id"])
        write_handoff("Hoàn tất task", task["id"], f"Đã push revision {revision}.", clock=ref_clock)
        return "DONE"

    unstage_paths(changed, cwd=wt_dir)
    task_checkpoint(task["id"], "REPAIRING", clock=ref_clock, round=0, review_artifact=safe_review)
    return run_worktree_repair_loop(
        task, config, cutoff, wt_dir, base_revision,
        initial_review=safe_review, start_round=1, clock=ref_clock,
    )


def retry_awaiting_task(
    task: dict[str, Any],
    config: dict[str, Any],
    cutoff: datetime,
    margin: timedelta,
    clock: Clock | None = None,
) -> str:
    ref_clock = clock or DEFAULT_CLOCK
    task_cp = load_task_checkpoint(task["id"])
    if not task_cp or task_cp.get("stage") != "AWAITING_REVIEW":
        return task.get("status", "UNKNOWN")

    wt_dir = Path(task_cp.get("worktree_path", str(task_worktree_dir(task["id"]))))
    if not wt_dir.exists():
        task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class="worktree_missing")
        return "BLOCKED"

    candidate_tree = task_cp.get("candidate_tree")
    candidate_head = task_cp.get("candidate_head")
    base_revision = task_cp.get("base_revision", candidate_head)
    changed_paths = task_cp.get("changed_paths", [])
    if not candidate_tree or not candidate_head:
        task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class="snapshot_missing")
        return "BLOCKED"

    if changed_paths:
        git("add", "--", *changed_paths, cwd=wt_dir)
    try:
        verify_review_snapshot(candidate_tree, candidate_head, cwd=wt_dir)
    except RunnerError:
        if changed_paths:
            unstage_paths(changed_paths, cwd=wt_dir)
        raise

    run_dir = STATE_DIR / "runs" / f"{ref_clock.now().strftime('%Y%m%d-%H%M%S')}-{task['id']}-retry"
    run_dir.mkdir(parents=True, exist_ok=True)

    task_checkpoint(task["id"], "REVIEWING", clock=ref_clock, round="retry_0345")
    review_available = int((cutoff - ref_clock.now()).total_seconds())
    if review_available <= 0:
        if changed_paths:
            unstage_paths(changed_paths, cwd=wt_dir)
        task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class="cutoff_exceeded")
        write_handoff("Chạm cutoff 05:00", task["id"], "Dừng retry do đã chạm cutoff.", clock=ref_clock)
        return "BLOCKED"
    review_timeout = min(config["agent_timeout_minutes"] * 60 + 30, review_available)

    try:
        review, err_class = call_codex_review(task, config, run_dir, review_timeout, cwd=wt_dir)
    except RunnerError as error:
        if changed_paths:
            unstage_paths(changed_paths, cwd=wt_dir)
        task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class=str(error))
        return "BLOCKED"

    if err_class == "quota":
        if changed_paths:
            unstage_paths(changed_paths, cwd=wt_dir)
        task_checkpoint(task["id"], "AWAITING_REVIEW", clock=ref_clock, last_error_class="quota")
        write_handoff(
            "Codex retry 03:45: vẫn hết quota",
            task["id"],
            "Tiếp tục giữ worktree và checkpoint có thể khôi phục.",
            clock=ref_clock,
        )
        return "AWAITING_REVIEW"

    if err_class is not None:
        if changed_paths:
            unstage_paths(changed_paths, cwd=wt_dir)
        task_checkpoint(task["id"], "BLOCKED", clock=ref_clock, last_error_class=err_class)
        write_handoff("Codex retry 03:45 lỗi", task["id"], f"Codex gặp lỗi {err_class}.", clock=ref_clock)
        return "BLOCKED"

    assert review is not None
    safe_review = review_artifact(review)
    (run_dir / "review-0345.json").write_text(
        json.dumps(safe_review, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    if review.get("approved") is True and not review.get("findings"):
        verify_review_snapshot(candidate_tree, candidate_head, cwd=wt_dir)
        task_checkpoint(task["id"], "APPROVED", clock=ref_clock, review_artifact=safe_review)
        revision = deliver_approved_worktree_task(
            task,
            config,
            candidate_tree,
            candidate_head,
            base_revision,
            cutoff,
            margin,
            cwd=wt_dir,
            clock=ref_clock,
        )
        task_checkpoint(task["id"], "DONE", clock=ref_clock, revision=revision)
        remove_task_worktree(task["id"])
        write_handoff("Hoàn tất task sau retry 03:45", task["id"], f"Đã deliver task {task['id']}.", clock=ref_clock)
        return "DONE"

    if changed_paths:
        unstage_paths(changed_paths, cwd=wt_dir)
    task_checkpoint(task["id"], "REPAIRING", clock=ref_clock, review_artifact=safe_review)
    return run_worktree_repair_loop(
        task, config, cutoff, wt_dir, base_revision,
        initial_review=safe_review, start_round=1, clock=ref_clock,
    )


def get_task_stage(task: dict[str, Any], session_blocked: set[str] | None = None) -> str:
    task_id = str(task.get("id", ""))
    if session_blocked and task_id in session_blocked:
        return "BLOCKED"
    cp = load_task_checkpoint(task_id)
    if cp and cp.get("stage"):
        stage = str(cp["stage"]).upper()
        # Nếu checkpoint ở trạng thái kết thúc (BLOCKED / CUTOFF_EXCEEDED) nhưng backlog được đánh dấu READY:
        # trạng thái READY mới là sự ủy quyền thực thi, thay thế checkpoint kết thúc cũ.
        if stage in ("BLOCKED", "CUTOFF_EXCEEDED") and str(task.get("status", "")).upper() == "READY":
            return "READY"
        return stage
    return str(task.get("status", "DRAFT")).upper()


def run_queue(
    config: dict[str, Any],
    backlog_path: Path,
    cutoff: datetime,
    stop_accepting_time: datetime | None = None,
    retry_time: datetime | None = None,
    clock: Clock | None = None,
) -> int:
    ref_clock = clock or DEFAULT_CLOCK
    margin = timedelta(minutes=config["shutdown_margin_minutes"])
    if stop_accepting_time is None:
        stop_accepting_time = cutoff - margin
    if retry_time is None:
        retry_time = cutoff.replace(hour=3, minute=45, second=0, microsecond=0)

    retry_done_for_0345 = False
    session_blocked: set[str] = set()

    ensure_authorized_git_target(config)
    ensure_head_exists()
    ensure_no_pending_delivery()
    ensure_clean_repository()

    while True:
        now = ref_clock.now()

        # 1. Kiểm tra mốc 03:45 để retry các task AWAITING_REVIEW
        if not retry_done_for_0345 and now >= retry_time and now < cutoff:
            retry_done_for_0345 = True
            backlog = load_json(backlog_path)
            awaiting_tasks = [
                t for t in backlog.get("tasks", [])
                if isinstance(t, dict) and get_task_stage(t, session_blocked) == "AWAITING_REVIEW"
            ]
            for task in awaiting_tasks:
                outcome = retry_awaiting_task(task, config, cutoff, margin, clock=ref_clock)
                if outcome == "BLOCKED":
                    session_blocked.add(task["id"])

        # 2. Ngừng nhận task mới sau stop_accepting_time (04:50)
        now = ref_clock.now()
        if now >= stop_accepting_time:
            write_handoff(
                "Dừng nhận task mới (04:50/cutoff)",
                None,
                f"Đã qua mốc dừng nhận việc ({stop_accepting_time.isoformat()}).",
                clock=ref_clock,
            )
            break

        # 3. Tìm task READY kế tiếp
        backlog = load_json(backlog_path)
        next_task = None
        for task in backlog.get("tasks", []):
            if isinstance(task, dict) and get_task_stage(task, session_blocked) == "READY":
                next_task = task
                break

        if next_task is None:
            # Nếu còn task AWAITING_REVIEW mà chưa tới 03:45 thì chờ đến 03:45
            has_awaiting = any(
                isinstance(t, dict) and get_task_stage(t, session_blocked) == "AWAITING_REVIEW"
                for t in backlog.get("tasks", [])
            )
            if has_awaiting and not retry_done_for_0345 and now < retry_time:
                wait_seconds = (retry_time - now).total_seconds()
                if wait_seconds > 0:
                    ref_clock.sleep(min(wait_seconds, 300))
                    continue
            break

        # 4. Triển khai task trong worktree riêng biệt
        outcome = execute_task_in_worktree(
            next_task,
            config,
            cutoff,
            clock=ref_clock,
        )
        if outcome == "BLOCKED":
            session_blocked.add(next_task["id"])

        # 5. Nếu task dang dở hoàn thiện xong mà đồng hồ đã chạm/qua cutoff 05:00, dừng scheduler
        if ref_clock.now() >= cutoff:
            write_handoff(
                "Dừng hàng đợi lúc cutoff (05:00)",
                next_task["id"],
                f"Task {next_task['id']} đã hoàn thiện xong chu kỳ và đồng hồ đã chạm/qua cutoff ({cutoff.isoformat()}). Dừng scheduler.",
                clock=ref_clock,
            )
            break

    return 0


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
    reset_parser = subparsers.add_parser("reset", help="Xóa checkpoint và worktree của task để chạy lại từ đầu")
    reset_parser.add_argument("task_id", nargs="?", help="ID task cần reset")
    reset_parser.add_argument("--all", action="store_true", help="Reset toàn bộ task")
    queue_parser = subparsers.add_parser("queue", help="Chạy hàng đợi task với worktree và retry 03:45")
    queue_parser.add_argument("--cutoff", help="ISO-8601 có múi giờ; mặc định 05:00 kế tiếp")
    queue_parser.add_argument("--stop-accepting", help="ISO-8601 có múi giờ; mặc định cutoff - margin")
    queue_parser.add_argument("--retry-time", help="ISO-8601 có múi giờ; mặc định 03:45 cùng ngày cutoff")
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
            task_checkpoint(active_task, "DONE", revision=state["revision"])
            remove_task_worktree(active_task)
            checkpoint(active_task, "done", revision=state["revision"])
            write_handoff("Đã giao commit chờ push", active_task, f"Đã push {state['revision']}.")
            print(f"DONE {active_task}: {state['revision']}")
            return 0
        if arguments.command == "reset":
            return reset_task(arguments.task_id, reset_all=arguments.all)
        if arguments.command == "queue":
            cutoff = parse_cutoff(arguments.cutoff, config["stop_hour"])
            stop_accepting = (
                datetime.fromisoformat(arguments.stop_accepting).astimezone(TIMEZONE)
                if arguments.stop_accepting
                else cutoff - timedelta(minutes=config["shutdown_margin_minutes"])
            )
            retry_time = (
                datetime.fromisoformat(arguments.retry_time).astimezone(TIMEZONE)
                if arguments.retry_time
                else cutoff.replace(hour=3, minute=45, second=0, microsecond=0)
            )
            print(f"Bắt đầu queue: cutoff={cutoff.isoformat()}, stop_accepting={stop_accepting.isoformat()}, retry={retry_time.isoformat()}")
            return run_queue(
                config=config,
                backlog_path=RUNNER_DIR / "backlog.json",
                cutoff=cutoff,
                stop_accepting_time=stop_accepting,
                retry_time=retry_time,
            )
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
