//
//  VideoFeedView.swift
//  bilu
//
//  Full-screen TikTok-style vertical feed using a sliding window of 3 AVPlayers.
//  Presented via .fullScreenCover from RestaurantDetailView.
//

import SwiftUI
import AVFoundation

// MARK: - VideoFeedView

struct VideoFeedView: View {
    @StateObject private var viewModel: VideoFeedViewModel
    @Environment(\.dismiss) private var dismiss

    init(videos: [TikTokVideo], startIndex: Int = 0) {
        _viewModel = StateObject(wrappedValue: VideoFeedViewModel(videos: videos, startIndex: startIndex))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PageViewController(viewModel: viewModel)
                .ignoresSafeArea()

            // Dismiss button — top-left frosted circle
            Button {
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
        .onAppear {
            // Ensure audio plays through speaker even when ringer is off
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
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

        let startVC = context.coordinator.makePageVC(for: viewModel.currentIndex)
        pvc.setViewControllers([startVC], direction: .forward, animated: false)
        return pvc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {}

    // MARK: Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let viewModel: VideoFeedViewModel

        init(viewModel: VideoFeedViewModel) {
            self.viewModel = viewModel
        }

        func makePageVC(for index: Int) -> UIHostingController<VideoPageView> {
            let pageModel = viewModel.warmPage(at: index)
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
