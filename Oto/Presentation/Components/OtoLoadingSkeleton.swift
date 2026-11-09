import SwiftUI

/// Khung xương giả lập (Skeleton Loading) khi ứng dụng đang nạp dữ liệu từ YouTube Music.
public struct OtoLoadingSkeleton: View {
    @State private var opacity: Double = 0.35

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtoTheme.spacing32) {
                // Section 1: Quick Picks Cards Skeleton
                VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                    skeletonBox(width: 160, height: 22)
                        .padding(.horizontal, OtoTheme.spacing16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: OtoTheme.spacing16) {
                            ForEach(0..<4, id: \.self) { _ in
                                cardSkeleton
                            }
                        }
                        .padding(.horizontal, OtoTheme.spacing16)
                    }
                }

                // Section 2: Listen Again Rows Skeleton
                VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                    skeletonBox(width: 180, height: 22)
                        .padding(.horizontal, OtoTheme.spacing16)

                    VStack(spacing: OtoTheme.spacing8) {
                        ForEach(0..<5, id: \.self) { _ in
                            rowSkeleton
                        }
                    }
                    .padding(.horizontal, OtoTheme.spacing16)
                }
            }
            .padding(.top, OtoTheme.spacing16)
            .padding(.bottom, 160)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                opacity = 0.75
            }
        }
    }

    private var cardSkeleton: some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
            skeletonBox(width: 144, height: 144, radius: OtoTheme.artworkRadius)
            skeletonBox(width: 120, height: 16, radius: 4)
            skeletonBox(width: 80, height: 12, radius: 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                .fill(OtoTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                        .stroke(OtoTheme.separator, lineWidth: 0.5)
                )
        )
    }

    private var rowSkeleton: some View {
        HStack(spacing: OtoTheme.spacing12) {
            skeletonBox(width: 48, height: 48, radius: OtoTheme.smallArtworkRadius)

            VStack(alignment: .leading, spacing: 6) {
                skeletonBox(width: 160, height: 16, radius: 4)
                skeletonBox(width: 100, height: 12, radius: 4)
            }

            Spacer()
        }
        .padding(.horizontal, OtoTheme.spacing12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                .fill(OtoTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                        .stroke(OtoTheme.separator, lineWidth: 0.5)
                )
        )
    }

    private func skeletonBox(width: CGFloat, height: CGFloat, radius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OtoTheme.secondaryText.opacity(opacity))
            .frame(width: width, height: height)
    }
}
