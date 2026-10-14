import SwiftUI

struct DiscoveryLoadingView: View {
    let phase: String
    let summary: String
    @ObservedObject var ads: LoadingAdController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            LoadingPulseView()
                .id(reduceMotion)
                .accessibilityHidden(true)
                .padding(.top, 36)
                .padding(.bottom, 8)

            VStack(spacing: 10) {
                Text(phase)
                    .font(AppTheme.title)
                    .foregroundStyle(AppTheme.onSurface)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("discovery-loading-title")
                Text("Searching for places that match your cravings, vibe, and location.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)

            LoadingAdvertisementView(ads: ads)

            VStack(alignment: .leading, spacing: 12) {
                Label("YOUR NEXT TABLE", systemImage: "fork.knife")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.sage)
                Text("Make the most of your shortlist")
                    .font(AppTheme.title)
                    .foregroundStyle(AppTheme.onSurface)
                Text("Start with the dish you're craving, then compare the atmosphere and price. For a group, look for a menu with something everyone can enjoy. Before heading out, check the restaurant's latest hours and reservation options.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AppTheme.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }
}

/// Reserves the SDK's maximum adaptive height from the first layout. Loading
/// never pushes content under a finger and the creative is never clipped.
private struct LoadingAdvertisementView: View {
    @ObservedObject var ads: LoadingAdController

    var body: some View {
        VStack(spacing: 8) {
            Text("Advertisement")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .opacity(ads.isLoaded ? 1 : 0)
                .accessibilityHidden(!ads.isLoaded)
            BannerHost(ads: ads)
                .frame(height: 100)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(ads.isLoaded ? AppTheme.white : Color.clear,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Do not animate an interactive advertisement across the screen.
        .transaction { $0.animation = nil }
    }
}

private struct BannerHost: UIViewControllerRepresentable {
    @ObservedObject var ads: LoadingAdController

    func makeUIViewController(context: Context) -> HostController { HostController(ads: ads) }
    func updateUIViewController(_ controller: HostController, context: Context) { controller.updateBanner() }
    static func dismantleUIViewController(_ controller: HostController, coordinator: ()) {
        if controller.discoveryID == controller.ads.discoveryID { controller.ads.suppress() }
    }

    final class HostController: UIViewController {
        let ads: LoadingAdController
        let discoveryID: UUID?
        private weak var hosted: UIView?

        init(ads: LoadingAdController) {
            self.ads = ads
            self.discoveryID = ads.discoveryID
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { nil }
        override func loadView() { view = UIView(); view.backgroundColor = .clear }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            hosted?.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            let width = view.bounds.width
            // Defer publication until SwiftUI's current layout pass is complete.
            Task { @MainActor [weak self] in
                guard let self, self.view.window != nil,
                      self.discoveryID == self.ads.discoveryID else { return }
                self.ads.prepare(width: width, root: self)
            }
        }
        func updateBanner() {
            guard discoveryID == ads.discoveryID else { return }
            guard hosted !== ads.bannerView else { return }
            hosted?.removeFromSuperview()
            hosted = ads.bannerView
            if let banner = ads.bannerView {
                view.addSubview(banner)
                banner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            }
        }
    }
}
