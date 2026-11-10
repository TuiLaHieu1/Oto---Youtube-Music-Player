# PLAYBACK-REMOTE-001: Điều khiển Từ xa (AirPods & Lock Screen Media Controls)

## 1. Hiện tượng & Vấn đề (Problem Statement)
1. **Tai nghe Bluetooth / AirPods:** Nhấn đúp hoặc nhấn 1 lần trên thân tai nghe (AirPods stem) không phản hồi lệnh Play/Pause vì hệ thống chưa đăng ký handler cho `MPRemoteCommandCenter.togglePlayPauseCommand`.
2. **Màn hình khóa (Lock Screen):** Chưa hiển thị Artwork (`MPMediaItemPropertyArtwork`) trong `MPNowPlayingInfoCenter`.
3. **Previous / Next Track:** Cần kiểm chứng lệnh `nextTrackCommand` và `previousTrackCommand` được định tuyến chuẩn xác tới `QueueManager` mà không bị nuốt lệnh.

## 2. Cách tái hiện (Reproduction Steps)
1. Kết nối tai nghe AirPods với iPhone 13 Pro Max.
2. Bật một bài hát trên Oto và khóa màn hình.
3. Nhấn 1 lần vào thân AirPods $\to$ Quan sát xem nhạc có dừng/tiếp tục không.
4. Quan sát widget Màn hình khóa $\to$ Kiểm tra xem có hiển thị ảnh bìa (Artwork) và các nút Previous / Next hay không.

## 3. Kết quả mong đợi (Expected Behavior)
- Bấm 1 lần trên AirPods: Gọi `togglePlayPauseCommand` $\to$ Chuyển đổi Play/Pause mượt mà.
- Bấm 2 lần trên AirPods: Chuyển sang bài kế tiếp (`nextTrackCommand`).
- Bấm 3 lần trên AirPods: Quay về bài trước (`previousTrackCommand`).
- Lock Screen hiển thị đầy đủ Artwork (tải bất đồng bộ và set `MPMediaItemArtwork`), Title, Artist, Album, thanh Scrubber thời gian thực.
- Không hiển thị các nút tua podcast $\pm30$s.

## 4. Kết quả thực tế (Actual Behavior)
- `NowPlayingManager` hiện chỉ đăng ký `playCommand` và `pauseCommand`, thiếu hoàn toàn `togglePlayPauseCommand`.
- `updateNowPlaying` chưa set `MPMediaItemPropertyArtwork`.

## 5. Bằng chứng hiện có (Evidence)
- **Thiết bị mục tiêu:** iPhone 13 Pro Max (iOS 18.x).
- **Mã nguồn:** `Oto/Services/Audio/NowPlayingManager.swift:57-99`.
- **Thiếu sót:** `commandCenter.togglePlayPauseCommand.isEnabled = true` chưa có.

## 6. Phạm vi cho phép (In Scope)
- `Oto/Services/Audio/NowPlayingManager.swift`
- `Oto/ViewModels/PlayerViewModel.swift`
- `Tests/OtoTests/` (Unit test cho `NowPlayingManager` command hooks)

## 7. Ngoài phạm vi (Out of Scope)
- Không can thiệp vào `SingletonPlayerWebView` logic.
- Không thay đổi Home feed hoặc UI màn hình chính.

## 8. Tiêu chí nghiệm thu (Acceptance Criteria)
- [ ] Bổ sung `togglePlayPauseCommand` vào `NowPlayingManager`.
- [ ] Nạp artwork bất đồng bộ cho `MPMediaItemArtwork` với kích thước phù hợp (tránh quá tải bộ nhớ).
- [ ] Unit tests cho remote command handlers trong `OtoTests`.
- [ ] SwiftLint strict 0 lỗi.
- [ ] Build generic iOS và iPhone 13 Pro Max thành công.
- [ ] **Kiểm thử trên iPhone 13 Pro Max thật:**
  - [ ] Nhấn AirPods 1 lần $\to$ Play/Pause.
  - [ ] Nhấn AirPods 2 lần $\to$ Next.
  - [ ] Lock Screen hiển thị artwork và metadata chuẩn.

## 9. Bảng nghiệm thu hoàn tất (Sign-off Table)

| Tiêu chí nghiệm thu | Trạng thái | Bằng chứng kiểm tra |
| :--- | :---: | :--- |
| `togglePlayPauseCommand` registered & tested | NOT TESTED | ... |
| `MPMediaItemArtwork` integration | NOT TESTED | ... |
| Unit tests (`xcodebuild test`) | NOT TESTED | ... |
| SwiftLint strict | NOT TESTED | ... |
| Physical iPhone 13 Pro Max & AirPods | NOT TESTED | Bắt buộc test trước khi đánh dấu DONE |
