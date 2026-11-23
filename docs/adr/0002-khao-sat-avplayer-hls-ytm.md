# ADR-0002: Khảo sát phát HLS YouTube Music bằng AVPlayer
Ngày: 2026-11-23
Trạng thái: **Đề xuất (khảo sát)**. Chỉ trên nhánh `spike/ytm-avplayer-hls`, sau cờ `OTO_STREAM_PROBE`. Chưa có số đo.

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
