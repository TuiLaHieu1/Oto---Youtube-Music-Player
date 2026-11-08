# Oto (音) — Kế hoạch triển khai

Cập nhật: 2026-11-08. Trạng thái: kế hoạch kỹ thuật; chưa có app hay kết quả thử phát nhạc trên thiết bị.

## 1. Mục tiêu và quyết định sản phẩm

Oto là app nghe YouTube Music cho iPhone/iPad, có giao diện SwiftUI, mini player, màn hình Now Playing và lời đồng bộ từ nhiều nguồn. Lấy cảm hứng từ cách tương tác của Apple Music nhưng có nhận diện riêng. Không xây phần YouTube video của Kaset.

Theo chủ dự án: dùng trên máy cá nhân trước; có thể chia sẻ cho nhóm nhỏ sau. Chưa triển khai App Store, TestFlight, backend thương mại, thanh toán hoặc analytics. Thiết bị thử chính: iPad Gen 9 và iPhone 13 Pro Max; OS được người dùng cung cấp là iOS/iPadOS 27, tài khoản có YouTube Premium. Khi thử cần ghi lại phiên bản/build thực tế của từng máy.

Deployment target **iOS 17 / iPadOS 17** đã được chủ dự án đồng ý, gồm giao diện dự phòng trên máy/OS cũ. Đây là mốc hỗ trợ mục tiêu, chưa phải tuyên bố đã kiểm chứng mọi máy. iPad Gen 9 là chuẩn hiệu năng thấp hơn; iPhone 13 Pro Max dùng kiểm tra cử chỉ và màn hình ProMotion. Không yêu cầu 120 Hz, Dynamic Island hoặc hiệu ứng iOS mới để sử dụng tính năng cốt lõi.

Đầu vào mới trong `docs/PRODUCT_INPUTS.md`: UI cơ bản trước, ảnh thiết kế bổ sung sau; tập trung trải nghiệm lyrics Anh/Việt và tham khảo hành vi Kaset. Khôi phục queue, mở ở Home và chưa chủ động phát khi cold launch. Foundation có thể dùng Home shell đơn giản; feed Home đầy đủ vẫn sau vertical slice. Agents được chọn thứ tự task; phát nền và lyric đúng là tiêu chí chất lượng đã ghi trong bảng Q.

Vận hành: Gemini code chính, Codex review; cả hai chỉ dùng hạn mức đăng nhập của gói hiện có, không phát sinh phí; từng task code hoàn tất checks/review phải commit và push vào repo chủ dự án đã chỉ định. Chú thích và báo cáo dùng tiếng Việt đơn giản. Phiên tự động qua đêm dừng chậm nhất 05:00 sáng giờ Việt Nam hoặc sớm hơn khi hết hạn mức; luôn lưu handoff trước khi kết thúc. Ghi cutoff có ngày cụ thể khi bắt đầu phiên, không tự khởi động lại sau cutoff. Xem `docs/AGENT_WORKFLOW.md`.

## 2. Điều cần sửa trong kế hoạch trước

