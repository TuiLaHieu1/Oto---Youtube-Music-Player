# ADR-0002: Khảo sát phát HLS YouTube Music bằng AVPlayer
Ngày: 2026-11-23
Trạng thái: **Đề xuất (khảo sát)**. Chỉ trên nhánh `spike/ytm-avplayer-hls`, sau cờ `OTO_STREAM_PROBE`. Cổng 1 (lấy trực tiếp) không đạt với một bài; xem "Kết quả đo".

## Bối cảnh
- Với backend WKWebView, Play từ Control Center hoặc AirPods sau khi Pause vài giây ở nền chỉ có hiệu lực khi mở Oto. Xem `docs/handoffs/OTO_YTM_REMOTE_RESUME_2026-11-20.md`.
- Đối chứng trên iPhone 13 Pro Max với cùng HLS mẫu của Apple: WKWebView tối giản tái hiện lỗi, còn AVPlayer nhận Play ở nền sau gần 28 giây Pause và phát tiếp. Đây là DEVICE VERIFIED cho HLS mẫu, không phải cho YouTube Music.
- Theo wiki yt-dlp (chỉ để đặt giả thuyết): client web với user-agent Safari có thể trả HLS chưa cần PO token khi tải stream, và tài khoản Premium không cần PO token khi tải stream. Chưa xác minh với `WEB_REMIX` trên Oto.

## Điều khoản liên quan
- Điều khoản YouTube (bản 5/1/2022): người dùng được xem/nghe cho mục đích cá nhân, phi thương mại, nhưng không được "truy cập, sản xuất lại, tải xuống, … phát … bất kỳ Nội dung nào trừ khi được Dịch vụ ủy quyền rõ ràng" và không được tránh né tính năng "giới hạn việc sử dụng Dịch vụ hoặc Nội dung".
- Chính sách API YouTube, mục I.7 (không tách audio/video), I.9 (không phát bằng player chạy nền không hiển thị), I.14 (không dùng công nghệ ngoài YouTube API Services để truy cập nội dung). Endpoint `player` của Innertube không phải API chính thức, nhưng các mục này thể hiện lập trường của YouTube.
- Không tìm thấy nguồn công khai nào cho phép app bên thứ ba phát stream YouTube Music bằng AVPlayer, kể cả khi dùng cá nhân và có Premium.

## Quyết định
Chủ dự án đã đọc các điều khoản trên, hiểu rủi ro và chọn khảo sát cho mục đích cá nhân, với giới hạn trong `AGENTS.md` (mục ngoại lệ khảo sát). Đây không phải kết luận rằng cách phát này được phép.

## Cổng đo
1. **M1/M2 (quan sát):** phân loại `hasHLS`, `validNoHLS`, `unplayable(status)`, `schemaMismatch`, `requestError(401/403/429/transport)`. Không có HLS thì dừng.
2. **Một bài:** Pause, về Home 30 giây, Play một lần từ Control Center. Đạt khi vị trí media tăng trước mốc foreground và chủ dự án nghe thấy tiếng.
3. **Ma trận:** Pause 10 phút (Control Center, AirPods), tự chuyển bài ở nền, đổi mạng, giả hết hạn URL ở nền, mở app sau Pause vẫn Pause, không hồi quy Next/Previous, Repeat One, nhạc import.

## Hệ quả
- Nếu một cổng không đạt: ghi số đo, chuyển trạng thái thành **Từ chối**, giữ WebKit.
- Nếu đạt cả ba: chỉ ghi kết quả. Làm bản thật cần kế hoạch và quyết định riêng; WebKit vẫn là đường dự phòng.

## Kết quả đo
### 2026-11-25 · iPhone 13 Pro Max · bản `e9d80fc` có cờ · tài khoản Premium · một bài thường
| Nguồn | outcome | sabr | mp4Direct | mp4Cipher | webmDirect | webmCipher |
| --- | --- | --- | --- | --- | --- | --- |
| M1 trang (`WEB_REMIX`) | validNoHLS | true | 0 | 1 | 0 | 3 |
| M2 native, user-agent iPhone | validNoHLS | true | 0 | 2 | 0 | 4 |
| M2 native, user-agent Safari Mac | validNoHLS | true | 0 | 2 | 0 | 4 |

- Cả ba đường đều không có HLS và không có M4A với `url` trực tiếp. Audio chỉ có `signatureCipher`, phần còn lại là SABR.
- Kết luận: với client `WEB_REMIX` và phiên Premium, Oto không lấy được nguồn AVPlayer phát được mà không giải mã chữ ký. Giải mã đang bị cấm trong `AGENTS.md`, nên hướng "lấy trực tiếp trong app" dừng ở cổng 1. Đây là `ACCOUNT VERIFIED` cho một bài; chưa đo Vevo và bài chỉ dành cho Premium, nhưng hành vi này thuộc về client nên khó khác theo bài.
- Không có request nào làm đổi dữ liệu tài khoản. Log chỉ có số đếm.

### Lựa chọn còn lại (chờ chủ dự án)
1. **Server dùng yt-dlp** (như source tham khảo `vibe-music`): yt-dlp giải mã và chọn client; Oto phát URL của server bằng AVPlayer. Cần server chạy khi nghe.
2. **Đổi quy tắc, cho phép giải mã trong app** (chạy JS player của YouTube bằng JavaScriptCore như plugin `yt-dlp-apple-webkit-jsi`): không cần server, nhưng tự bảo trì khi YouTube đổi.
3. **Giữ WebKit**, ghi giới hạn "Pause lâu phải mở Oto", có thể thêm nút mở app rồi phát.

### 2026-11-25 · Hướng yt-dlp nhúng trong app (chủ dự án duyệt)
- Nhúng Python 3.14 (BeeWare b14, sha256 đã kiểm), yt-dlp 2026.11.23, yt-dlp-ejs 0.8.0 và certifi vào bản Debug có cờ; tải bằng `Tools/StreamProbe/fetch_vendor.sh` vào `Vendor/` (gitignore). Bản không cờ không có Python.
- Plugin `yt-dlp-apple-webkit-jsi` chạy JS trong **WKWebView** và chờ trên run loop chính, nên sẽ bị treo khi app ở nền như backend hiện tại. Không dùng. Thay bằng provider `oto-jsc` (`Tools/StreamProbe/python/yt_dlp_plugins/extractor/oto_jsc.py`) gọi C API của JavaScriptCore qua ctypes, chạy trong tiến trình app. Provider chỉ chạy script do yt-dlp-ejs dựng.
- Trên Mac (chỉ JavaScriptCore, không node/deno): lấy được itag 140 `audio/mp4` mp4a.40.2 khoảng 130 kbps trong khoảng 7 giây, tải thử 64 KB trả 206 `audio/mp4`.
- **Bước 1 trên iPhone 13 Pro Max (không cookie):** `YtdlpProbe outcome=ok format=140 abr=130 expiresIn=21595 hasN=true seconds=6.6–9.1`; `YtdlpFetch status=206 bytes=65536 type=audio/mp4 seconds=0.3`. Đạt: yt-dlp chạy được trong app iOS và URL tải được từ IP của iPhone.
- Bước 2 (AVPlayer, Pause → Home → Play từ Control Center/AirPods) và bước 3 (lấy URL khi app ở nền) chưa đo.
