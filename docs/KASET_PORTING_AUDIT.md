# Oto — audit tái sử dụng Kaset

Khảo sát read-only ngày 2026-11-08 tại Kaset revision `fd88b69`. Oto lúc khảo sát chỉ có `AGENTS.md` và `PROJECT_PLAN.md`. Chưa chuyển code, chưa build iOS, chưa đo tỷ lệ tái sử dụng. Đường dẫn bên dưới tính từ gốc repo Kaset.

## Module nên xem trước

| Thành phần | Bằng chứng trong code | Hướng đưa vào Oto |
| --- | --- | --- |
| Domain models | `Sources/Kaset/Models/Song.swift`, `Album.swift`, `Artist.swift` | Tận dụng ý nghĩa dữ liệu, kiểm tra cả dependency graph; Song có thêm music-video/playlist metadata và CoreTransferable, không coi cả Models là pure core |
| Synced lyrics / LRC | `Sources/Kaset/Models/SyncedLyrics.swift` | Đã có line/word timing, lookup và LRC parser; chọn phần domain, kiểm tra Sendable và ID/timestamp behavior |
| Provider contract | `Sources/Kaset/Services/Lyrics/LyricsProvider.swift` | Đã có protocol Sendable và LyricsSearchInfo; đánh giá isolation của dữ liệu trả về trong core mới |
| LRCLIB | `Sources/Kaset/Services/Lyrics/Providers/LRCLibProvider.swift` | Có `/api/search` client; cần injected transport, timeout/error model, matching chặt và bỏ force unwrap trước khi port |
| YTM timed lyrics | `Sources/Kaset/Services/Lyrics/Providers/YTMusicSyncedProvider.swift` | Gọi `getTimedLyrics`; bằng chứng Kaset không chỉ có YTM plain lyrics; cần xác minh response hiện tại qua explorer |
| Resolver | `Sources/Kaset/Services/Lyrics/SyncedLyricsService.swift` | Đã có priority selection, generation chống stale fetch và cache; tách `SettingsManager.shared`/romanization khỏi lõi |
| Metadata API | `Sources/Kaset/Services/API/YTMusicClient.swift` + extensions/parsers | Client đang `@MainActor`, phụ thuộc concrete AuthService/WebKitManager, APICache, diagnostics và key resolver; cần adapter/session boundary, không copy rồi hứa chạy nguyên trạng |
| Auth | `Sources/Kaset/Services/Auth/AuthService.swift` | Có lifecycle/logout/generation protection đáng học; không copy state chứa credential thành UI model mới |
| Cookie/session | `Sources/Kaset/Services/WebKit/WebKitManager.swift` + extensions | Có observers, restore, archive serialization và account fences; đánh giá lại bằng iOS Keychain/data-store lifecycle |
| Playback/queue | `Sources/Kaset/Services/Player/PlayerService.swift` + extensions | Logic lớn, liên quan SettingsManager/AuthService và native/web queue; chỉ trích policy đã kiểm chứng, không đem toàn bộ service vào Oto |
| Web bridge | `Sources/Kaset/Views/SingletonPlayerWebView+*.swift` | Dùng tham khảo control/state recovery; singleton và DOM injection macOS không chứng minh iOS background support |
| Tests | `Tests/KasetTests/SyncedLyricsTests.swift`, `LyricsParserTests.swift`, `PlayerServiceQueueTests.swift` và các race tests | Port invariants/fixtures đã sanitize tương ứng module được chọn, không mang UI/macOS harness sang |

## Các vấn đề đã thấy cần tránh mang theo

- LRCLibProvider đang có force unwrap URLComponents/first result, dùng URLSession.shared, chọn duration gần nhất mà chưa có confidence threshold. Không sửa Kaset ngoài phạm vi; xử lý trong bản port và thêm test hành vi có ý nghĩa.
- SyncedLyricsService có quan hệ SettingsManager/romanization; chỉ nhìn `import Foundation` không đủ kết luận độc lập nền tảng.
- `Package.swift` Kaset đặt macOS 15.4 và sản phẩm executable; không phải một shared library có thể add thẳng vào target iOS.
- ADR `docs/adr/0001-webview-playback.md` của Kaset mô tả quyết định macOS. Các kết luận DRM/feature parity/background ở đó không được coi là kết quả thử iOS.
- Chính sách lưu cookie file trong DEBUG của Kaset giải quyết vấn đề sandbox/Keychain macOS cụ thể, không phải mặc định lưu credentials của Oto.

## Phần không chuyển trong MVP

YouTubeClient và giao diện YouTube video, window/menubar/AppKit controllers, macOS fullscreen/keyboard routing, Sparkle/update packaging, AI/Gemini, automation macOS và toàn bộ extension system. Video ID vẫn có thể cần làm định danh bài YTM; loại bỏ sản phẩm YouTube video không có nghĩa xóa mọi field tên video.

## Quy trình port theo lát nhỏ

1. Tạo core package/test target độc lập, chuẩn bị mock models và clock/transport contracts.
2. Chọn một model/parser/queue policy, liệt kê dependency rồi mới copy/adapt. Giữ license/copyright MIT của Kaset khi dùng phần code đáng kể; nguồn có `LICENSE` copyright 2025 sozercan.
3. Với parser/API thay đổi: xác minh bằng API explorer tái sử dụng, sanitize fixture ngoài repo trước khi add. Khảo sát hiện tại chỉ đọc source nên chưa gửi live request.
4. Run tests module đó, compile iOS, kiểm tra không kéo AppKit/settings singleton vào core.
5. Port session/backend sau khi có probe; giữ test regressions về stale request, logout và queue authority.

Không ước lượng phần trăm reuse từ số file/import. Khi bắt đầu implementation, ghi module nào đã compile/test trên iOS và module nào còn chưa xác minh.
