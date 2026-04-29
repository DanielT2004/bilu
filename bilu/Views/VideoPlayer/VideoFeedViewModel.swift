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

final class VideoFeedViewModel: ObservableObject, Identifiable {
    let id = UUID()

    // currentIndex is published so VideoPageView re-renders its isActive check
    // All mutations must happen on the main queue (UIPageViewController delegates fire on main)
    @Published private(set) var currentIndex: Int

    var count: Int { videos.count }
    let videos: [TikTokVideo]

    private(set) var pool: [Int: VideoPageModel] = [:]

    init(videos: [TikTokVideo], startIndex: Int = 0) {
        self.videos = videos

        // Clamp startIndex into a valid range so an upstream off-by-one can't crash us.
        let clamped = videos.isEmpty ? 0 : max(0, min(startIndex, videos.count - 1))
        self.currentIndex = clamped

        guard !videos.isEmpty else { return }

        warmPage(at: clamped)
        warmPage(at: clamped + 1)
        warmPage(at: clamped - 1)
        // Note: do not activate here — VideoFeedView calls activateCurrent() in
        // .onAppear. This keeps the pool silently buffering when used purely as
        // a pre-warmer (e.g. RestaurantDetailView before any tap).
    }

    // MARK: - Called when a swipe completes (UIPageViewController delegate, always on main)

    func didSwipeTo(index: Int) {
        guard index != currentIndex, index >= 0, index < count else { return }

        pool[currentIndex]?.deactivate()

        let previous = currentIndex
        currentIndex = index

        // Warm the next page in the swipe direction
        let nextInDirection = index > previous ? index + 1 : index - 1
        warmPage(at: nextInDirection)

        pool[index]?.activate()

        // Evict the page now 2 steps behind
        let toEvict = index > previous ? previous - 1 : previous + 1
        evictPage(at: toEvict)
    }

    /// Re-aim the feed at a new index *before* presentation. Used to pivot a
    /// pre-warmed model (e.g. RestaurantDetailView) to whichever video the user
    /// actually tapped, while keeping any already-loaded players in the pool.
    func setStartIndex(_ index: Int) {
        guard !videos.isEmpty else { return }
        let clamped = max(0, min(index, videos.count - 1))
        guard clamped != currentIndex else { return }

        pool[currentIndex]?.deactivate()
        currentIndex = clamped

        warmPage(at: clamped)
        warmPage(at: clamped + 1)
        warmPage(at: clamped - 1)

        // Evict anything outside the [-1, +1] window
        for key in pool.keys where key < clamped - 1 || key > clamped + 1 {
            evictPage(at: key)
        }
    }

    func activateCurrent() {
        pool[currentIndex]?.activate()
    }

    func deactivateCurrent() {
        pool[currentIndex]?.deactivate()
    }

    // MARK: - Pool management

    @discardableResult
    func warmPage(at index: Int) -> VideoPageModel? {
        guard index >= 0, index < videos.count else { return nil }
        if let existing = pool[index] { return existing }
        let model = VideoPageModel(index: index, video: videos[index])
        pool[index] = model
        return model
    }

    private func evictPage(at index: Int) {
        pool.removeValue(forKey: index)
    }
}
