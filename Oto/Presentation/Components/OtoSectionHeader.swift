import SwiftUI

/// Tiêu đề phân nhóm nhất quán với nút hành động tùy chọn.
public struct OtoSectionHeader: View {
    public let title: String
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(
        title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(OtoTheme.sectionTitleFont)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .foregroundStyle(OtoTheme.primaryText)

            Spacer()

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(OtoTheme.captionFont)
                        .fontWeight(.semibold)
                        .foregroundStyle(OtoTheme.accent)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .frame(minHeight: OtoTheme.minTouchTarget)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, OtoTheme.spacing16)
    }
}
