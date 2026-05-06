//
//  VideoPageModel.swift
//  bilu
//
//  Architecture: Each page owns exactly one AVPlayer for exactly one TikTokVideo.
//  Created once, never reassigned. Buffers silently while not active.
//

import Foundation
import Combine
import AVFoundation

final class VideoPageModel: ObservableObject {
    let index: Int
    let video: TikTokVideo
    let player: AVPlayer

    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var playbackRate: Float = 1.0

    private var timeObserver: Any?
    private var loopObserver: Any?

    init(index: Int, video: TikTokVideo) {
        self.index = index
        self.video = video
        self.player = AVPlayer()

        guard let url = URL(string: video.videoUrl) else { return }

        let item = AVPlayerItem(url: url)
        // Short buffer target — start playback within ~1.5s instead of 5s
        item.preferredForwardBufferDuration = 1.5
        player.replaceCurrentItem(with: item)
        player.isMuted = true  // Silent until activated

        setupLoopObserver(for: item)
        setupProgressObserver()
    }

    // MARK: - State transitions

    /// Called when this page becomes visible. Already buffered — unmute and play.
    func activate() {
        player.isMuted = false
        player.play()
        player.rate = playbackRate
        isPlaying = true
    }

    /// Called when user swipes away. Pause, mute, reset to frame 0.
    func deactivate() {
        player.pause()
        player.isMuted = true
        player.seek(to: .zero)
        isPlaying = false
        playbackRate = 1.0
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
    }

    /// Set playback rate (e.g. 1.0 normal, 2.0 for hold-to-skim).
    /// Only takes effect while the video is actively playing — a held finger
    /// on a paused video must not auto-start playback.
    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    // MARK: - Private setup

    private func setupLoopObserver(for item: AVPlayerItem) {
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
    }

    private func setupProgressObserver() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self,
                  let item = self.player.currentItem,
                  item.duration.isNumeric,
                  item.duration.seconds > 0
            else { return }
            self.progress = time.seconds / item.duration.seconds
        }
    }

    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        if let obs = loopObserver { NotificationCenter.default.removeObserver(obs) }
    }
}
