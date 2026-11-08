# Oto — thử nghiệm đăng nhập và phát nhạc

Trạng thái ngày 2026-11-08: **NOT TESTED**. Đây là checklist nghiệm thu, không phải báo cáo thành công. Chưa có probe app, chưa đọc phiên Google và chưa chạy trên máy người dùng.

## Mục đích

Trả lời bằng thực nghiệm: một backend iOS có thể đăng nhập phiên riêng, phát YouTube Music cho người có Premium, tiếp tục chuyển bài khi khóa máy và nhận điều khiển hệ thống không? Kết quả macOS, simulator hoặc phát file thử native không trả lời thay câu hỏi này.

Apple mô tả category playback/Background Modes cho app media và `allowsInlineMediaPlayback` cho inline/fullscreen. Suy luận kỹ thuật của dự án: cần thêm bằng chứng cho chuỗi web player + WebKit process + queue + iOS lifecycle cụ thể. [Media setup](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback), [inline playback](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/allowsinlinemediaplayback).

## Chuẩn bị

- Máy chính: iPad Gen 9 và iPhone 13 Pro Max. Người dùng cho biết đang ở iOS/iPadOS 27 và có YouTube Premium; ghi phiên bản/build thực tế khi bắt đầu.
- Ghi Xcode/SDK, git revision của probe, configuration Debug/Release, adapter, network type, trạng thái pin/Low Power Mode, output route và việc debugger có attached không.
- Chạy bản ký đúng thiết bị. Xin quyền trước việc cài/chạy app nếu phiên làm việc chưa có ủy quyền này. Người dùng tự thao tác login, không gửi secrets cho agent.
- Không chép cookie Kaset. Không dump raw response/cookie/localStorage để debug. Test account mutations không thuộc probe này.
- Chuẩn bị ít nhất ba bài khả dụng có metadata/duration và queue rõ; không giả định mọi nội dung dùng cùng cơ chế DRM.
- Tạo trace event dùng monotonic timestamp và session/track IDs giả hoặc opaque, state, route, command và acknowledgement; không ghi headers, body, account IDs hoặc cookie.
- Trace lưu trong container của app, đọc bằng cách xuất có kiểm soát. Không dùng hardcoded `/tmp`; xóa instrumentation trước chia sẻ build.

## Tách ba phép thử