- Không có bằng chứng để hứa tái sử dụng 60–70% code, giảm nửa dung lượng, hoặc hoàn thành trong năm tuần. Đo theo từng module và cổng nghiệm thu.
- `AVAudioSession` và Background Modes là cấu hình phát nền; `allowsInlineMediaPlayback` quyết định phát inline/fullscreen. Chúng chưa chứng minh YouTube Music trong WKWebView tiếp tục chạy, tự chuyển bài và nhận remote commands khi khóa máy. [Apple: media playback](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback), [inline playback](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/allowsinlinemediaplayback).
- Không giả định DRM/web player trên macOS hoạt động giống trên iOS. Premium không phải bằng chứng tương thích của backend mới.
- Không dùng silent audio, vòng lặp giữ tiến trình, private API hoặc player video thu nhỏ để che vấn đề phát nền.
- Đăng nhập web/cookie và OAuth là hai hướng khác nhau; OAuth thành công không tự tạo phiên YouTube Music trong WKWebsiteDataStore. Google không cho gửi luồng OAuth vào embedded user-agent do ứng dụng kiểm soát. Khảo sát luồng phù hợp trước khi chọn. [Google OAuth policies](https://developers.google.com/identity/protocols/oauth2/policies#use-secure-browsers).
- Kaset đã có LRCLIB, mô hình synced lyrics và provider timed lyrics của YTM. Không mặc định YTM chỉ có lời tĩnh; không xây lại toàn bộ lyric engine.
- Musixmatch/NetEase chưa nằm trong MVP. Chỉ thêm provider khi có cách truy cập và quyền sử dụng phù hợp; không dùng token lấy từ app khác hay scraper làm mặc định.

## 3. Stack đề xuất

| Phần | Lựa chọn | Quy tắc |
| --- | --- | --- |
| Ngôn ngữ | Swift, language mode 6, strict concurrency | Pin toolchain theo project khi tạo; máy khảo sát có Xcode 27.2 / Swift 6.4.2 |
| App | Universal iOS/iPadOS Xcode project, SwiftUI | Một app target; không copy executable target macOS |
| Logic dùng chung | Một local Swift Package `OtoCore` | Domain, queue, lyrics, test doubles; không kéo AppKit/WebKit vào core |
| UI | Observation, NavigationStack, NavigationSplitView | Layout theo kích thước cửa sổ, không chỉ theo loại máy |
| Network | URLSession, Codable và parser phù hợp payload | Client API nhận transport/session provider qua dependency injection |
| Playback | `PlaybackBackend` + một adapter thử nghiệm | WKWebView là ứng viên khảo sát; chưa chốt engine sản xuất |
| Hệ thống audio | AVFAudio/AVFoundation, MediaPlayer | Audio session, Now Playing, remote commands, route/interruption |
| Credentials | Security.framework Keychain, WebKit data store nếu cần | Không cần dependency KeychainAccess; cache không chứa credentials |
| Lưu trữ | File cache có giới hạn + UserDefaults | SwiftData chỉ thêm khi có nhu cầu truy vấn/migration rõ ràng |
| Lyrics | LRCLIB + YTM nếu endpoint được xác minh | Provider protocol; hiển thị nguồn và độ chính xác đồng bộ |
| Kiểm thử | Swift Testing, URLProtocol/fake transport, fake playback clock | Unit test không đăng nhập thật; thử phát nền cần máy thật |
| Chất lượng | SwiftLint / SwiftFormat có version pin | Thiết lập ở bước foundation; không mặc định đã cài |

Không thêm thư viện bên thứ ba trong foundation. Không có server trung gian lưu phiên Google. ActivityKit, Metal, cloud sync, CarPlay và widget chưa cần.

## 4. Kiến trúc và quyền sở hữu state

```text
SwiftUI screens -> @MainActor observable application stores
                              |
           +------------------+-------------------+
           |                  |                   |
      MusicCatalog       PlaybackCoordinator   LyricsResolver
           |                  |                   |
      YTMusic adapter    PlaybackBackend       LyricsProvider[]
           |                  |                   |
  SessionProvider +      iOS adapter         LRCLIB / verified YTM
  HTTP transport         (feasibility spike)
```

- App composition root tạo dependency và sở hữu một playback session xuyên suốt các scene. Không bắt buộc global singleton. Sheet player chỉ quan sát cùng state, không tạo engine riêng.
- `OtoCore`: domain types, queue item có ID riêng cho mỗi lần xuất hiện, queue policy, lyric models/LRC parser, matching và clock policy. Giá trị qua actor boundary phải `Sendable` đúng nghĩa.
- `MusicCatalog`: home/search/details/library; tách anonymous và account-scoped data. `SessionProvider` không xuất credentials lên UI. Không đem AuthService/WebKitManager macOS vào core.
- `PlaybackCoordinator`: nguồn sự thật của lệnh và queue. Engine gửi trạng thái thực tế có session generation, track ID và sequence; event cũ không đổi bài hiện tại.
- State tối thiểu: idle, preparing, playing, paused, buffering, interrupted, failed. Tách user intent khỏi observed state; play chỉ thành playing sau xác nhận engine.
- Command async: play, pause, seek, next, previous, setQueue, setRepeat, setShuffle. Capability flags quyết định control nào khả dụng; lỗi trả có kiểu.
- Lệnh seek có request ID; bỏ progress cũ trong lúc seek, đồng bộ lại khi engine xác nhận. Không suy ra hết bài chỉ từ elapsed time; advance đúng một lần theo completion event.
- Clock nội suy dùng monotonic clock từ mốc engine xác nhận; dừng khi pause/buffer/interruption. Chỉ cập nhật UI khi cần, không chạy display link liên tục trong nền.
- Queue native và queue của web không được cùng tự advance. Spike phải xác định bên có quyền điều khiển; cơ chế này được ghi ADR trước khi mở rộng.
- Restore queue/settings sau mở lại app nhưng không tự phát khi chưa có ý định của người dùng. Force quit không nằm trong cam kết tiếp tục phát.

Layout dự kiến:

```text
Oto.xcodeproj/                 # Tạo trong foundation, chưa có hiện tại
Oto/App/                      # Composition, lifecycle, resources
Oto/Features/                 # Home, Search, Library, Player, Lyrics, Settings
Oto/Platform/                 # AudioSession, NowPlaying, Auth, Playback adapters
Packages/OtoCore/Sources/      # Domain, queue, lyrics, contracts
Packages/OtoCore/Tests/        # Swift Testing, sanitized fixtures
Tools/APIExplorer/            # CLI probe tái sử dụng được, tạo khi khảo sát API
docs/adr/                     # Các quyết định kiến trúc
.agents/skills/               # Workflow cục bộ, chỉ khi đã tạo/kiểm chứng
```

## 5. Yêu cầu và nghiệm thu MVP

Các yêu cầu phát nhạc YTM chỉ được coi là đã triển khai khi qua cổng feasibility trong `docs/PLAYBACK_FEASIBILITY.md`.

| ID | Yêu cầu | Điều kiện nghiệm thu |
| --- | --- | --- |
| AUTH-01 | Khách duyệt/tìm kiếm nếu endpoint hỗ trợ | Không cần đăng nhập để mở app; không hứa guest có mọi quyền phát |
| AUTH-02 | Đăng nhập tài khoản cá nhân | Không thu mật khẩu; phiên tồn tại sau relaunch; lỗi/cancel có thể thử lại |
| AUTH-03 | Hết phiên/đăng xuất | Xóa cookie và backup, hủy request cũ, không hồi sinh dữ liệu tài khoản sau logout |
| CAT-01 | Home + search bài/album/artist/playlist | Loading/empty/error/retry; debounce, cancel query cũ, pagination không trùng |
| CAT-02 | Detail album/playlist/artist cơ bản | Phát bài hoặc cả danh sách theo thứ tự; track không khả dụng báo rõ |
| LIB-01 | Đọc library/liked songs khi đã đăng nhập | Không lẫn account cache; chưa làm mutation trong MVP đầu |
| PLAY-01 | Play/pause/next/previous/seek | State phản ánh engine, xử lý spam tap, không phát chồng hoặc advance hai lần |
| PLAY-02 | Queue, shuffle, repeat off/one/all | Track lặp trong playlist giữ ID riêng; repeat/shuffle qua test xác định |
| PLAY-03 | Khóa màn hình và chuyển app | Hai máy thật vượt ma trận feasibility, gồm chuyển bài khi app đang nền |
| PLAY-04 | Lock Screen/Control Center/tai nghe | Đúng title/artwork/progress; lệnh từ hệ thống tác động cùng queue |
| PLAY-05 | Interruption/route/network | Rút tai nghe không tự bật loa; resume theo user intent và session; retry có giới hạn |
| UI-01 | Mini player + Now Playing | Cùng một session; dismiss/rotate không reload engine hoặc restart bài |
| UI-02 | iPhone/iPad adaptive | Compact, portrait, landscape, split window; layout không che controls/lyrics |
| LYR-01 | Lời đồng bộ theo dòng, lời tĩnh, instrumental | Có trạng thái riêng; plain lyrics không có tap-to-seek giả |
| LYR-02 | Tap dòng, cuộn tay, quay về dòng hiện tại | Seek đúng timestamp; cuộn tay tạm dừng auto-scroll; bài cũ không đè bài mới |
| LYR-03 | Chọn bản lời và chỉnh offset | Hiện nguồn; offset theo track/version/provider, không sửa timestamp gốc |
| SET-01 | Settings tối thiểu | Theme theo hệ thống, motion, lyrics offset, clear cache, sign out |
| A11Y-01 | VoiceOver/Dynamic Type/Reduce Motion | Nút có label; chữ lớn vẫn dùng được; giảm chuyển động và tăng contrast |
| LOC-01 | Tiếng Việt và tiếng Anh | String Catalog của app là nguồn chính; core nhận localized text từ app khi cần |

Playback quảng cáo, quyền Premium, vùng và nội dung hạn chế phải phản ánh khả năng thực tế; không chặn quảng cáo hoặc mô phỏng quyền Premium. Mỗi người dùng phiên riêng khi chia sẻ app.

Sau MVP mới xét: Explore sâu, like/unlike và sửa playlist, tải lời người dùng sở hữu, word timing, romanization, Smart Shuffle, AirPlay mở rộng. Không tải audio/offline trong phạm vi hiện tại; cache metadata/lyrics không phải tải nhạc.

## 6. Lyrics đa nguồn

1. Khi đổi track, tạo request generation mới; hủy việc cũ và chỉ publish kết quả của track hiện tại.
2. Truy vấn bằng title/artist/album/duration có sẵn; không giả định API có ISRC. LRCLIB cung cấp `/api/get` và `/api/search`; xác minh payload hiện tại bằng explorer trước khi viết parser. [LRCLIB docs](https://lrclib.net/docs).
3. Giữ raw title; normalization chỉ loại nhãn quảng bá an toàn. Không bỏ `live`, `remix`, `acoustic`, `remastered` một cách mù quáng vì chúng phân biệt bản thu.
4. Xếp hạng theo metadata, bản thu và duration; không tự lấy kết quả gần duration nhất nếu tên/nghệ sĩ sai. Khớp không chắc thì hiển thị chưa tìm được hoặc cho chọn bản khác.
5. Ưu tiên bản sync khớp tốt từ LRCLIB/YTM đã kiểm chứng; giữ bản plain khớp tốt khi không có sync. Không để plain ghi đè sync hợp lệ của cùng track. Timeout một nguồn không chặn playback.
6. Bảo toàn instrumental; phân biệt no lyrics, provider error, offline và loading. Cache có TTL, version, source và negative TTL ngắn; không cache lỗi mạng thành vĩnh viễn không có lời.
7. LRC cần xử lý nhiều timestamp, offset, dòng rỗng, trùng timestamp, Unicode và dữ liệu sai. Chỉ hiện karaoke từng chữ khi nguồn có timestamp từng chữ thật.
8. Dừng animation khi lyrics không hiển thị; giảm hiệu ứng với Reduce Motion/Low Power Mode. Không poll network theo từng dòng hoặc từng frame.

## 7. Hiệu năng, dữ liệu và độ tin cậy

- Cache artwork có giới hạn dung lượng/kích thước giải mã; không decode ảnh lớn trên main actor. Cache riêng theo account khi dữ liệu cá nhân.
- Không đưa credentials vào model state hiển thị/debug description; Keychain chọn accessibility phù hợp việc đọc khi máy khóa và dùng `ThisDeviceOnly` nếu không cần đồng bộ. Đo trên iOS, không bê workaround Keychain của macOS.
- HTTP errors có loại: auth, network, rate-limited, unavailable, schema mismatch. 401/403 được adapter map theo ngữ nghĩa endpoint đã xác minh; không retry login vô hạn khi là lỗi quyền/nội dung.
- Optional chỉ cho field thật sự tùy chọn. ID/shape bắt buộc thiếu thì báo schema mismatch; không tạo bài giả ID rỗng hoặc trả thành công với feed trống.
- Request read-only có timeout, cancellation, backoff giới hạn; tôn trọng Retry-After. Không tự retry mutation có nguy cơ chạy hai lần.
- Trace tạm chỉ có timestamp, event, ID thử giả hoặc opaque ID; không body/header/session/lyric đầy đủ. Xóa trước chia sẻ build. Dùng app container, không giả định hardcoded `/tmp` ghi được.
- Mục tiêu ban đầu: không tăng memory vô hạn qua 50 lần đổi bài/đóng mở player; đo cold/warm start, first playable time, CPU, memory và energy trên iPad Gen 9. Chốt budget số sau baseline, không bịa mức RAM hoặc pin.
- UI chủ đạo phục vụ tốt màn hình 60 Hz; gradient chỉ là trang trí, có static fallback trên OS cũ và máy yếu. MeshGradient dùng khi API có sẵn và benchmark đạt.

## 8. Lộ trình theo cổng nghiệm thu

| Bước | Việc làm | Kết quả bắt buộc |
| --- | --- | --- |
| S0 — đang làm | Plan, quy tắc agent, audit Kaset, checklist | Bộ tài liệu nhất quán; rủi ro chưa đo được ghi rõ |
| S1 — foundation | Xcode universal target, local core package, mock app, scheme/test/format config | Build simulator; core tests pass; ghi build commands thực tế |
| S2 — feasibility | Auth probe + playback probe, đúng hai máy thật | Hoàn tất AUTH/BG/QUEUE/REMOTE matrix; chọn hoặc bác backend bằng ADR |
| S3 — vertical slice | Search -> chọn bài -> player -> lời -> next | Một luồng thật ổn định, lỗi rõ ràng, không cần full Home/Library |
| S4 — MVP | Home/details/library read-only, queue, cache, accessibility/localization | Các yêu cầu MVP qua test và checklist hai máy |
| S5 — chia sẻ nhóm nhỏ | Release build, signing/install guide, kiểm tra tài khoản khác | Bạn bè cài và đăng nhập riêng; không gửi credentials kèm build |

S1 có thể dùng nội dung âm thanh thử được cấp quyền để kiểm tra hệ thống iOS; kết quả đó chỉ chứng minh native baseline, không chứng minh YTM. Nếu S2 fail, báo nguyên nhân và chọn tiếp tục khảo sát hoặc đổi mục tiêu với chủ dự án; không âm thầm bỏ tiêu chí nghe nền. Không mở rộng UI sau mock để che backend chưa chạy.

Chưa cam kết lịch phát hành. Sau S2 mới ước lượng dựa trên code port thực tế và độ ổn định playback.

## 9. Skills cho AI agent

Đây là danh sách đề xuất, **chưa được cài/tạo trong Oto**. Không gọi tên skill như thể nó đã tồn tại. Workflow để trong `.agents/skills/<name>/SKILL.md` có name/description mô tả đúng lúc dùng; AGENTS chỉ giữ quy tắc chung. [OpenAI: skills](https://developers.openai.com/codex/skills).

| Skill | Dùng khi | Nguồn/trạng thái |
| --- | --- | --- |
| `oto-api-exploration` | Đổi endpoint/parser, capture fixture | Adapt workflow Kaset, bỏ phụ thuộc cookie macOS; dùng explorer tái sử dụng |
| `oto-playback-validation` | Đổi lifecycle/audio/bridge/queue sync | Tạo từ checklist feasibility sau lần đo đầu; ghi kết quả trước/sau |
| `oto-player-ui` | Mini/full player và lyrics layout | Hướng dẫn adaptive layout, accessibility, gestures; không ép animation 120 Hz |
| `oto-lyrics-validation` | Matching/provider/LRC/offset | Corpus giả có nhiều bản thu, stale responses và instrumental |
| `oto-build-device` | Build/sign/install cho máy cá nhân | Tạo khi có project, scheme và đường dẫn thật; không hardcode signing team |
| `autoreview` | Review độc lập thay đổi không nhỏ | Có workflow ở Kaset; đọc/cài có chủ đích sau, không copy mù vào Oto |

Chỉ tạo skill khi có quy trình thật để kiểm chứng; không cần cài tất cả trước khi bắt đầu foundation.

## 10. Chia sẻ, license và giới hạn đã biết

Trước mắt chạy từ Xcode trên máy bạn. Khi chia sẻ nhóm nhỏ, dùng cơ chế ký/provision phù hợp tài khoản developer và thiết bị đăng ký; chưa chọn dịch vụ sideload bên ngoài. Không hứa file IPA cài được trên mọi máy hay vĩnh viễn. [Apple: registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

Việc cài ngoài không chứng minh quyền sử dụng dịch vụ. YouTube API policies hạn chế audio separation/background player; Innertube là API nội bộ, không phải public contract được bảo đảm. Ghi nhận điều này để không hứa độ bền/quyền phân phối; chưa biến App Store thành một hạng mục của dự án. [YouTube developer policies, III.I](https://developers.google.com/youtube/terms/developer-policies#i-additional-prohibitions).

Kaset dùng MIT; giữ license/copyright khi chuyển phần code đáng kể. Xem audit trong `docs/KASET_PORTING_AUDIT.md`. Không dùng lại logo, credential, cấu hình ký hoặc cache tài khoản của Kaset.

## 11. Công việc kế tiếp cụ thể

Vai trò đã được chủ dự án xác nhận: **Gemini CLI triển khai chính, Codex review**. Quy trình bàn giao được đề xuất trong `docs/AGENT_WORKFLOW.md`; chưa có bộ điều phối tự động chạy thực tế.

Trước foundation, thu thập các lựa chọn trong `docs/PRODUCT_INPUTS.md`. Ảnh/video tham khảo đưa vào `design/references/` cùng chú thích theo README ở đó. Chỉ cần chốt phần đầu vào của giai đoạn sắp làm; logo và toàn bộ visual spec không chặn probe playback.

1. Tạo foundation tối thiểu có mock catalog/lyrics/playback và UI debug đơn giản trên cả hai kích thước; chưa xây toàn bộ màn hình đẹp.
2. Ghi scheme, deployment target, toolchain và unit-test commands hoạt động được vào AGENTS.
3. Implement probe auth và playback tách adapter; chủ dự án tự đăng nhập trong app, không gửi secrets cho agent.
4. Thực hiện checklist trên iPad Gen 9 trước, iPhone 13 Pro Max sau; ghi failed/not tested trung thực.
5. Chốt ADR backend rồi mới mở rộng vertical slice YouTube Music.
