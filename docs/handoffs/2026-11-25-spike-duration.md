# Đo bài dài gần gấp đôi và có đoạn im

- Phiên ngày 2026-11-25, múi giờ Asia/Ho_Chi_Minh. Mốc local trước khi thêm trace là `f21b26f` trên `spike/ytm-avplayer-hls`.
- Chủ dự án báo bài khoảng 3 phút hiện khoảng 6 phút và còn khoảng 3 phút im trước khi chuyển bài. Chưa có trace từ máy thật. Chủ dự án yêu cầu chuẩn bị trước, chưa cài lên iPhone.
- Bản Debug khảo sát ghi `mediaDuration` từ yt-dlp và `itemDuration`, `position`, `control`, `video` từ AVPlayer. Sự kiện `itemEnded` ghi lúc AVPlayer báo hết bài. Các trường thêm chỉ gồm số đo và cờ.
- **BUILD VERIFIED** cho Debug generic iOS với ký ad hoc framework Python. Kiểm tra cú pháp Python và `git diff --check` đều qua.
- **UNIT VERIFIED** cho 18 test thuộc PlaybackRepairTests và PlaybackIntentSyncTests trên simulator iPhone 13 Pro Max, gồm luồng Home đến phát nhạc với backend giả lập. Đo lỗi gấp đôi trên máy thật vẫn **NOT VERIFIED**.
- Log chủ dự án gửi từ iPhone xác nhận luồng audio có thời lượng nguồn 221 giây, còn AVPlayer báo 442,35 giây ngay lúc bắt đầu phát. Log kết thúc ở thao tác Pause tại giây 16, chưa có sự kiện hết bài. Mỗi dòng khảo sát được ghi qua cả unified log và stdout.
- Bản sửa dùng thời lượng nguồn làm điểm kết thúc AVPlayerItem khi timeline audio khảo sát nằm trong khoảng 1,95–2,05 lần thời lượng nguồn. Cùng mốc được gửi lên thanh tiến độ. Sửa định dạng log khi thời lượng còn chưa biết.
- **BUILD VERIFIED** bản sửa Debug generic iOS. **UNIT VERIFIED** với 20 test trên simulator, gồm hai ca thời lượng mới và luồng Home đến phát nhạc với backend giả lập. Bản sửa chưa được cài lên máy thật và chưa push.
- Bước đo tiếp theo: phát lại bài gặp lỗi, kiểm tra đồng hồ hiện khoảng 3:41 và chờ app tự sang bài kế. Sau khi đo, bỏ trace tạm nếu không còn cần.
