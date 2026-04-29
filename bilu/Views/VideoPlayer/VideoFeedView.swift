//
//  VideoFeedView.swift
//  bilu
//
//  Full-screen TikTok-style vertical feed using a sliding window of 3 AVPlayers.
//  Presented via .fullScreenCover from RestaurantDetailView.
//

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - VideoFeedView

struct VideoFeedView: View {
    @ObservedObject var viewModel: VideoFeedViewModel
    @Environment(\.dismiss) private var dismiss
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            PageViewController(viewModel: viewModel)
                .ignoresSafeArea()

            // Dismiss button — top-left frosted circle
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(.leading, 16)
                    .padding(.top, 16)
            }
        }
        .background(Color.black)
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    if value.translation.height > 0 {
                        state = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    }
                }
        )
        .onAppear {
            // Ensure audio plays through speaker even when ringer is off
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            viewModel.activateCurrent()
        }
        .onDisappear {
            viewModel.deactivateCurrent()
        }
    }
}

// MARK: - PageViewController

struct PageViewController: UIViewControllerRepresentable {
    let viewModel: VideoFeedViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .vertical
        )
        pvc.view.backgroundColor = .black
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator

        if let startVC = context.coordinator.makePageVC(for: viewModel.currentIndex) {
            pvc.setViewControllers([startVC], direction: .forward, animated: false)
        }
        return pvc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {}

    // MARK: Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let viewModel: VideoFeedViewModel

        init(viewModel: VideoFeedViewModel) {
            self.viewModel = viewModel
        }

        func makePageVC(for index: Int) -> UIHostingController<VideoPageView>? {
            guard let pageModel = viewModel.warmPage(at: index) else { return nil }
            let pageView = VideoPageView(feedViewModel: viewModel, pageModel: pageModel, index: index)
            let vc = UIHostingController(rootView: pageView)
            vc.view.backgroundColor = .black
            vc.view.tag = index
            return vc
        }

        // MARK: UIPageViewControllerDataSource

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerBefore vc: UIViewController
        ) -> UIViewController? {
            let idx = vc.view.tag
            guard idx > 0 else { return nil }
            return makePageVC(for: idx - 1)
        }

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerAfter vc: UIViewController
        ) -> UIViewController? {
            let idx = vc.view.tag
            guard idx < viewModel.count - 1 else { return nil }
            return makePageVC(for: idx + 1)
        }

        // MARK: UIPageViewControllerDelegate

        func pageViewController(
            _ pvc: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed, let vc = pvc.viewControllers?.first else { return }
            viewModel.didSwipeTo(index: vc.view.tag)
        }
    }
}
