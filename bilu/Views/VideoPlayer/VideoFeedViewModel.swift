//
//  VideoFeedViewModel.swift
//  bilu
//
//  Manages the sliding window of VideoPageModels.
//  Rule: keep alive at most — prev + current + next (max 3).
//  Models outside that window are evicted (deallocated).
//

import Foundation
import Combine

final class VideoFeedViewModel: ObservableObject {
    // currentIndex is published so VideoPageView re-renders its isActive check
    // All mutations must happen on the main queue (UIPageViewController delegates fire on main)
    @Published private(set) var currentIndex: Int

    var count: Int { videos.count }
    let videos: [TikTokVideo]

    private(set) var pool: [Int: VideoPageModel] = [:]

    init(videos: [TikTokVideo], startIndex: Int = 0) {
        self.videos = videos
        self.currentIndex = startIndex

        guard !videos.isEmpty else { return }

        // Warm the start page and adjacent pages
        warmPage(at: startIndex)
        if startIndex + 1 < videos.count { warmPage(at: startIndex + 1) }
        if startIndex - 1 >= 0           { warmPage(at: startIndex - 1) }

        pool[startIndex]?.activate()
    }

    // MARK: - Called when a swipe completes (UIPageViewController delegate, always on main)

    func didSwipeTo(index: Int) {
        guard index != currentIndex else { return }

        pool[currentIndex]?.deactivate()

        let previous = currentIndex
        currentIndex = index

        // Warm the next page in the swipe direction
        let nextInDirection = index > previous ? index + 1 : index - 1
        if nextInDirection >= 0 && nextInDirection < count {
            warmPage(at: nextInDirection)
        }

        pool[index]?.activate()

        // Evict the page now 2 steps behind
        let toEvict = index > previous ? previous - 1 : previous + 1
        evictPage(at: toEvict)
    }

    // MARK: - Pool management

    @discardableResult
    func warmPage(at index: Int) -> VideoPageModel {
        if let existing = pool[index] { return existing }
        guard index >= 0, index < videos.count else {
            fatalError("Invalid page index \(index)")
        }
        let model = VideoPageModel(index: index, video: videos[index])
        pool[index] = model
        return model
    }

    private func evictPage(at index: Int) {
        guard index >= 0, index < count else { return }
        pool.removeValue(forKey: index)
    }
}
