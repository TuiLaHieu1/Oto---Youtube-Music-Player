import Foundation
import SwiftUI
import OtoCore

/// ViewModel cung cấp danh sách bài hát gợi ý cho màn hình Home ban đầu.
@MainActor
@Observable
public final class HomeViewModel {
    public var quickPicks: [Song] = []
    public var listenAgain: [Song] = []
    public var isLoading: Bool = false

    public init() {
        loadInitialMockData()
    }

    public func loadInitialMockData() {
        quickPicks = [
            Song(
                id: "qp1",
                title: "Ánh Sao Và Bầu Trời",
                artist: "T.R.I, Cá",
                album: "Ánh Sao Và Bầu Trời (Single)",
                duration: 260.0
            ),
            Song(
                id: "qp2",
                title: "Đưa Em Về Nhà",
                artist: "Grey D, Chillies",
                album: "Dự Báo Thời Tiết Hôm Nay Mưa",
                duration: 245.0
            ),
            Song(
                id: "qp3",
                title: "See You Again",
                artist: "Wiz Khalifa, Charlie Puth",
                album: "Furious 7 Soundtrack",
                duration: 229.0
            ),
            Song(
                id: "qp4",
                title: "Counting Stars",
                artist: "OneRepublic",
                album: "Native",
                duration: 257.0
            )
        ]

        listenAgain = [
            Song(
                id: "la1",
                title: "Chờ Đợi Có Đáng Sợ",
                artist: "Andiez",
                album: "Chờ Đợi Có Đáng Sợ (Single)",
                duration: 275.0
            ),
            Song(
                id: "la2",
                title: "Shape of You",
                artist: "Ed Sheeran",
                album: "÷ (Divide)",
                duration: 233.0
            )
        ]
    }
}
