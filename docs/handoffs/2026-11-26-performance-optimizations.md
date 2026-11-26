# Tối ưu RAM và dữ liệu phát nhạc

Mốc đầu là `942b905` trên nhánh `spike/ytm-avplayer-hls`. Chủ dự án duyệt năm tối ưu và yêu cầu giữ việc nạp Python sớm. Chủ dự án tự build và thử âm thanh sau.

## Phần đã triển khai

- Nạp trước tối đa một bài kế trên mạng được hệ thống xác định là không đắt và không bật Low Data Mode. Player phụ xin bộ đệm trước 5 giây, đây là gợi ý cho AVFoundation. Bỏ item khi pause, đổi mạng/chất lượng, hàng đợi đổi bài kế, chuyển sang file local, đăng xuất hoặc có cảnh báo bộ nhớ. Callback cũ được chặn bằng revision.
- Tắt Video sẽ lấy audio, giữ vị trí tua gần nhất và ý định phát mới nhất. Token, generation và trạng thái kết thúc chặn kết quả cũ. Nếu lấy audio thất bại, tiếp tục HLS với độ phân giải giới hạn để giữ bài đang phát.
- Ảnh bìa local được giải mã ngoài MainActor theo kích thước hiển thị. Cache dùng chung có giới hạn 100 ảnh và mức cost 20 MiB, xóa khi cảnh báo bộ nhớ. Ảnh lớn giữ mức tối đa 768 pixel như nguồn hiện tại.
- Thêm chất lượng tự động, cao và tiết kiệm trong Cài đặt, có tiếng Việt/Anh. Mặc định tự động chọn audio nhỏ hơn trên mạng di động/Low Data Mode. Chế độ tiết kiệm chọn audio M4A/AAC thấp nhất hiện có. Nếu nguồn chỉ có một mức thì dùng mức đó. Cache kiểm tra chất lượng, kết quả cũ không ghi đè cache của chính sách mới. Lựa chọn áp dụng ở lần lấy URL tiếp theo.
- Router cập nhật tiến độ mỗi 200 ms khi trình phát mở rộng ở foreground, mỗi giây khi thu nhỏ, pause hoặc ở nền. Khi đang chờ phát ở foreground vẫn kiểm tra mỗi 200 ms. Sự kiện hết bài tiếp tục dùng notification riêng. Bỏ cập nhật runtimeDuration khi giá trị giống nhau.

Hàm warm của Python và lời gọi warm lúc mở app giữ nguyên. Kiểm tra AST xác nhận thân hàm warm giống revision đầu.

## Kiểm tra và review

- CODED cho năm mục trên.
- Swift 6 typecheck theo danh sách Sources thực tế của target Oto, với và không có `OTO_STREAM_PROBE`. Dùng iOS SDK và module phụ thuộc đã có trên máy. Lệnh này chỉ kiểm tra kiểu dữ liệu.
- UNIT VERIFIED cho bốn kiểm tra Python thuần dữ liệu về chọn chất lượng, bỏ định dạng có video, fallback AAC, nguồn chỉ một mức, tái sử dụng warm và tách pool theo chất lượng. Chạy `PYTHONDONTWRITEBYTECODE=1 python3 Tools/StreamProbe/tests/test_audio_quality.py`, dùng yt-dlp đã có trong Vendor, không gọi mạng.
- String Catalog JSON, plist dự án và `git diff --check` hợp lệ.
- Tự review đã sửa callback prefetch chạy sau đăng xuất, cache chất lượng cũ ghi đè kết quả mới, item nạp trước sai bài kế, và callback seek của item cũ khi chuyển luồng. Sửa capture mạnh trong observer video để tránh giữ view qua observer.
- Review độc lập đã được yêu cầu nhưng bị chặn vì hết hạn mức trước khi trả findings. Chưa có kết quả độc lập để chấp nhận hoặc bác bỏ.
- Build app, Swift unit suite, Home-to-Playback smoke, UI, thiết bị và đo RAM/data thực tế đều NOT VERIFIED theo giới hạn kiểm tra của chủ dự án. Chưa có số liệu tiết kiệm thực đo.
- Python extraction đã chạy có thể hoàn tất sau khi hủy yêu cầu. Revision chặn khôi phục cache/item cũ, nhưng không ngắt ngay HTTP đang chạy trong Python.

## Bàn giao

Các thay đổi thuộc lượt tối ưu này được commit và push theo quyền đã được chủ dự án cấp. Đối chiếu hash và kết quả push trong phản hồi hoàn tất và Git.

Khi chủ dự án tự thử, kiểm tra chuyển Video/audio trong lúc pause và tua, đổi bài nhanh, hết bài tự chuyển đúng một lần, phát qua Home/Search, thu nhỏ/mở lại player, Wi-Fi sang di động/Low Data Mode, ba mức chất lượng, và ảnh bìa nhạc local. Đo RAM/data trên cùng danh sách bài trước khi kết luận mức cải thiện.
