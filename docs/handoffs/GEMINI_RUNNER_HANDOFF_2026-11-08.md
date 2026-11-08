# Handoff cho Gemini — hoàn thiện Oto multi-agent runner

Ngày bàn giao: 2026-11-08  
Múi giờ: `Asia/Ho_Chi_Minh`  
Repo: `/Users/hieu/Code/Oto`  
Remote được chủ dự án cho phép: `https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player.git`

## 1. Mục tiêu

Hoàn thiện runner để:

1. Gemini qua Antigravity CLI (`agy`) là agent triển khai chính.
2. Codex CLI là agent review độc lập.
3. Chỉ dùng quota đăng nhập sẵn có của hai CLI; không dùng API key hoặc paid fallback.
4. Task chỉ được commit/push sau khi checks pass và Codex approve snapshot cuối.
5. Nếu Codex hết quota, Gemini được làm tiếp các task độc lập trong worktree riêng.
6. Đúng 03:45 giờ Việt Nam, runner thử Codex lại cho hàng đợi chờ review.
7. Dừng có kiểm soát trước 05:00, luôn ghi checkpoint và handoff.

Đọc theo thứ tự:

- `AGENTS.md`
- `docs/AGENT_WORKFLOW.md`
- `docs/RUNNER_GUIDE.md`
- `docs/CLI_CONNECTION.md`
- `runner/config.json`
- `runner/backlog.json`
- `runner/oto_runner.py`

Không sửa checkout Kaset. Không chạy UI test, cài thiết bị thật, thêm dependency hoặc gửi request làm thay đổi tài khoản khi chưa được chủ dự án cho phép.

## 2. Hai CLI đã có trên máy

```text
Gemini/Antigravity: /Users/hieu/.local/bin/agy
Codex:              /Users/hieu/.local/bin/codex
```

Phiên bản từng được kiểm tra:

```text
agy 1.5.3
codex 0.167.0
```

Model Gemini đã chọn trong `runner/config.json`:

```text
gemini-3.8-flash-high
```

Không đọc hoặc xuất cookie/token của hai CLI. Runner dùng environment allowlist và dựa vào login cục bộ có sẵn.

## 3. Cách kết nối hai CLI

Hai CLI không nói chuyện trực tiếp. Runner làm bộ điều phối:

```text
backlog task
  -> runner tạo prompt có rules + acceptance criteria + scope
  -> agy triển khai và trả JSON theo implement-result.schema.json
  -> runner chạy checks
  -> runner stage đúng scope và chốt Git tree bất biến
  -> codex exec review snapshot/diff và trả JSON theo review-result.schema.json
  -> nếu có findings: runner đưa JSON về lại agy để sửa
  -> checks + Codex review lại
  -> approved: tạo commit đúng reviewed tree và push origin/main
```

Các entry point hiện có:

```bash
Scripts/oto-runner doctor
Scripts/oto-runner list
Scripts/oto-runner run S1-001 --cutoff 2026-11-09T05:00:00+07:00
Scripts/oto-runner run S1-001 --resume --cutoff 2026-11-09T05:00:00+07:00
Scripts/oto-runner retry-push --cutoff 2026-11-09T05:00:00+07:00
```

`S1-001` đang là `DRAFT`; không đổi sang `READY` cho tới khi có Xcode project/scheme thật và checks thật đã được xác định.

### Gọi Gemini có cấu trúc

Runner hiện gọi tương đương:

```bash
/Users/hieu/.local/bin/agy \
  --model gemini-3.8-flash-high \
  --effort high \
  --mode auto \
  --sandbox \
  --disable-slash-commands \
  --output-format json \
  --json-schema runner/schemas/implement-result.schema.json \
  -p "<task prompt>"
```

### Gọi Codex review có cấu trúc

Runner hiện gọi tương đương:

```bash
/Users/hieu/.local/bin/codex exec review \
  --uncommitted \
  --ephemeral \
  --output-schema runner/schemas/review-result.schema.json \
  -
```

Prompt được truyền qua stdin. Không dùng `--output-last-message` vì raw response có thể được ghi xuống đĩa trước khi sanitize. Parse stdout trong memory, sau đó chỉ lưu artifact rút gọn không có `evidence`.

## 4. Trạng thái đã làm

Runner một-task đã có:

- Kiểm tra Git root, branch, đúng một fetch URL và một push URL được cho phép.
- Chỉ nhận task `READY`; từ chối working tree bẩn.
- Strict cutoff đúng `05:00:00` giờ Việt Nam và margin dừng 10 phút.
- Process group riêng; timeout/SIGINT/SIGTERM dừng cả process tree.
- Environment allowlist; không truyền các biến API key phổ biến.
- Scope allowlist cho file thay đổi.
- Checks dùng argument arrays, không dùng shell string.
- Git tree snapshot trước review.
- Commit bằng `git commit-tree` từ đúng reviewed tree, sau đó `git update-ref` có expected old HEAD.
- Checkpoint `delivery_pending` và lệnh `retry-push`.
- `--resume` cho task dở đúng scope.
- Redaction và artifact rút gọn; không lưu raw check stdout/stderr hoặc raw Codex response.

Các test gần nhất:

```bash
python3 -m unittest discover -s Tests/RunnerTests -v
python3 -m py_compile runner/oto_runner.py
git diff --check
```

Kết quả gần nhất: 11 unit tests pass, py_compile pass, diff check pass. `Scripts/oto-runner doctor` pass Git root, hai executable và remote; nó chỉ báo working tree đang có thay đổi vì đây là initial uncommitted setup.

## 5. Review đã thực hiện và trạng thái review cuối

