import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Hệ thống Design Tokens theo đặc tả: Atelier (Light mode) × Spectrum (Dark mode).
///
/// Nguyên tắc cốt lõi: Đổi sắc thái màu, giữ nguyên vị trí, cấu trúc điều hướng và logic phát nhạc.
/// Tự động thích ứng theo giao diện hệ thống (System Appearance) mà không làm gián đoạn playback.
public enum OtoTheme {

    // MARK: - Dynamic Color Factory

    public static func dynamicColor(light: String, dark: String) -> Color {
        #if os(iOS)
        let uiColor = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(hex: dark)
            } else {
                return UIColor(hex: light)
            }
        }
        return Color(uiColor: uiColor)
        #else
        return Color(hex: dark)
        #endif
    }

    // MARK: - Core Color Tokens

    /// Canvas Background:
    /// - Atelier (Light): #F7F4EF (nền sáng ấm, craft paper)
    /// - Spectrum (Dark): #101117 (nền tối sâu, immersive)
    public static let background = dynamicColor(light: "F7F4EF", dark: "101117")

    /// Surface:
    /// - Atelier: #FFFFFF (bề mặt thẻ sạch sẽ)
    /// - Spectrum: #1D202A (bề mặt nổi lớp than chì)
    public static let surface = dynamicColor(light: "FFFFFF", dark: "1D202A")

    /// Surface Elevated (Popup, Inset, Chip cao hơn một bậc):
    /// - Atelier: #FDFCFA
    /// - Spectrum: #262A37
    public static let surfaceElevated = dynamicColor(light: "FDFCFA", dark: "262A37")

    /// Primary Text:
    /// - Atelier: #201E1B (chữ đen than ấm, độ tương phản cao)
    /// - Spectrum: #F7F8FC (chữ trắng ánh bạc)
    public static let primaryText = dynamicColor(light: "201E1B", dark: "F7F8FC")

    /// Secondary Text:
    /// - Atelier: #7A756D (chữ phụ xám ấm)
    /// - Spectrum: #8F94A6 (chữ phụ xám sương lạnh)
    public static let secondaryText = dynamicColor(light: "7A756D", dark: "8F94A6")

    /// Tertiary Text / Placeholder:
    /// - Atelier: #A6A095
    /// - Spectrum: #5D6275
    public static let tertiaryText = dynamicColor(light: "A6A095", dark: "5D6275")

    /// Accent / Highlight Color:
    /// - Atelier: #A74328 (đỏ gạch nung terracotta ấm áp)
    /// - Spectrum: #B9ADFF (tím oải hương lavender huyền ảo)
    public static let accent = dynamicColor(light: "A74328", dark: "B9ADFF")

    /// On-Accent (Nội dung trên nền accent, ví dụ icon nút Play):
    /// - Atelier: #FFFFFF
    /// - Spectrum: #171225
    public static let onAccent = dynamicColor(light: "FFFFFF", dark: "171225")

    /// Accent Surface (Nền mờ nhạt cho badge, tag, nút chọn):
    /// - Atelier: #F6EDE9 (terracotta 10%)
    /// - Spectrum: #242238 (lavender 15%)
    public static let accentSurface = dynamicColor(light: "F6EDE9", dark: "242238")

    /// Separator / Border:
    /// - Atelier: #E8E3DA (đường viền nhẹ nhàng)
    /// - Spectrum: #262A37 (đường phân tách sâu)
    public static let separator = dynamicColor(light: "E8E3DA", dark: "262A37")

    /// Error Color (Tuyệt đối không dùng chung với accent):
    /// - Atelier: #C83E3E
    /// - Spectrum: #FF6B6B
    public static let error = dynamicColor(light: "C83E3E", dark: "FF6B6B")

    /// Warning dùng cho trạng thái kết nối chập chờn hoặc dữ liệu chưa đồng bộ.
    public static let warning = dynamicColor(light: "9A6700", dark: "F2C94C")

    /// Success tách khỏi Accent để trạng thái tài khoản luôn dễ hiểu.
    public static let success = dynamicColor(light: "2F7D4A", dark: "62C987")

    /// Control chưa chọn và trạng thái disabled.
    public static let controlInactive = dynamicColor(light: "8B867E", dark: "9297AA")
    public static let disabled = dynamicColor(light: "C8C2B8", dark: "4B5061")

    /// Lớp phủ cho sheet/menu, không phụ thuộc màu artwork.
    public static let scrim = dynamicColor(light: "201E1B", dark: "05060A")

    // MARK: - Geometry Tokens

    /// Bo góc thẻ nội dung thống nhất: 16 pt
    public static let cardRadius: CGFloat = 16

    /// Bo góc ảnh bìa lớn / album: 12 pt
    public static let artworkRadius: CGFloat = 12

    /// Bo góc ảnh thumbnail hàng danh sách: 8 pt
    public static let smallArtworkRadius: CGFloat = 8

    /// Bo góc nút bấm hành động: 12 pt
    public static let buttonRadius: CGFloat = 12

    /// Bo góc dạng viên thuốc (Pill tag): 20 pt
    public static let pillRadius: CGFloat = 20

    /// Kích thước vùng chạm tối thiểu chuẩn Apple HIG: 44 × 44 pt
    public static let minTouchTarget: CGFloat = 44

    // MARK: - Spacing Scale

    public static let spacing4: CGFloat = 4
    public static let spacing8: CGFloat = 8
    public static let spacing12: CGFloat = 12
    public static let spacing16: CGFloat = 16
    public static let spacing20: CGFloat = 20
    public static let spacing24: CGFloat = 24
    public static let spacing32: CGFloat = 32
    public static let spacing40: CGFloat = 40

    // MARK: - Typography (Dynamic Type Text Styles)

    /// Tiêu đề màn hình chính (Trang chủ, Thư viện, Tìm kiếm)
    public static let largeTitleFont = Font.system(.largeTitle, design: .default, weight: .bold)

    /// Tiêu đề phân nhóm (Lựa chọn nhanh, Nghe lại gần đây, Đã phát gần đây)
    public static let sectionTitleFont = Font.system(.title3, design: .default, weight: .bold)

    /// Tên bài hát hiển thị trong hàng danh sách
    public static let rowTitleFont = Font.system(.body, design: .default, weight: .medium)

    /// Tên bài hát hiển thị trong thẻ vuông (Card)
    public static let cardTitleFont = Font.system(.subheadline, design: .default, weight: .semibold)

    /// Tên nghệ sĩ hoặc mô tả phụ
    public static let subtitleFont = Font.system(.subheadline, design: .default, weight: .regular)

    /// Thông tin chú thích nhỏ, thời lượng bài hát
    public static let captionFont = Font.system(.caption, design: .default, weight: .regular)

    /// Chữ số thời gian định dạng monospaced (tránh nhảy số khi chạy nhạc)
    public static let timeFont = Font.system(.caption, design: .monospaced, weight: .medium)

    /// Nhãn nút bấm hành động chính
    public static let buttonFont = Font.system(.headline, design: .default, weight: .semibold)

    // MARK: - Shadows

    /// Bóng đổ nhẹ cho thẻ nội dung
    public static let cardShadowColor = dynamicColor(light: "D8D2C6", dark: "000000")

    // MARK: - Motion Tokens

    public static let standardSpring = Animation.spring(response: 0.3, dampingFraction: 0.78)
    public static let smoothSpring = Animation.spring(response: 0.35, dampingFraction: 0.82)
}

// MARK: - Hex Color Helper

#if os(iOS)
private extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
#endif

private extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
