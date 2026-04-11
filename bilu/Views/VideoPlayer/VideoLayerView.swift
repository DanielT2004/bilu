//
//  VideoLayerView.swift
//  bilu
//
//  Wraps a UIView whose backing layer is AVPlayerLayer.
//  Video frames are composited directly by the GPU — no extra copies.
//

import SwiftUI
import AVFoundation

struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        // Player reference never changes after creation
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        // Fill the full screen, cropping if needed (TikTok-style)
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError() }
}
