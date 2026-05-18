import UIKit
import WebKit

/// Minimal in-app browser used by `PMMainViewController` when the embedded
/// web app issues `command://browse.inapp?sharedCookie=true`. Because it
/// shares the process pool with the main `WKWebView`, cookies set on
/// platinumaps.jp continue to apply — required for flows like stamp-rally
/// reward redemption where the destination page must recognise the user
/// session.
///
/// The host typically presents this controller wrapped in a
/// `UINavigationController` so the close button is visible.
class PMWebViewController: UIViewController {

    /// URL to load when the view appears. Must be set before
    /// `viewDidLoad()`; the controller does not reload after the fact.
    public var pageUrl: URL? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.white

        let webView = WKWebView(frame: CGRect.zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        if let nb = navigationController {
            let doneItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(onTapDone))
            nb.navigationBar.topItem?.leftBarButtonItem = doneItem
        }

        guard let url = pageUrl else {
            return
        }
        webView.load(URLRequest(url: url))
    }

    @objc func onTapDone() {
        self.dismiss(animated: true, completion: nil)
    }
}
