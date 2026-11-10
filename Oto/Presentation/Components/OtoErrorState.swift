import SwiftUI

/// Trạng thái báo lỗi kết nối hoặc phân tích dữ liệu với nút Thử lại.
public struct OtoErrorState: View {
    public let title: String
    public let message: String
    public let onRetry: () -> Void

    public init(
        title: String = "Không thể tải dữ liệu",
        message: String,
        onRetry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: OtoTheme.spacing16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(OtoTheme.error)
                .accessibilityHidden(true)

            VStack(spacing: OtoTheme.spacing8) {
                Text(title)
                    .font(OtoTheme.sectionTitleFont)
                    .foregroundStyle(OtoTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(OtoTheme.subtitleFont)
                    .foregroundStyle(OtoTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OtoTheme.spacing32)
            }

            Button(action: onRetry) {
                Label("Thử lại", systemImage: "arrow.clockwise")
                    .font(OtoTheme.buttonFont)
                    .foregroundStyle(OtoTheme.onAccent)
                    .padding(.horizontal, OtoTheme.spacing24)
                    .padding(.vertical, OtoTheme.spacing12)
                    .frame(minHeight: OtoTheme.minTouchTarget)
                    .background(
                        RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous)
                            .fill(OtoTheme.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OtoTheme.spacing24)
        .accessibilityElement(children: .contain)
    }
}
