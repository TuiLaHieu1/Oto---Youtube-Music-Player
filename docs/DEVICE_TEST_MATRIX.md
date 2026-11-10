# Oto — Device Test Matrix (Ma trận Kiểm thử Thiết bị)

Tài liệu này xác định ranh giới kiểm thử giữa **iOS Simulator** và **Thiết bị thật (iPhone 13 Pro Max / iPad)** đối với các tính năng của Oto. Mọi báo cáo nghiệm thu phải đối chiếu theo ma trận này.

---

## 1. Bảng phân định năng lực kiểm thử

| Nhóm tính năng / Kịch bản | iOS Simulator | iPhone 13 Pro Max (Thiết bị chính) | iPad (Thiết bị phụ) | Tiêu chuẩn Bằng chứng (Evidence Required) |
| :--- | :---: | :---: | :---: | :--- |
| **Logic Hàng đợi & State Machine** | Đầy đủ | Hỗ trợ | Hỗ trợ | `OtoCoreTests` 100% pass (`swift test`) |
| **Fake Backend Recovery & Decoupling** | Đầy đủ | Hỗ trợ | Hỗ trợ | `OtoTests` 100% pass (`xcodebuild test`) |
| **Next / Previous Track** | Chỉ test UI nút bấm | **Bắt buộc** | Tùy chọn | Video hoặc trace log chuyển track mượt mà |
| **Scrubber & Tua nhạc (Seek)** | Tương đối | **Bắt buộc** | **Bắt buộc** | Video thao tác kéo thanh tiến trình không giật |
| **Lock Screen (Màn hình khóa)** | **Không hỗ trợ** (Simulator không có Lock Screen media controls đầy đủ) | **Bắt buộc** | **Bắt buộc** | Screenshot Lock Screen hiển thị đúng Artwork, Title, Artist, Scrubber |
| **AirPods / Tai nghe Bluetooth** | **Không hỗ trợ** | **Bắt buộc** | Tùy chọn | Log trace nhận sự kiện AVRCP (Play, Pause, Next, Previous) |
| **Phát nhạc nền (Background Audio)** | Không có giá trị chứng minh (Watchdog simulator khác iOS thật) | **Bắt buộc** | **Bắt buộc** | Trace log chạy liên tục > 3 phút khi tắt màn hình hoặc chuyển app |
| **Tài khoản Google & Home Feed cá nhân** | Chỉ dùng Mock/Public data | **Bắt buộc** | **Bắt buộc** | Log sanitized hiển thị các shelf (Quick Picks, Listen Again) từ tài khoản thật |
| **DRM / Widevine Audio Playback** | Hạn chế | **Bắt buộc** | **Bắt buộc** | Âm thanh phát rõ ràng qua loa/tai nghe, không rè hoặc mất tiếng |
| **Độ khớp UI Atelier Light × Spectrum Dark** | Kiểm tra layout sơ bộ | **Bắt buộc** | **Bắt buộc** | Screenshot đối chiếu với frame Figma trên màn hình 13 Pro Max |

---

## 2. Quy tắc đánh dấu trạng thái (Evidence Grading)

1. **PASS:**
   - Chỉ được gán cho các mục trên thiết bị thật khi **đã nạp app lên máy, thực hiện thao tác và thu thập được bằng chứng cụ thể** (Log sanitized, screenshot màn hình khóa, hoặc video thao tác).
2. **CODE COMPLETE:**
   - Áp dụng khi mã nguồn đã hoàn tất, compile thành công (`BUILD SUCCEEDED`), unit test đạt 100%, SwiftLint strict 0 lỗi, nhưng **chưa thể cắm dây nạp vào iPhone thật**.
3. **NOT TESTED:**
   - Bắt buộc ghi nhận rõ nếu chưa thực hiện kiểm thử trên phần cứng thực tế.
4. **FAIL:**
   - Xuất hiện lỗi runtime (ví dụ: mất tiếng, Lock Screen hiển thị sai nút $\pm30$s thay vì Next/Previous, AirPods bấm không phản hồi, WebContent crash liên tục).

---

## 3. Quy trình xác thực Playback & Lock Screen trên iPhone thật

Khi cắm iPhone 13 Pro Max:
1. **Kiểm tra Audio Session & Lock Screen:**
   - Bật một bài hát bất kỳ.
   - Khóa màn hình iPhone.
   - Quan sát Lock Screen widget: phải có Title, Artist, Album Art, thanh tiến trình (progress bar), nút Play/Pause và nút Previous/Next (không phải nút tua tiến/lùi 30 giây).
2. **Kiểm tra Điều khiển Phần cứng (AirPods / EarPods):**
   - Bấm 1 lần: Tạm dừng / Tiếp tục phát.
   - Bấm 2 lần: Chuyển bài kế tiếp (`NextTrackCommand`).
   - Bấm 3 lần: Quay lại bài trước (`PreviousTrackCommand`).
3. **Kiểm tra Background Continuity:**
   - Mở Safari hoặc một ứng dụng khác nặng (ví dụ: Camera/Maps).
   - Đảm bảo nhạc vẫn phát nền liên tục, không bị ngắt ngang sau 30 giây.