Hai vòng Codex trước đã tìm và runner đã sửa:

1. Process con có thể sống sau timeout/cutoff.
2. Cutoff từng cho phép giờ khác 05:00.
3. Chưa xác minh remote trước push.
4. Raw output có thể lưu credential.
5. Push lỗi thiếu đường retry an toàn.
6. Snapshot review/commit chưa bất biến.
7. Chưa kiểm tra `remote.pushurl` riêng.
8. Raw Codex response được ghi trước sanitize.
9. Commit hook có thể tạo commit khác reviewed tree.

Vòng review cuối sau các bản sửa trên **chưa hoàn tất**:

- Lần chạy trong sandbox thất bại khi Codex khởi tạo app-server: `Operation not permitted`.
- Lần xin chạy review read-only ngoài sandbox bị người dùng ngắt để yêu cầu handoff này.
- Không được ghi “Codex approved”. Gemini phải chạy lại checks và yêu cầu Codex review cuối trước commit/push.

## 6. Yêu cầu mới chưa triển khai: hàng đợi 03:45

Runner hiện chỉ xử lý một task/lệnh. Nó chưa được phép tiếp tục task khác sau khi Codex hết quota vì các diff sẽ trộn nhau.

Cần triển khai scheduler với nguyên tắc:

1. Mỗi task có một Git worktree riêng dựa trên cùng baseline đã push.
2. Một writer duy nhất trong mỗi worktree.
3. Khi Gemini xong và checks pass, lưu immutable candidate tree/metadata rồi chuyển task sang `AWAITING_REVIEW`.
4. Nếu Codex báo quota exhaustion trước 03:45, không retry liên tục; Gemini có thể nhận task READY độc lập kế tiếp trong worktree khác.
5. Không coi mọi lỗi Codex là quota. Phân loại tối thiểu: `quota`, `auth`, `network/transient`, `tool/internal`, `review finding`.
6. Lúc 03:45 `Asia/Ho_Chi_Minh`, thử Codex đúng một lượt theo thứ tự backlog. Nếu quota vẫn chưa có, checkpoint và handoff.
7. Findings quay lại Gemini trong đúng worktree; sửa xong chạy checks và review snapshot mới.
8. Chỉ task approved mới được đưa lên `main`, commit/push tuần tự. Trước tích hợp phải phát hiện baseline/main đã đổi và conflict.
9. Không force-push. Không overwrite worktree hoặc xóa thay đổi khi chưa có checkpoint có thể khôi phục.
10. Từ 04:50 không nhận task mới; ưu tiên lưu trạng thái/giao task đã đạt. Đến 05:00 dừng toàn bộ process group.

### Trạng thái đề xuất

```text
READY
IMPLEMENTING
CHECKING
AWAITING_REVIEW
REVIEWING
REPAIRING
APPROVED
DELIVERY_PENDING
DONE
BLOCKED
```

### Dữ liệu tối thiểu cho mỗi task checkpoint

```text
task_id
worktree_path
base_revision
candidate_tree
changed_paths
check summary (không raw output)
stage
attempt counts
last error class
review artifact đã sanitize
updated_at
```

Không lưu prompt/response thô nếu có thể chứa dữ liệu nhạy cảm.

## 7. Việc Gemini nên làm tiếp

1. Chạy lại ba checks ở mục 4.
2. Đọc kỹ `runner/oto_runner.py`; không giả định code đúng chỉ vì test pass.
3. Hoàn thiện test cho các nhánh chưa phủ: push URL khác fetch URL, exact-tree commit, timeout kill process tree, delivery pending, resume, malformed model JSON.
4. Nhờ Codex CLI review read-only bản runner một-task hiện tại. Nếu Codex thực sự hết quota, ghi đúng error class và không tự approve.
5. Sau khi review sạch, tạo initial commit tiếng Việt và push `origin/main` theo ủy quyền sẵn có của chủ dự án.
6. Trên baseline sạch, triển khai worktree scheduler/03:45 thành một task riêng, có unit/integration tests dùng repo tạm và fake CLI; không tiêu quota thật trong unit tests.
7. Codex review scheduler, Gemini sửa findings, checks lại, rồi commit/push task đó.
8. Chỉ sau đó mới chạy một smoke task nhỏ có người quan sát. Chưa chạy batch qua đêm ngay.

## 8. Definition of done cho scheduler

- Fake Codex quota trước 03:45 làm task chuyển `AWAITING_REVIEW`, không commit/push.
- Gemini task tiếp theo chạy trong worktree khác; file của hai task không trộn.
- Clock injected tới 03:45 kích hoạt đúng một review retry, không polling/spam.
- Fake Codex vẫn quota lúc 03:45 tạo handoff và giữ worktree khôi phục được.
- Fake Codex approve cho phép giao đúng candidate tree; thay đổi sau review bị chặn.
- Cutoff 04:50/05:00 dừng nhận việc/dừng process và giữ checkpoint.
- Auth/network/tool error không bị gắn nhầm thành quota.
- Không artifact nào chứa secret fixture.
- Không force-push, không chạy UI/device test, không paid API fallback.

## 9. Git hiện tại

Oto là Git root riêng, branch `main`, remote `origin` đã cấu hình. Remote từng được kiểm tra là trống. Toàn bộ planning docs và runner hiện vẫn là untracked/uncommitted initial state. Trước khi commit:

```bash
git status --short
git remote get-url --all origin
git remote get-url --push --all origin
```

Không sửa hoặc xóa thay đổi hiện có. Không dùng `git reset --hard`, `git clean`, force-push hoặc thao tác phá hủy để làm sạch repo.

