# DESIGN.md — Đặc tả Hệ thống Thiết kế Oto (Atelier Light × Spectrum Dark)

> **Dự án:** **Oto** (音)  
> **Nguồn tham chiếu:** Figma Preview 4 frame chính (Atelier Home/Player, Spectrum Home/Player).  
> **Nguyên tắc cốt lõi:** Một hệ thống giao diện, hai sắc thái màu sắc (Atelier = Light mode, Spectrum = Dark mode). Giữ nguyên hình học (geometry), bố cục (hierarchy) và hành vi tương tác giữa hai chế độ.

---

## 1. Bảng màu Semantic Tokens

Mọi màu sắc trong Oto được định nghĩa theo vai trò ngữ nghĩa (semantic tokens), tuyệt đối không hardcode mã hex trong các view thành phần.

| Semantic Token | Atelier (Light Mode) | Spectrum (Dark Mode) | Mục đích sử dụng |
| :--- | :--- | :--- | :--- |
| `background` | `#F7F4EF` (Kem ấm) | `#101117` (Đêm sâu) | Nền chính của toàn bộ màn hình |
| `surface` | `#FFFFFF` (Trắng ngà) | `#1D202A` (Xám chì nổi) | Nền thẻ nội dung, danh sách, thanh điều hướng |
| `secondarySurface` | `#EDE8E0` | `#262A37` | Nền phụ, hàng danh sách hover/nhấn |
| `accentSurface` | `#F5EBE6` | `#242236` | Nền nổi bật khi một mục đang được chọn/phát |
| `primaryText` | `#201E1B` (Nâu than) | `#F7F8FC` (Trắng sáng) | Tiêu đề chính, tên bài hát, nhãn quan trọng |
| `secondaryText` | `#746E65` (Nâu cát) | `#9B9FA9` (Xám tro) | Tên nghệ sĩ, thời lượng, tiêu đề phụ |
| `tertiaryText` | `#A49E94` | `#636773` | Chú thích nhỏ, placeholder, icon phụ |
| `accent` | `#A74328` (Cam đất nung) | `#B9ADFF` (Tím lavender) | Nút hành động chính, thanh tiến trình, icon đang phát |
| `separator` | `#E8E3DA` | `#262A37` | Đường kẻ phân cách, viền thẻ (stroke 0.5pt) |
| `error` | `#C83E3E` | `#FF6B6B` | Trạng thái lỗi mạng, cảnh báo quan trọng (tách khỏi accent) |
| `warning` | `#9A6700` | `#F2C94C` | Trạng thái kết nối chập chờn, dữ liệu chưa sync |
| `success` | `#2F7D4A` | `#62C987` | Trạng thái kết nối thành công, xác nhận tài khoản |
| `controlInactive` | `#8B867E` | `#9297AA` | Icon / nút bấm ở trạng thái không kích hoạt |
| `disabled` | `#C8C2B8` | `#4B5061` | Nút bấm hoặc text bị vô hiệu hoá |
| `scrim` | `#201E1B` (opacity 0.4) | `#05060A` (opacity 0.6) | Lớp phủ làm tối màn hình cho modal/sheet |

---

## 2. Hệ thống Typography (Dynamic Type Support)

Toàn bộ chữ trong app sử dụng hệ thống phông native của Apple với hỗ trợ Dynamic Type (tự động co giãn theo cỡ chữ hệ thống của người dùng):

- **Large Title:** `.system(.largeTitle, design: .default, weight: .bold)` — Tiêu đề màn hình chính (Trang chủ, Tìm kiếm, Thư viện).
- **Section Header:** `.system(.title3, design: .default, weight: .bold)` — Tiêu đề nhóm (Lựa chọn nhanh, Nghe lại gần đây, Đã phát gần đây).
- **Card Title:** `.system(.subheadline, design: .default, weight: .semibold)` — Tên bài hát trong thẻ vuông.
- **Row Title:** `.system(.body, design: .default, weight: .medium)` — Tên bài hát trong hàng danh sách.
- **Subtitle / Artist:** `.system(.subheadline, design: .default, weight: .regular)` — Tên nghệ sĩ trong hàng/thẻ.
- **Caption / Metadata:** `.system(.caption, design: .default, weight: .regular)` — Thông tin bổ sung, thời lượng.
- **Monospaced Time:** `.system(.caption, design: .monospaced, weight: .medium)` — Hiển thị giây/phút trong thanh scrubber.

---

## 3. Hệ thống Hình học (Geometry & Spacing Tokens)

- **Bo góc (Corner Radius):**
  - Thẻ card nội dung (`cardRadius`): `16 pt`
  - Ảnh bìa lớn Fullscreen Player (`artworkRadius`): `12 pt`
  - Ảnh bìa nhỏ hàng danh sách (`smallArtworkRadius`): `8 pt`
  - Nút bấm hành động (`buttonRadius`): `12 pt`
  - Pill Tag / Badge (`pillRadius`): `20 pt`
- **Khoảng cách (Spacing):**
  - `spacing4`: 4 pt
  - `spacing8`: 8 pt
  - `spacing12`: 12 pt
  - `spacing16`: 16 pt
  - `spacing20`: 20 pt
  - `spacing24`: 24 pt
  - `spacing32`: 32 pt
  - `spacing40`: 40 pt
- **Vùng chạm tối thiểu (Touch Target):**
  - `minTouchTarget`: $\ge 44 \times 44 \text{ pt}$ cho mọi nút tương tác (theo Apple HIG).

---

## 4. Danh sách Reusable Shared Components

Để đảm bảo tính nhất quán trên iPhone và iPad, các component dùng chung được chuẩn hóa:

1. `OtoSongRow`: Hàng bài hát chuẩn hiển thị ảnh thumbnail, tên bài, nghệ sĩ, thời lượng, hiệu ứng đang phát (waveform) và menu tùy chọn.
2. `OtoAlbumCard`: Thẻ hiển thị album/danh sách bài dạng lưới hoặc thanh trượt ngang.
3. `OtoSectionHeader`: Tiêu đề mục có nút "Xem tất cả" hoặc hành động phụ.
4. `OtoMiniPlayer`: Thanh phát nhạc mini nổi cố định phía trên Tab Bar.
5. `OtoPlaybackControls`: Cụm nút Shuffle, Previous, Play/Pause, Next, Repeat có haptic feedback và kích thước chạm $\ge 44$pt.
6. `OtoScrubber`: Thanh trượt thời lượng bài hát mượt mà, hỗ trợ scrubbing không gián đoạn âm thanh.
7. `OtoEmptyState`: Trạng thái trống lịch sự với hình minh hoạ SF Symbol, tiêu đề và nút gợi ý.
8. `OtoErrorState`: Trạng thái báo lỗi kết nối có nút "Thử lại".
9. `OtoLoadingSkeleton`: Hiệu ứng shimmer / skeleton loading cho danh sách và thẻ bài hát khi đang tải dữ liệu.

---

## 5. Quy tắc Hành vi & Trợ năng

- **Chuyển đổi Light / Dark:** Tự động theo hệ thống; không gây load lại dữ liệu, không ngắt quãng audio session.
- **Hỗ trợ Reduce Motion:** Tự động tắt scale effect và chuyển động nền khi người dùng bật Trợ năng giảm chuyển động.
- **VoiceOver:** Mọi nút bấm đều có nhãn ngữ nghĩa (`accessibilityLabel`) và gợi ý hành động (`accessibilityHint`).
- **Nền Ambient Blur:** Fallback nhẹ nhàng sang gradient tĩnh dựa trên màu sắc theme khi không có màu bìa album.
