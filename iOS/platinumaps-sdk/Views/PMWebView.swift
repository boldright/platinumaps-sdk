import WebKit

/// A `WKWebView` subclass that flattens its reported `safeAreaInsets` to
/// zero. The Platinumaps web layer handles its own safe-area padding (it
/// receives the host's insets via the `safearea` query parameter) so leaving
/// WebKit's insets in place would result in double padding at the top and
/// bottom of the page.
class PMWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}
