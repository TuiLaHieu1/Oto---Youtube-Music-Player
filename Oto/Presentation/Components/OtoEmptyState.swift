import SwiftUI

/// Trạng thái trống (Empty State) nhất quán theo hệ thống Atelier Light × Spectrum Dark.
public struct OtoEmptyState: View {
    public let iconName: String
    public let title: String
    public let message: String?
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(
        iconName: String = "music.note.house",
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.iconName = iconName
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: OtoTheme.spacing16) {
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundStyle(OtoTheme.tertiaryText)
                .accessibilityHidden(true)

            VStack(spacing: OtoTheme.spacing8) {
                Text(title)
                    .font(OtoTheme.sectionTitleFont)
                    .foregroundStyle(OtoTheme.primaryText)
                    .multilineTextAlignment(.center)

                if let message = message {
                    Text(message)
                        .font(OtoTheme.subtitleFont)
                        .foregroundStyle(OtoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, OtoTheme.spacing32)
                }
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(OtoTheme.buttonFont)
                        .foregroundStyle(OtoTheme.surface)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OtoTheme.spacing24)
    }
}
