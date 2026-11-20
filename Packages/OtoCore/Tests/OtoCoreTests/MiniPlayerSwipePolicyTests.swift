import CoreGraphics
import Testing
@testable import OtoCore

@Suite("Mini Player vuốt ngang")
struct MiniPlayerSwipePolicyTests {
    @Test("Vuốt phải là bài trước")
    func rightSwipeMeansPrevious() {
        #expect(MiniPlayerSwipePolicy.action(translation: CGSize(width: 80, height: 0)) == .previous)
    }

    @Test("Vuốt trái là bài tiếp theo")
    func leftSwipeMeansNext() {
        #expect(MiniPlayerSwipePolicy.action(translation: CGSize(width: -80, height: 0)) == .next)
    }

    @Test("Dưới ngưỡng thì không làm gì")
    func belowThresholdDoesNothing() {
        #expect(MiniPlayerSwipePolicy.action(translation: CGSize(width: 43, height: 0)) == nil)
        #expect(MiniPlayerSwipePolicy.action(translation: CGSize(width: -20, height: 0)) == nil)
    }

    @Test("Vuốt dọc chiếm ưu thế thì không đổi bài")
    func verticalSwipeDoesNotChangeTrack() {
        #expect(MiniPlayerSwipePolicy.action(translation: CGSize(width: 50, height: 40)) == nil)
        #expect(MiniPlayerSwipePolicy.action(translation: CGSize(width: 50, height: -80)) == nil)
    }

    @Test("Vuốt chéo nhưng ngang rõ ràng vẫn nhận")
    func clearlyHorizontalDiagonalIsAccepted() {
        #expect(MiniPlayerSwipePolicy.action(translation: CGSize(width: 90, height: 30)) == .previous)
        #expect(MiniPlayerSwipePolicy.action(translation: CGSize(width: -90, height: -30)) == .next)
    }

    @Test("Giá trị không hữu hạn bị bỏ qua")
    func nonFiniteTranslationIsIgnored() {
        #expect(MiniPlayerSwipePolicy.action(translation: CGSize(width: CGFloat.infinity, height: 0)) == nil)
        #expect(MiniPlayerSwipePolicy.action(translation: CGSize(width: 80, height: CGFloat.nan)) == nil)
    }

    @Test("Ngưỡng và độ ưu thế có thể tinh chỉnh")
    func customThresholdsAreHonored() {
        #expect(MiniPlayerSwipePolicy.action(
            translation: CGSize(width: 30, height: 0),
            minimumDistance: 20
        ) == .previous)
        #expect(MiniPlayerSwipePolicy.action(
            translation: CGSize(width: 50, height: 30),
            horizontalDominance: 1
        ) == .previous)
    }
}
