import UIKit
import WebKit

/// iPhone app: a full-screen WKWebView showing the same index.html as Telegram and Android
/// (copied into the app's "www" folder at build time).
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = WebViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

/// Serves files from the app bundle's "www" folder at putevoy://app/...
/// A real origin (not file://) gives the page normal localStorage, clipboard and fonts.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root = Bundle.main.resourceURL!.appendingPathComponent("www")

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst()))
        guard file.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript", "css": "text/css",
                     "png": "image/png", "json": "application/json", "webmanifest": "application/manifest+json"]
        let mime = types[file.pathExtension.lowercased()] ?? "application/octet-stream"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime, "Content-Length": String(data.count)])!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var web: WKWebView!

    /// Records are kept in a file in the app's own folder, not only in WebKit storage,
    /// so iOS cleaning website data never wipes them. Updates over the old app keep this file.
    private let storeURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("storage.json")
    }()

    private func loadStore() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return obj
    }

    private func saveStore(_ s: [String: String]) {
        if let data = try? JSONSerialization.data(withJSONObject: s) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: "putevoy")
        cfg.applicationNameForUserAgent = "PutevoyUchet/iOS"
        cfg.allowsInlineMediaPlayback = true

        let saved = (try? JSONSerialization.data(withJSONObject: loadStore()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // Page code uses localStorage; mirror every write to the native file and read from it first.
        let bridge = """
        (function(){
          var saved=\(saved), has=function(k){return Object.prototype.hasOwnProperty.call(saved,k)};
          var post=function(k,v){try{webkit.messageHandlers.store.postMessage(v===null?{k:k}:{k:k,v:v})}catch(e){}};
          var ok=true;try{window.localStorage.length}catch(e){ok=false}
          if(!ok){
            var mem={getItem:function(k){return has(k)?saved[k]:null},
                     setItem:function(k,v){saved[k]=String(v);post(k,String(v))},
                     removeItem:function(k){delete saved[k];post(k,null)},
                     clear:function(){Object.keys(saved).forEach(function(k){mem.removeItem(k)})},
                     key:function(i){return Object.keys(saved)[i]||null}};
            Object.defineProperty(mem,"length",{get:function(){return Object.keys(saved).length}});
            try{Object.defineProperty(window,"localStorage",{value:mem,configurable:true})}catch(e){}
            return;
          }
          var p=Storage.prototype,oset=p.setItem,oget=p.getItem,orem=p.removeItem;
          p.setItem=function(k,v){v=String(v);if(this===window.localStorage){saved[k]=v;post(k,v)}try{oset.call(this,k,v)}catch(e){}};
          p.getItem=function(k){if(this===window.localStorage&&has(k))return saved[k];try{return oget.call(this,k)}catch(e){return null}};
          p.removeItem=function(k){if(this===window.localStorage){delete saved[k];post(k,null)}try{orem.call(this,k)}catch(e){}};
        })();
        """
        cfg.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.add(self, name: "store")

        web = WKWebView(frame: .zero, configuration: cfg)
        web.scrollView.contentInsetAdjustmentBehavior = .never // the page handles the notch itself
        web.isOpaque = false
        web.backgroundColor = UIColor(named: "LaunchBg")
        web.scrollView.backgroundColor = UIColor(named: "LaunchBg")
        web.navigationDelegate = self
        web.uiDelegate = self
        view = web
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        web.load(URLRequest(url: URL(string: "putevoy://app/index.html")!))
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let key = body["k"] as? String else { return }
        var s = loadStore()
        if let v = body["v"] as? String { s[key] = v } else { s.removeValue(forKey: key) }
        saveStore(s)
    }

    // Links to other sites open in Safari instead of replacing the app.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, action.targetFrame?.isMainFrame ?? true,
           url.scheme != "putevoy", url.scheme != "about", action.navigationType == .linkActivated {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { UIApplication.shared.open(url) }
        return nil
    }

    // Page dialogs (confirm before delete, etc.) as native alerts.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    // A crashed web process (low memory) reloads the page instead of leaving a blank screen.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}
