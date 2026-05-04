import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var hosting: UIHostingController<ShareRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        loadSharedURL { [weak self] url in
            DispatchQueue.main.async {
                self?.present(url: url)
            }
        }
    }

    private func present(url: URL?) {
        let root = ShareRootView(
            sharedURL: url,
            onDone: { [weak self] in self?.complete() },
            onCancel: { [weak self] in self?.complete() }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.modalPresentationStyle = .overFullScreen
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        hosting = host
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func loadSharedURL(completion: @escaping (URL?) -> Void) {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let providers = item.attachments
        else {
            completion(nil); return
        }

        let urlType = UTType.url.identifier
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { data, _ in
                completion(Self.coerceURL(from: data))
            }
            return
        }

        let textType = UTType.plainText.identifier
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            provider.loadItem(forTypeIdentifier: textType, options: nil) { data, _ in
                if let s = data as? String, let url = URL(string: s) {
                    completion(url)
                } else {
                    completion(nil)
                }
            }
            return
        }

        completion(nil)
    }

    private static func coerceURL(from data: NSSecureCoding?) -> URL? {
        if let url = data as? URL { return url }
        if let s = data as? String { return URL(string: s) }
        return nil
    }
}
