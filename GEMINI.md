# Oto — Gemini Implementation Entry Point & Rules

Gemini thông qua Antigravity CLI (`agy`) là implementer chính của Oto. Codex là independent reviewer.
Mỗi task phải tuân thủ nghiêm ngặt các quy tắc dưới đây.

---

## 1. Context & Task Files Bắt buộc Đọc

Vì Antigravity CLI không tự động mở rộng cú pháp import `@./file.md`, trước khi thực hiện bất kỳ task nào, implementer bắt buộc phải đọc trực tiếp:
- `@AGENTS.md` (Quy tắc kiến trúc, bảo mật, concurrency Swift 6, token/credential policy).
- `@GEMINI.md` (Quy chuẩn thực thi, runtime evidence gate, quy trình 3 giai đoạn).
- `@docs/AGENT_WORKFLOW.md` (Quy trình phối hợp Gemini - Codex, handoff và review).
- `@docs/PLAYBACK_FEASIBILITY.md` (Ranh giới kỹ thuật WebKit, DRM và CoreAudio).
- `@docs/DEVICE_TEST_MATRIX.md` (Ma trận kiểm thử thiết bị thật vs Simulator).
- `@docs/tasks/TASK-ID.md` (Task packet cụ thể của công việc hiện tại).

---

## 2. Runtime Evidence Gate (Bắt buộc)

> [!CRITICAL]
> **Compile success và Mock Unit test pass KHÔNG CHỨNG MINH tính năng runtime hoạt động trên thiết bị thật.**

1. `xcodebuild` thành công hoặc `swift test` 100% pass với `MockPlaybackBackend` chỉ chứng minh tính đúng đắn của logic state machine trong RAM. Nó **không chứng minh** WebKit background audio không bị iOS watchdog hủy, không chứng minh Lock Screen / Dynamic Island nhận metadata, không chứng minh AirPods Bluetooth AVRCP điều khiển được nhạc, và không chứng minh cookie YouTube Music session hợp lệ.
2. Với mọi lỗi hoặc tính năng liên quan đến phần cứng, WebKit audio, remote controls hoặc tài khoản:
   - Khi hoàn thành code và unit test, chỉ được ghi: `CODE COMPLETE (DEVICE TEST REQUIRED)`.
   - Chỉ được ghi `PASS` khi có bằng chứng thực tế từ iPhone/iPad (log console đã sanitize, video, hoặc trace).
3. **Tuyệt đối không dùng** các từ ngữ như *"đã fix triệt để"*, *"hoàn tất 100%"*, hoặc *"đã chạy tốt"* khi hàng mục kiểm thử thiết bị thật còn mang trạng thái `NOT TESTED`.

---

## 3. Quy trình 3 Giai đoạn Bắt buộc

**Không sửa code ngay lập tức khi nhận yêu cầu.**

### Giai đoạn 1: Chẩn đoán & Xác định Root Cause
1. Đọc kỹ code path liên quan và vẽ lại luồng sự kiện thực tế:
   ```text
   Hardware Event (AirPods / Lock Screen / Car)
     │
     ▼
   iOS Media Session (MPRemoteCommandCenter / AVAudioSession)
     │
     ▼
   WKWebView / navigator.mediaSession / JS Bridge
     │
     ▼
   PlayerViewModel
     │
     ▼
   PlaybackStateMachine
     │
     ▼
   PlaybackBackend (WebKit / Native)
   ```
2. Xác định rõ **State Owner** (ai nắm quyền thay đổi state, counter, generation).
3. Chỉ ra bằng chứng cụ thể cho Root Cause (dòng code, log error, race condition).
4. Liệt kê rõ các giả thuyết chưa được xác minh (nếu có).

### Giai đoạn 2: Thay đổi Tối thiểu & Kiểm thử
1. Chọn giải pháp nhỏ nhất để xử lý trực tiếp root cause mà không gây tác dụng phụ.
2. Viết test regression (chứng minh test fail trước khi fix hoặc kiểm thử đúng luồng biên).
3. Triển khai code theo nguyên tắc bảo toàn kiến trúc (Swift 6 strict concurrency, `@MainActor`, zero force-unwrap).
4. Chạy kiểm tra:
   - Focused unit tests;
   - Toàn bộ `OtoTests` và `OtoCoreTests`;
   - SwiftLint strict;
   - Build generic iOS.

### Giai đoạn 3: Nghiệm thu & Báo cáo Bằng chứng
Kết thúc task bằng bảng nghiệm thu 3 cột minh bạch:

| Acceptance Criterion | Trạng thái (PASS / FAIL / NOT TESTED) | Evidence |
| :--- | :---: | :--- |
| Unit tests & Regression tests | PASS / FAIL | Lệnh và kết quả chạy test |
| SwiftLint strict (0 errors) | PASS / FAIL | Lệnh và số lượng file lint |
| Xcodebuild generic iOS | PASS / FAIL | Kết quả build |
| Kiểm thử trên iPhone 13 Pro Max | PASS / FAIL / NOT TESTED | Log sanitized / Video / Screenshot |
| Lock Screen / AirPods remote control | PASS / FAIL / NOT TESTED | Bằng chứng thao tác thực tế |

Không commit hoặc push nếu chưa hoàn tất các bước kiểm tra code hoặc chưa có xác nhận từ reviewer/chủ dự án. Không tự ý mở rộng phạm vi ra ngoài task packet được giao.
