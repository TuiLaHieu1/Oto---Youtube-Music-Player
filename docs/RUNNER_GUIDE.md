# Oto runner — cách sử dụng

Runner nằm ở `Scripts/oto-runner`. Nó nối Gemini qua Antigravity (`agy`) với Codex review, nhưng chỉ chạy khi người dùng gọi lệnh.

## Luồng một task

1. Đọc task `READY` trong `runner/backlog.json`.
2. Từ chối chạy nếu Git root không phải Oto hoặc working tree đang bẩn.
3. Gọi Gemini bằng `agy` trong sandbox để triển khai đúng scope.
4. Chạy danh sách checks dạng argument arrays, không chạy shell string.
5. Gọi `codex exec review --uncommitted` với output schema có cấu trúc.
6. Nếu có findings, chuyển JSON về Gemini và lặp tối đa ba vòng sửa.
7. Khi checks pass và Codex approve không còn findings, chỉ stage file trong scope, commit tiếng Việt và push `origin/main`.
8. Lưu checkpoint cùng handoff local trong `.oto-runner/`. Thư mục này bị Git ignore và không chứa raw credentials.

Runner dừng nhận task mới trước cutoff 10 phút. Cutoff mặc định là 05:00 kế tiếp theo `Asia/Ho_Chi_Minh`; có thể ghi rõ ngày để tránh hiểu nhầm.

## Chính sách Codex hết quota

Mốc thử lại Codex đã chốt là **03:45 giờ Việt Nam**. Thiết kế batch sẽ đặt mỗi task Gemini đã làm vào một Git worktree riêng với trạng thái `AWAITING_REVIEW`, để Gemini có thể làm task READY kế tiếp mà không trộn diff. Task chờ Codex không được commit/push hoặc ghi DONE. Lúc 03:45, runner review hàng đợi, đưa finding về Gemini sửa và chỉ giao task đã đạt cổng trước 05:00.

Phiên bản runner hiện tại chỉ chạy một task/lệnh và **chưa triển khai worktree queue hay lịch 03:45**. Nếu Codex hết quota, nó dừng và ghi handoff. Không bật chạy batch qua đêm cho tới khi scheduler này có test hồi quy; đây là điểm chặn có chủ ý để tránh trộn nhiều task chưa review trong cùng working tree.

## Lệnh

```bash
Scripts/oto-runner doctor
Scripts/oto-runner list
Scripts/oto-runner run S1-001 --cutoff 2026-11-09T05:00:00+07:00
Scripts/oto-runner run S1-001 --resume --cutoff 2026-11-09T05:00:00+07:00
Scripts/oto-runner retry-push --cutoff 2026-11-09T05:00:00+07:00
```

`doctor` và `list` không gọi model. `run` từ chối task `DRAFT`; đổi sang `READY` sau khi prompt, scope và checks đã hoàn chỉnh. Backlog mẫu để `S1-001` ở DRAFT vì chưa có Xcode project nên chưa biết build/test commands thật.

Nếu task dừng sau khi đã sửa file, đọc handoff rồi dùng `run <task> --resume`. Runner chỉ nhận checkpoint cùng task và thay đổi nằm trong scope. Nếu push lỗi sau commit, dùng `retry-push`; không dùng `--resume` để triển khai lại.

## Thêm task

Mỗi task cần:

- ID, tiêu đề, prompt và trạng thái `DRAFT` hoặc `READY`.
- Tài liệu tham chiếu và acceptance criteria kiểm chứng được.
- `allowed_paths` đủ hẹp để phát hiện sửa nhầm phạm vi.
- `checks` dưới dạng mảng argument, ví dụ `["swift", "test"]`; không dùng `"swift test && ..."`.
- Commit message tiếng Việt đơn giản.

## Quyền và giới hạn

- Runner không dùng API key từ environment; nó loại các biến API phổ biến và dựa vào login sẵn có của hai CLI.
- Process con chạy trong process group riêng; timeout, SIGINT và SIGTERM dừng toàn bộ nhóm trước khi ghi handoff.
- `--cutoff` chỉ nhận đúng 05:00:00 giờ Việt Nam. Runner trừ thêm 10 phút để hoàn tất checkpoint.
- Trước commit, runner stage scope thành một Git tree, Codex review snapshot đó và runner so lại tree/HEAD. Commit được tạo trực tiếp từ đúng tree đã review rồi cập nhật branch có điều kiện; runner không chạy Git commit hook.
- Cả fetch URL lẫn push URL, Git root và nhánh được xác minh trước mọi commit/push. Chỉ repo GitHub đã được chủ dự án ủy quyền được chấp nhận.
- Artifact không lưu raw stdout/stderr của checks hoặc raw Codex response. Kết quả model được rút gọn và redaction trước khi ghi; environment của process con dùng allowlist, không truyền token môi trường phổ biến.
- Runner không dùng `--dangerously-skip-permissions`, không force-push, không chạy UI test hoặc thiết bị thật.
- Antigravity có thể dừng ở trạng thái cần permission nếu sandbox chưa cho một thao tác. Khi đó handoff ghi blocker; cấu hình quyền phải được thu hẹp theo task trước khi chạy lại.
- Runner chưa tự biết quota còn bao nhiêu. Exit lỗi/quota làm dừng và ghi handoff; không tự chuyển sang dịch vụ trả phí.
- Commit/push là phần của `run`. Push lỗi khiến delivery chưa hoàn tất dù commit đã tồn tại local.
- Push lỗi ghi checkpoint `delivery_pending`; dùng `retry-push` để giao đúng revision, không triển khai lại task.
- Phiên đầu nên chạy một task foundation có người quan sát. Chỉ chạy qua đêm sau khi task đó chứng minh build, review, repair, commit và push hoạt động đúng.
