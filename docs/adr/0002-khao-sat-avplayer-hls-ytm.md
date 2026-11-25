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

### 2026-11-25 · Bước 2 và phát mọi bài qua AVPlayer
- **Bước 2 trên iPhone (chủ dự án thao tác):** Pause, về Home, sau 47,2 giây bấm Play trong Control Center khi `appState=2`; AVPlayer vào trạng thái phát sau 0,15 giây, vị trí tăng 18,09 → 21,01 khi app vẫn ở nền. Chủ dự án xác nhận Pause lâu rồi Play phát tiếp được. `DEVICE VERIFIED` cho ca này.
- Router bản khảo sát giờ phát mọi bài YouTube Music bằng AVPlayer, lấy trước URL bài kế, lấy URL mới khi Play sau lúc URL gần hết hạn, quay về WebKit khi lỗi. Cờ `OTO_STREAM_PROBE` bật sẵn cho cấu hình Debug trên nhánh khảo sát.
- Lượt thử tự động 2 bài (iPhone, không cookie): bài 1 lấy URL 5,9–7,1 giây; bài 2 lấy trước 4,0–5,2 giây; Next dùng URL đã lấy trước (`cached=1`). AVPlayer cần thêm khoảng 4–6 giây để có tiếng sau khi tạo item. Thử tắt `automaticallyWaitsToMinimizeStalling` thì có tiếng ngay nhưng bị đứng khoảng 5 giây giữa bài, nên giữ mặc định.
- Một lượt gặp lỗi DNS tạm thời trong Python (`gaierror`, yt-dlp báo `apiPage`); đo lại ngay sau đó DNS/TCP/HTTPS của Python đều bình thường. Python không đi qua URLSession nên nhạy hơn với mạng chập chờn; khi lỗi, bài quay về WebKit.
- Chưa đo: tự chuyển bài khi màn hình tắt, Next/Previous từ Lock Screen/AirPods, Pause trên 6 giờ, ca mở app sau Pause.
### 2026-11-26 · Bỏ WebKit trong bản khảo sát và tối ưu tốc độ
- Theo yêu cầu của chủ dự án, bản có cờ không dùng WebKit để phát nữa: router dùng `NoopPlaybackBackend`, không tạo `PlayerWebViewContainer`. Bỏ đường quay về WebKit. Khi lỗi, router báo `onError`: 150 (bài không phát được, tự chuyển bài), -1009 (lỗi mạng), -1001 (quá 40 giây chưa có URL). Watchdog tải bài tăng từ 12 lên 45 giây.
- Chọn client (đo trên Mac, 3 video): `visionos` 3,8–4,0 giây cho 3/3 video; mặc định 9,8–16,4 giây; `tv_samsung` 6,9–10,1 giây; `android_vr`, `tv`, `web_music`, `ios`, `mweb`, `web_safari` lỗi ở một số video; `player_skip webpage` làm hỏng một số video. `oto_resolve.py` thử hồ sơ `fast` (`visionos`) trước, lỗi thì thử hồ sơ mặc định.
- Thêm handler `requests` (requests, urllib3, idna, charset-normalizer thuần Python) để dùng lại kết nối. Trên iPhone với mạng chậm, mỗi kết nối TCP+TLS mới tốn 3–5 giây. Khởi động yt-dlp lúc mở app (`warm`) mất 0,84 giây. Lấy URL trên iPhone: 1,5–3,1 giây khi mạng ổn, có lượt 13,2 giây khi mạng chậm.
- Nạp sẵn bài kế: AVPlayer thứ hai (tắt tiếng) giữ item của bài kế và `preroll`. Một `AVPlayerItem` không được gắn sang AVPlayer khác (gắn sang làm app crash với `NSInvalidArgumentException`), nên khi Next thì đổi vai hai player. Đo trên iPhone: Next tới bài đã nạp sẵn có trạng thái phát sau 0,20–0,21 giây; Next tới bài chưa nạp sẵn mất 5–7 giây.
- Chưa đo: bài nạp sẵn có phát tiếng ra ngoài hay giành Now Playing không (cần tai người nghe), tự chuyển bài khi tắt màn hình, Next/Previous từ Lock Screen/AirPods, Pause trên 10 phút, mở app sau Pause.
