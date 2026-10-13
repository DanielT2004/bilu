import GoogleMobileAds
import UIKit

@MainActor
enum LoadingBannerEvent {
    case loaded, impression, clicked
    case failed(Int)
    case revenue(Decimal, String, Int)
}

@MainActor
protocol LoadingBannerAd: AnyObject {
    var view: UIView { get }
    var size: CGSize { get }
    var onEvent: ((LoadingBannerEvent) -> Void)? { get set }
    func load()
    func dispose()
}

/// One banner per discovery. Configure dashboard refresh off for this unit.
@MainActor
final class GoogleLoadingBanner: NSObject, LoadingBannerAd, BannerViewDelegate, AdSizeDelegate {
    private let banner: BannerView
    var onEvent: ((LoadingBannerEvent) -> Void)?
    var view: UIView { banner }
    var size: CGSize { banner.bounds.size }

    init(unitID: String, width: CGFloat, root: UIViewController) {
        banner = BannerView(adSize: inlineAdaptiveBanner(width: width, maxHeight: 100))
        super.init()
        banner.adUnitID = unitID
        banner.rootViewController = root
        banner.delegate = self
        banner.adSizeDelegate = self
        banner.frame.size = CGSize(width: width, height: 100)
        banner.paidEventHandler = { [weak self] value in
            self?.onEvent?(.revenue(value.value.decimalValue, value.currencyCode, value.precision.rawValue))
        }
    }

    func load() { banner.load(AdPrivacyService.contextualRequest()) }

    func dispose() {
        banner.isHidden = true
        banner.isUserInteractionEnabled = false
        banner.removeFromSuperview()
        banner.delegate = nil
        banner.adSizeDelegate = nil
        banner.paidEventHandler = nil
        banner.rootViewController = nil
        onEvent = nil
    }

    func adView(_ bannerView: BannerView, willChangeAdSizeTo size: AdSize) {
        bannerView.bounds.size = size.size
        bannerView.superview?.setNeedsLayout()
    }

    func bannerViewDidReceiveAd(_ bannerView: BannerView) { onEvent?(.loaded) }
    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        onEvent?(.failed((error as NSError).code))
    }
    func bannerViewDidRecordImpression(_ bannerView: BannerView) { onEvent?(.impression) }
    func bannerViewDidRecordClick(_ bannerView: BannerView) { onEvent?(.clicked) }
}
