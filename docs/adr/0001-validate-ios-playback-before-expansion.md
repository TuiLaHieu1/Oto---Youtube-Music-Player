# ADR-0001: Kiểm chứng playback iOS trước khi mở rộng sản phẩm

Ngày: 2026-11-08

Trạng thái: **Đề xuất**. Backend chưa được chọn, chưa có evidence máy thật. Mục tiêu dùng cá nhân trước và khả năng chia sẻ nhóm nhỏ do chủ dự án xác nhận.

## Bối cảnh

Oto cần trải nghiệm music player native, lấy nhạc YouTube Music và tiếp tục hoạt động khi khóa màn hình. Kaset có web playback trên macOS, nhưng app lifecycle, WebKit behavior và hệ thống audio trên iOS khác. Tài liệu ban đầu đã khẳng định phát nền/DRM trước khi thử.

## Hướng đề xuất

Tách `PlaybackBackend` khỏi SwiftUI và dùng một coordinator sở hữu session/queue. Tạo thử nghiệm nhỏ cho auth, playback và remote commands; dùng iPad Gen 9 cùng iPhone 13 Pro Max làm máy nghiệm thu đầu tiên. Backend WKWebView chỉ là ứng viên, không phải quyết định được chứng minh.

Thực hiện ma trận trong `../PLAYBACK_FEASIBILITY.md`, đo với debugger detached và ghi kết quả trung thực. Chỉ chốt backend/queue authority bằng ADR tiếp theo khi có evidence. Native audio test asset chứng minh baseline iOS, không thay thế thử YouTube Music.

## Các lựa chọn chưa chốt

- WKWebView adapter: gần hướng Kaset, nhưng auth/content/background/auto-next phải được kiểm chứng riêng.
- Native AVPlayer: dùng cho test asset được cấp quyền; không giả định có URL/DRM/license tích hợp YouTube Music phù hợp để dùng làm production backend.
- Deep link sang YouTube Music: có thể là phương án đổi mục tiêu sau trao đổi, không đáp ứng player Oto độc lập như hiện tại.

## Hệ quả

Foundation/mock UI có thể tiến hành trước. Không dùng thời gian xây toàn bộ Home/Library/animation khi nền tảng playback còn chưa đạt. Nếu probe thất bại, báo chủ dự án nguyên nhân và lựa chọn tiếp theo; không lặng lẽ giảm tiêu chí hoặc dùng keepalive workaround.

Kiến trúc adapter thêm một ít code nhưng giúp test state/lyrics/queue độc lập, giữ phạm vi port Kaset nhỏ và thay backend khi dữ liệu thực tế yêu cầu.
