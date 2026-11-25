# Rà luồng phát trên nhánh khảo sát

- Phiên ngày 2026-11-25, múi giờ Asia/Ho_Chi_Minh.
- Đã commit và push mốc người dùng xác nhận ổn, `4089cf0` trên `origin/spike/ytm-avplayer-hls`.
- Thay đổi cục bộ sau mốc gồm token riêng cho mỗi lần lấy URL, kiểm tra item hiện tại khi nhận sự kiện hết bài và kiểm tra lại bài kế trước khi nạp đệm.
- `git diff --check` sạch. **BUILD VERIFIED** cho Debug generic iOS 17 có cờ khảo sát, dùng biến ký ad hoc cho Python nhúng. Build này chỉ dùng để xác minh compile và đóng gói.
- **UNIT VERIFIED** cho luồng Home đến phát nhạc với backend giả lập và nhóm Up Next. Lượt chạy toàn bộ ghi hai assertion lỗi ở `NowPlayingArtworkTests`, sau đó không tiến thêm ở test đăng xuất `SessionStore` và đã được ngắt. Chưa đối chiếu hai vấn đề này với checkpoint. Bản sửa cục bộ chưa commit hay push.
- Video dài tự dừng và bài đầu sau khi mở lại app đều **NOT VERIFIED** trên máy thật trong phiên này. ADR 0002 ghi lần đo trước mất 5,9–7,1 giây để lấy URL và thêm 4–6 giây tới khi có tiếng.
- Bước đo tiếp theo trên máy thật khi có quyền chạy: dùng cùng một bài Video dài, ghi thời điểm dừng, trạng thái AVPlayer và ý định phát. Sau khi thoát hẳn rồi mở lại app, đo từ lúc bấm phát tới khi lấy xong URL và từ lúc có URL tới khi bắt đầu phát.
