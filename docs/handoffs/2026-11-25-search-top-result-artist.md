# Tên nghệ sĩ của kết quả Search hàng đầu

- Phiên ngày 2026-11-25, múi giờ Asia/Ho_Chi_Minh.
- Commit cục bộ `fadce6a` trên `spike/ytm-avplayer-hls`. Mốc trên GitHub là `4089cf0`. Phần sửa playback từ phiên trước vẫn ở worktree.
- Parser giữ tên nghệ sĩ dạng chữ trong phụ đề và bổ sung credit từ thẻ lớn nếu dòng cùng ID thiếu credit. Giữ loại Song/Video và các metadata khác của dòng.
- API Explorer kiểm tra Search công khai, chỉ xuất số đếm cấu trúc. Hai ca lỗi được kiểm tra với dữ liệu mẫu.
- **UNIT VERIFIED** và **BUILD VERIFIED** trên simulator iPhone 13 Pro Max. 24 test gồm MusicSearchTests, UpNextWrapperTests và PlaybackRepairTests đều qua. `git diff --check` sạch.
- **NOT VERIFIED** trên thiết bị thật. Bước tiếp theo là tìm lại bài từng gặp lỗi, phát từ ô lớn và đối chiếu tên nghệ sĩ trên trình phát.
