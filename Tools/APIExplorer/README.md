# APIExplorer công khai

Explorer chỉ gửi request đọc công khai, không đọc cookie/Keychain hoặc phiên trình duyệt. Chỉ xuất số lượng shape endpoint; không lưu raw response, tiêu đề cá nhân hoặc credentials.

```sh
python3 Tools/APIExplorer/home_shapes.py --operation search --client-version 1.20261104.00.00 --output /tmp/oto-public-shapes.json
```

Client version phải lấy từ adapter đang kiểm tra, không mặc định đây là version hợp lệ vĩnh viễn. Probe search ngày 2026-11-16 ghi nhận 41 watchEndpoint chỉ có videoId và 8 watchEndpoint có cả videoId/playlistId. Điều này xác nhận video ID và playlist context có thể đồng thời tồn tại; không chứng minh mọi renderer Home hoặc dữ liệu tài khoản có cùng schema. Probe Home bị timeout và không được tính là xác minh.

Request/shape mới cần thêm thành operation trong explorer. Không dùng script này để thực hiện mutation hoặc đưa cookie vào CLI.

Lyrics dùng `--operation lyrics-browse --video-id <public-video-id>` để kiểm tra shape của `next` rồi `browse` bằng phiên công khai. Explorer chỉ xuất số lượng `timed_lyrics_model`, `lyrics_browse_endpoint` và `plain_lyrics_shelf`; không in browse ID hay nội dung lời. Probe công khai ngày 2026-11-17 ghi nhận đường `next → browse` và một `plain_lyrics_shelf` cho bài mẫu; chưa xác nhận shape timed lyrics bằng tài khoản thật.

Dùng `--operation library-albums` và `--operation library-artists` để kiểm tra hai browse ID ứng viên. Probe công khai chỉ thấy một `sectionListRenderer` ở mỗi phản hồi và không thấy hàng nội dung. Kết quả này chưa xác minh schema của thư viện đã đăng nhập.

Có thể đưa phản hồi Library đã loại dữ liệu nhạy cảm vào explorer ở chế độ ngoại tuyến. Giữ tệp đầu vào ngoài repo. Explorer chỉ xuất số lượng renderer, đường dẫn cấu trúc của hàng và cờ có trang tiếp theo.

```sh
python3 Tools/APIExplorer/home_shapes.py --operation library-albums \
  --library-shape-input /tmp/sanitized-library-albums.json --output /tmp/oto-library-albums-shape.json
```

Dùng `library-artists` cho phản hồi danh sách nghệ sĩ.

Dùng `--operation lyrics-next --video-types --video-id <public-video-id>` để đếm
loại media trên các `watchEndpoint` khớp chính xác ID. Endpoint thiếu loại
được tính là `unknown`. Kết quả chỉ xác minh metadata công khai.
