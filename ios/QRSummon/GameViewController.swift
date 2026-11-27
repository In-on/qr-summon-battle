import UIKit
import WebKit

/// ゲーム（www フォルダ内の index.html）を WKWebView で表示し、
/// JavaScript の window.QRIAP / window.QRAd をネイティブ（StoreKit / AdMob）につなぐ。
final class GameViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static let scheme = "qrsummon"
    static let startURL = URL(string: "\(scheme)://localhost/index.html")!

    private var webView: WKWebView!
    private let iap = IAPBridge()
    private let ads = AdBridge()

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: Self.scheme)
        config.allowsInlineMediaPlayback = true               // カメラ映像を全画面にせず表示するため
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()                  // localStorage（セーブデータ）を保持
        // User-Agent の最後に QRSummonApp を付ける（ゲームの isApp() がこれでアプリ版と判断する）
        config.applicationNameForUserAgent = "Mobile/15E148 QRSummonApp"

        let ucc = WKUserContentController()
        ucc.add(WeakScriptMessageHandler(self), name: "qr")
        if let url = Bundle.main.url(forResource: "native-bridge", withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8) {
            ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.userContentController = ucc

        webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.allowsLinkPreview = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        iap.onDeliver = { [weak self] items in self?.deliver(items) }
        iap.start()
        webView.load(URLRequest(url: Self.startURL))
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    func prepareAds() {
        Task { await ads.prepare(from: self) }
    }

    // MARK: - JS → ネイティブ

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? Int,
              let cmd = body["cmd"] as? String else { return }
        let args = body["args"] as? [String: Any] ?? [:]

        Task { @MainActor in
            do {
                let result: Any
                switch cmd {
                case "iap.buy":
                    result = try await iap.buy(productID: args["pid"] as? String ?? "")
                case "iap.finish":
                    await iap.finish(transactionID: args["tx"] as? String ?? "")
                    result = true
                case "iap.pending":
                    result = await iap.pendingDeliveries()
                case "iap.restore":
                    result = await iap.premiumPurchaseDates(sync: args["sync"] as? Bool ?? false)
                case "ad.show":
                    result = await ads.showRewarded(from: self)
                default:
                    result = NSNull()
                }
                self.reply(id: id, ok: true, value: result)
            } catch {
                self.reply(id: id, ok: false, value: error.localizedDescription)
            }
        }
    }

    private func reply(id: Int, ok: Bool, value: Any) {
        let json = Self.json(value)
        webView.evaluateJavaScript("window.__qrNative&&__qrNative.reply(\(id),\(ok),\(json))", completionHandler: nil)
    }

    private func deliver(_ items: [[String: String]]) {
        webView.evaluateJavaScript("window.__qrNative&&__qrNative.deliver(\(Self.json(items)))", completionHandler: nil)
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    // MARK: - ナビゲーション（外部リンクは Safari で開く）

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == Self.scheme || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            decisionHandler(.allow)
            return
        }
        if navigationAction.targetFrame?.isMainFrame ?? true {
            if ["http", "https", "mailto"].contains(url.scheme ?? "") {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["http", "https", "mailto"].contains(url.scheme ?? "") {
            UIApplication.shared.open(url)
        }
        return nil
    }

    // ゲーム内カメラ（getUserMedia）は、OSのカメラ許可が済んでいれば追加の確認を出さない
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(type == .camera ? .grant : .deny)
    }

    // WebView のプロセスが落ちたら読み込み直す（セーブは localStorage に残る）
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.load(URLRequest(url: Self.startURL))
    }

    // alert / confirm をネイティブのダイアログで出す
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }
}

/// WKUserContentController が handler を強参照して循環参照になるのを防ぐ
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}
