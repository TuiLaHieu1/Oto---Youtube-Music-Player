import CoreGraphics

/// Hành động phát nhạc tương ứng với một cú vuốt trên Mini Player.
public enum MiniPlayerSwipeAction: Sendable, Equatable {
    case previous
    case next
}

/// Quy đổi khoảng dịch chuyển của một cú vuốt thành tối đa một hành động.
/// Chỉ nhận vuốt ngang rõ ràng để không tranh chấp với cuộn dọc hoặc chạm nút.
public enum MiniPlayerSwipePolicy {
    public static let defaultMinimumDistance: CGFloat = 44
    public static let defaultHorizontalDominance: CGFloat = 1.5

    public static func action(
        translation: CGSize,
        minimumDistance: CGFloat = Self.defaultMinimumDistance,
        horizontalDominance: CGFloat = Self.defaultHorizontalDominance
    ) -> MiniPlayerSwipeAction? {
        guard translation.width.isFinite, translation.height.isFinite else { return nil }
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard horizontal >= minimumDistance else { return nil }
        guard horizontal > vertical * horizontalDominance else { return nil }
        return translation.width > 0 ? .previous : .next
    }
}
