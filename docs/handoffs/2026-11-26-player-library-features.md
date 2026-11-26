# Tính năng phát và thư viện

- Phiên ngày 2026-11-26, múi giờ Asia/Ho_Chi_Minh. Mốc trước loạt thay đổi này trên `spike/ytm-avplayer-hls` là `ebef978`.
- Hẹn giờ ngủ trong menu của trình phát, gồm 15, 30, 60 phút và hết bài. Lịch sử Home giữ tối đa 30 bài theo phiên, ghi khi trình phát xác nhận đang phát.
- Nhạc đã nhập từ Files có thể chỉnh tên, nghệ sĩ và ảnh bìa. Phần lời đồng bộ cho chỉnh từng 0,5 giây và lưu theo bài và nguồn.
- Gỡ một dấu backtick thừa ở lời gọi parser Home continuation mà lần build trước của phiên đã báo lỗi cú pháp.
- Theo yêu cầu, lượt này chỉ kiểm tra tĩnh. Swift typecheck qua với và không có cờ khảo sát. Cú pháp hai test mới, String Catalog và `git diff --check` cũng qua. Phần build, unit test, phát âm thanh và thiết bị **NOT VERIFIED**.
- Khi tự thử, ưu tiên hẹn giờ hết bài (gồm khóa màn hình), lịch sử sau khi mở lại app, thêm bài vào playlist YouTube, chỉnh và bấm tua theo lời, đổi ảnh bìa rồi phát một bài đã nhập. Sau khi các luồng này ổn, đo lại thời gian bấm phát đến khi có tiếng ở lần mở app đầu tiên.

## Đổi thao tác thêm bài sang playlist YouTube

- Chủ dự án cung cấp OAuth Client ID iOS và duyệt GoogleSignIn-iOS. Đã thêm SDK, URL callback, màn hình chọn playlist YouTube trong trình phát và thao tác ghi qua YouTube Data API. Đã gỡ giao diện và logic playlist lưu trên máy. Dữ liệu playlist cũ trong UserDefaults chưa xóa để tránh mất dữ liệu ngoài ý muốn.
- Swift parser, typecheck riêng lớp API, plist, String Catalog và `git diff --check` đều qua. **NOT VERIFIED** cho build app và ghi playlist thật từ phía agent. Chủ dự án đã tự cấu hình Google Cloud và báo đăng nhập hoạt động sau khi xử lý cảnh báo ứng dụng chưa xác minh.

## Sửa nút thao tác bài hát trong playlist

- Chủ dự án cho biết màn hình Google báo ứng dụng chưa xác minh. Sau khi hoàn tất bước xác minh, đăng nhập hoạt động. Không có bằng chứng lỗi trong SDK đăng nhập nên giữ luồng đang chạy được.
- Dấu `…` trong hàng bài hát trước đây chỉ là ảnh nằm trong nút phát. Đã tách thành menu độc lập. Menu playlist có phát bài, phát tiếp theo, thêm vào hàng đợi, thêm vào playlist YouTube và chia sẻ.
- Swift parser và `git diff --check` qua. Chưa build hay thử UI từ phía agent theo yêu cầu chủ dự án. Kết quả commit/push được ghi trong Git.
