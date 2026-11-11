# Trạng thái hiện tại của Oto

Cập nhật: 2026-11-11 15:32 (Asia/Ho_Chi_Minh)

Tài liệu này là nguồn trạng thái ngắn gọn cho người dùng và các coding agent. Chỉ ghi `PASS` khi có bằng chứng tương ứng; source code hiện diện hoặc build thành công không thay thế kiểm thử thiết bị/tài khoản.

## Repository

| Mục | Giá trị |
| --- | --- |
| Git root | `/Users/hieu/Code/Oto` |
| Branch | `main` |
| Local HEAD | `d34d0d2` — `docs: thêm quy tắc cô lập regression` |
| `origin/main` | `d34d0d2` |
| Local so với remote | Đồng bộ tại thời điểm cập nhật |
| Working tree | **Không sạch — đang có bản sửa regression chưa commit** |

Không reset, checkout, commit hoặc trộn các thay đổi đang dở nếu chưa xác định owner và phạm vi task.

## Mục tiêu ổn định hiện tại

Hoàn thành một vertical slice có bằng chứng:

```text
Đăng nhập hợp lệ
→ Home nhận dữ liệu cá nhân
→ Speed Dial không dùng fallback giả
→ chọn bài
→ audio bắt đầu
→ metadata đúng
→ pause/resume
→ previous/next
→ seek
→ mở/đóng Fullscreen Player không mất session
```

Không tiếp tục mở rộng UI hoặc feature cho đến khi vertical slice này ổn định.

## Trạng thái chức năng

| Khả năng | Trạng thái | Bằng chứng hiện có | Bằng chứng còn thiếu |
| --- | --- | --- | --- |
| Speed Dial hiển thị đúng gợi ý tài khoản | **OWNER OBSERVED** | Người dùng báo đã nhìn thấy Speed Dial đúng sau `9e92412` | Trace tài khoản đã sanitize và kiểm thử lặp lại |
| Parser nhận `musicSpeedDialShelfRenderer` | **CODED** | Parser và fixture hiện có | Focused test trên working tree hiện tại chưa được ghi nhận PASS |
| Không lấy section thường làm Speed Dial giả | **CODED, NOT VERIFIED** | Test mới `missingSpeedDialMustNotStealFirstSection` đang ở working tree | Chạy test và ghi kết quả |
| Phát bài từ Home/Speed Dial | **REGRESSION / FAIL theo quan sát người dùng** | Người dùng báo nhạc không phát sau bản sửa Speed Dial | Sanitized playback trace và failing regression test |
| Pause/resume/next/previous/seek | **NOT VERIFIED trên revision hiện tại** | Từng hoạt động trước thay đổi auth/Speed Dial theo quan sát người dùng | Focused tests và device smoke test |
| Cookie domain scoping | **CODED, NOT VERIFIED** | Có implementation và test mới trong working tree | Focused test, review bảo mật và build |
| Authorization header | **CODED, NOT VERIFIED** | Có implementation và test mới trong working tree | Focused test và sanitized request evidence |
| Lock Screen/AirPods/background | **NOT DEVICE VERIFIED** | Source có remote-command wiring | Test trên thiết bị thật với authorization |
| UI theo PDF | **PARTIAL** | Đã có các lượt theme/component/layout | Screenshot comparison theo từng màn hình |

## Regression đang mở

### REG-001 — Speed Dial đúng nhưng playback không phát

| Mục | Trạng thái |
| --- | --- |
| Triệu chứng | Sau khi Speed Dial hiển thị đúng, chọn bài không phát được |
| Last-known-good candidate | `051e9a6` (parent của bản auth/Speed Dial); **chưa được bisect xác nhận** |
| First-bad candidate | `9e92412`; **chưa được bisect xác nhận** |
| Root cause | Chưa chứng minh |
| Khu vực nghi ngờ | Cookie scoping, auth header, session completion, playback bridge/generation |
| Không được làm | Thêm workaround UI, sửa queue hoặc mở rộng feature trước khi xác định boundary đầu tiên sai |
| Phép đo tiếp theo | Chạy focused regression tests và trace đường tap song → load request → WebKit state/generation |

## Thay đổi đang dở trong working tree

Các file sau đang được sửa nhưng chưa commit và chưa được nghiệm thu:

```text
Oto.xcodeproj/project.pbxproj
Oto/Presentation/Auth/AuthView.swift
Oto/Services/API/YTMusicClient.swift
Oto/Services/API/YTMusicParsers+SpeedDial.swift
Oto/Services/WebKit/CookieStorage.swift
Oto/Services/WebKit/PlayerBridgeScript.swift
Oto/ViewModels/PlayerViewModel.swift
Tests/OtoTests/AuthenticationAndSpeedDialRegressionTests.swift (mới)
```

Phạm vi này đang trộn auth, catalog parser, playback bridge, player state, Xcode project và test. Trước khi commit phải tách hoặc chứng minh vì sao từng file cần thiết cho cùng root cause.

## Kiểm thử của working tree hiện tại

| Kiểm tra | Trạng thái |
| --- | --- |
| `git diff --check` | Chưa ghi nhận trong tài liệu này |
| Focused auth/Speed Dial regression tests | **NOT RUN / NOT RECORDED** |
| OtoCore tests | **NOT RUN / NOT RECORDED cho working tree hiện tại** |
| OtoTests | **NOT RUN / NOT RECORDED cho working tree hiện tại** |
| SwiftLint strict | **NOT RUN / NOT RECORDED cho working tree hiện tại** |
| Generic iOS build | **NOT RUN / NOT RECORDED cho working tree hiện tại** |
| iPhone 13 Pro Max | **NOT TESTED cho working tree hiện tại** |
| iPad 9th generation | **NOT TESTED cho working tree hiện tại** |

Không kế thừa kết quả test của commit cũ để đánh dấu working tree hiện tại là PASS.

## Task cần làm theo thứ tự

1. **BASELINE** — đóng băng feature/UI, xác nhận diff hiện tại, last-known-good và first-bad revision.
2. **EVIDENCE** — thu trace đã sanitize, xác định boundary đầu tiên khiến playback khác hành vi cũ.
3. **FAILING TESTS** — chạy và hoàn thiện test tái hiện cookie/session/Speed Dial/playback regression.
4. **MINIMAL FIX** — mỗi patch sửa một boundary, tối đa ba production files; không sửa lan sang UI/Xcode project.
5. **REGRESSION** — chạy Home-to-Playback smoke regression và các test tập trung.
6. **REVIEW & DELIVERY** — review độc lập P0/P1, chạy full verification một lần, commit/push theo task và cập nhật tài liệu này.

## Bước tiếp theo duy nhất

Review working-tree diff hiện tại theo `REG-001`, chạy focused regression tests đang có, và xác định thay đổi tối thiểu nào thực sự cần thiết. Chưa tiếp tục UI và chưa commit/push bản sửa regression cho đến khi bước này có kết quả.

