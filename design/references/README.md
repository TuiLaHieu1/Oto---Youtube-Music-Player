# Oto — ảnh và video tham khảo

Thư mục dành cho đầu vào thiết kế. Chưa có ảnh/video nào được cung cấp tại thời điểm tạo tài liệu này.

## Nên cung cấp

1. iPhone Now Playing: bố cục artwork, title, controls, progress, nền.
2. iPhone lyrics: kích thước chữ, highlight, spacing, trạng thái cuộn tay.
3. Mini player và chuyển cảnh sang full player.
4. iPad player + lyrics ở màn hình rộng và cửa sổ hẹp.
5. Home/search/library nếu có yêu cầu rõ về các màn hình này.
6. Một ví dụ không thích, giải thích vì sao.

Không cần đủ tất cả để bắt đầu. Ảnh rõ nội dung và chú thích cụ thể hữu ích hơn số lượng nhiều. Một recording ngắn giúp mô tả gesture/animation mà ảnh tĩnh không diễn đạt được.

## Cách lưu và chú thích

Đặt tên dễ đọc, ví dụ `iphone-now-playing-01.png`, `ipad-lyrics-01.png`, `player-transition-01.mov`. Đây là tên gợi ý, chưa phải file đang tồn tại.

Mỗi ảnh/video có thể đi kèm file Markdown cùng tên hoặc một đoạn mô tả trong chat:

```text
Tên file hoặc link:
Nguồn / app / phiên bản (nếu biết):
Thiết bị hoặc kích thước cửa sổ:
Màn hình / trạng thái (playing, paused, loading...):
Thích: tối đa ba điểm cụ thể
Không thích / muốn đổi:
Hành vi tương tác cần giữ:
Mức độ: bắt buộc | cảm hứng | chỉ tham khảo
Được phép dùng làm asset trong app? Có | Không | Chưa rõ
```

Nếu dùng video, thêm mốc thời gian của đoạn cần học, ví dụ `00:04–00:07: kéo player xuống, artwork chuyển về mini player`.

## Cách agent sử dụng

- Đọc chú thích trước, không coi mọi chi tiết trong ảnh là requirement.
- Đề xuất một hướng thiết kế thống nhất trước khi xây toàn bộ màn hình. Mockup là đề xuất cho tới khi người dùng chọn.
- Tách yếu tố bắt buộc, yếu tố cảm hứng và chi tiết hệ điều hành. Không hứa giống pixel trên mọi OS/kích thước.
- Cần mô tả cả paused, buffering, error, no artwork, title dài, lyrics unavailable và Dynamic Type lớn, dù ảnh tham khảo chỉ có happy path.
- Không tự lấy artwork/logo/font trong ảnh để đóng gói làm asset. Chỉ dùng tài sản có nguồn và quyền sử dụng phù hợp.
- Che tài khoản, notification và dữ liệu cá nhân trước khi lưu. Video lớn có thể giữ ngoài repo và tham chiếu đường dẫn; không thêm Git LFS/dependency chỉ để chứa ảnh tham khảo.

Sau khi chốt hướng, agent viết design spec có màu, typography, spacing, component states, behavior và fallback. Chưa có design spec cuối cùng ở giai đoạn này.