1. **Native baseline:** âm thanh thử được cấp quyền qua AVPlayer để kiểm tra audio session, interruptions và Now Playing. PASS ở đây không phải PASS của YTM.
2. **Session probe:** xác minh luồng sign-in và phiên mà metadata adapter/playback adapter thật sự dùng. Không chọn embedded OAuth chỉ vì Kaset có login WebView; không giả định ASWebAuthenticationSession chia sẻ cookie với WKWebView. [Google OAuth browser policy](https://developers.google.com/identity/protocols/oauth2/policies#use-secure-browsers).
3. **YTM playback probe:** adapter ứng viên + một coordinator + queue ba bài + điều khiển debug. Chưa cần Home, gradient hoặc lyric UI hoàn chỉnh.

## Ma trận bắt buộc

Ký hiệu: NT = NOT TESTED; ghi PASS/FAIL cùng evidence khi chạy. Ngưỡng thời gian/số lần dưới đây là tiêu chí thử của dự án, không phải SLA của Apple/Google.

| ID | Kịch bản | Kỳ vọng | iPad Gen 9 | iPhone 13 Pro Max |
| --- | --- | --- | --- | --- |
| A1 | Login, cancel, thử lại | Phiên hợp lệ hoặc lỗi rõ, không mắc loading | NT | NT |
| A2 | Quit/relaunch, mở khi đã khóa rồi unlock | Restore phiên đúng; không báo logout chỉ vì credential tạm chưa đọc được | NT | NT |
| A3 | Logout khi request cũ đang chạy | Không hồi sinh phiên/cache hoặc metadata tài khoản | NT | NT |
| P1 | Play/pause/seek/next/previous foreground | Engine acknowledgement đúng; không phát chồng | NT | NT |
| P2 | Khóa máy 20 phút | Audio không dừng ngoài buffering/interruption được giải thích | NT | NT |
| P3 | Khóa trước khi bài kết thúc | Ít nhất ba lần tự chuyển bài trong nền, queue đúng | NT | NT |
| P4 | Chuyển sang app khác 20 phút | Tiếp tục audio và chuyển bài khi màn hình app không hiện | NT | NT |
| P5 | Lock Screen/Control Center play/pause/next/seek | Lệnh được xác nhận, artwork/progress theo track thật | NT | NT |
| P6 | Tai nghe Bluetooth/remote nếu có | Pause/next đúng, route đổi có trace; thiếu phụ kiện ghi NT | NT | NT |
| P7 | Rút/ngắt tai nghe; reconnect | Không bất ngờ phát ra loa; resume theo intent | NT | NT |
| P8 | Siri/cuộc gọi/interruption | Không tự bật nhạc khi người dùng đã pause; resync state | NT | NT |
| P9 | Mất mạng, phục hồi; Wi-Fi đổi mạng nếu có | Retry giới hạn, lỗi rõ; không skip lặp vô hạn | NT | NT |
| P10 | Spam next/seek, completion event trễ | Event bài cũ không đè bài mới, advance đúng một lần | NT | NT |
| P11 | 50 lần chuyển bài + 20 lần mở/đóng player | Không tăng memory vô hạn, không giữ webview/observer không dùng | NT | NT |
| P12 | iPad rotate, split window, resize | Playback không restart; UI dùng được ở cửa sổ hẹp | NT | N/A |
| P13 | Low Power Mode, pause lâu rồi resume | State đúng, không cần animation/keepalive để phát | NT | NT |
| P14 | Web process terminate hoặc app restore | Fail/recover có giới hạn; không giả đang phát | NT | NT |

Lặp lại P2/P3/P5 ít nhất hai phiên trên mỗi máy, gồm một bản Release-like không attached debugger. Force quit là hành động chấm dứt app, không phải phép thử bắt app tiếp tục phát.

Chỉ điền PASS cho điều kiện đã quan sát được. NT vì không có phụ kiện/hệ điều hành cũ phải thành giới hạn hỗ trợ công bố; không đổi sang PASS vì simulator chạy được.

## Mẫu báo cáo mỗi lần chạy

```text
Run ID / ngày:
Device model / OS build:
Probe revision / adapter / build config / debugger:
Network / route / Low Power Mode:
Case ID / số lần:
Expected / observed:
Result: PASS | FAIL | NOT TESTED
Trace event range (đã sanitize):
Root cause hoặc giả thuyết cần đo tiếp:
Follow-up:
```

## Quyết định sau thử

- **Pass:** auth và các case cốt lõi A1–A3/P1–P5/P7–P13 đạt trên cả hai máy; P6 cần phụ kiện để claim Bluetooth. Ghi rõ P14 đã kiểm chứng phần nào. Chốt backend và queue authority bằng ADR có evidence.
- **Fail:** ghi lỗi, reproducible steps, trace và phạm vi ảnh hưởng. Cho phép khảo sát tiếp trong adapter nhỏ; không tiếp tục xây toàn bộ app như thể playback đã xong.
- Nếu không đạt background auto-next hoặc phiên đăng nhập phù hợp, báo chủ dự án để đổi hướng. Không dùng silent track/private API hoặc thay nguồn nhạc mà không thống nhất.

Qua hai máy chỉ xác nhận hai cấu hình. Hỗ trợ rộng iOS/iPadOS 17+ cần build/deployment validation, kiểm tra API availability và runtime trên OS cũ khi có thiết bị; kết quả chưa có vẫn ghi NT.
