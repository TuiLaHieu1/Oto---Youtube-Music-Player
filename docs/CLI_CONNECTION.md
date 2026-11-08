# Oto — kết nối Antigravity và Codex

Ngày kiểm tra: 2026-11-08. Kết quả: **PASS cho truyền phản hồi CLI**, chưa phải PASS cho coding loop, code review hay playback iOS.

## Công cụ đã xác minh trên máy

| Vai trò | Executable | Phiên bản |
| --- | --- | --- |
| Gemini triển khai | `/Users/hieu/.local/bin/agy` — Google Antigravity CLI | 1.5.3 |
| Reviewer | `/Users/hieu/.local/bin/codex` | 0.167.0 |

`agy` không phải tên alias của Gemini CLI riêng biệt. CLI này có giao diện/flags của Antigravity; không đổi tên mọi lệnh `gemini` sang `agy` rồi giả định chúng tương đương.

`agy models` liệt kê Gemini 3.8 Flash high/medium/low và một số model ngoài Gemini. Probe chọn cụ thể `gemini-3.8-flash-high` để xác nhận đúng họ Gemini, không dùng default model chưa biết. Đây là model của phép thử, chưa phải lựa chọn bắt buộc cho coding. Danh sách model có thể thay đổi.

## Phép thử đã chạy

Một script Python stdlib dùng subprocess truyền kết quả tuần tự:

1. `agy -p` trả chính xác marker `OTO_AGY_BRIDGE_OK`.
2. `codex exec` nhận marker đó, xác minh và trả `OTO_CODEX_REVIEW_OK`.
3. `agy -p` nhận xác nhận Codex, trả `OTO_HANDOFF_RECEIVED`.

Cả ba kết quả khớp và script exit 0. Mỗi lời gọi giới hạn 60 giây; AGY print timeout 50 giây. Probe dùng thư mục tạm ngoài repo, yêu cầu không dùng tools/đọc/sửa code; `agy` ở mode plan + sandbox, Codex ở read-only. Không dùng cờ bypass permissions. Không cài app, chạy test iOS, commit/push hoặc truy cập phiên YouTube.

Codex trước đó báo đã đăng nhập ChatGPT. Probe loại bỏ các biến môi trường API key thông dụng khỏi process con, không cấu hình API trả phí hay đọc/export credentials. Việc thử không đo số quota còn lại hoặc xác nhận tất cả thiết lập billing của tài khoản.

Môi trường sandbox của agent ban đầu chặn log trong `~/.gemini` và cổng localhost cần cho Antigravity. Các lệnh liệt kê model và chạy probe được thực hiện sau approval cho quyền chạy ngoài sandbox đó; không thay đổi quyền mặc định toàn hệ thống.

## Giao diện để dựng runner

- Antigravity: `-p` nhận prompt, `--output-format json` trả kết quả có cấu trúc, `--print-timeout` đặt giới hạn mỗi lượt. Phiên đa lượt có thể dùng conversation ID hoặc stream-json theo tài liệu chính thức.
- Codex: `exec` nhận prompt qua stdin, `--sandbox read-only` cho reviewer, `--output-schema` định nghĩa output, `--output-last-message` lưu câu trả lời cuối.
- Runner tạo task -> gọi AGY -> chạy checks -> cố định revision -> gọi Codex -> chuyển findings về AGY -> kiểm tra lại. Review sạch và checks đạt mới commit/push theo AGENTS.
- AGY headless cần permissions cho từng tool/command phù hợp. Nếu gặp permission không có sẵn thì dừng để xử lý, không bật auto-approve toàn bộ.
- Rules/task phải được đưa rõ vào AGY; chưa kiểm chứng Antigravity tự nạp `GEMINI.md` hoặc cú pháp import của Gemini CLI.

## Phần chưa triển khai

Chưa có runner persistent, task backlog executable, enforce cutoff 05:00, checkpoint/resume, review đúng diff hay commit/push tự động. Oto vẫn cần checkout Git riêng để tránh repo cha. Các nội dung này không được coi là đã xong vì probe marker thành công.

Tài liệu: [Antigravity headless](https://antigravity.google/docs/cli/headless/), [Codex structured review/repair loops](https://developers.openai.com/cookbook/examples/codex/build_iterative_repair_loops_with_codex).
