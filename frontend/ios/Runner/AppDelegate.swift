import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var snapshotDelegates: [SnapshotNavDelegate] = []
  private var snapshotWebViews: [WKWebView] = []
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // MethodChannel for webpage snapshot
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "bookmark.snapshot", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] (call, result) in
        guard call.method == "takeSnapshot" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let args = call.arguments as? [String: Any],
              let urlStr = args["url"] as? String,
              let outPath = args["outPath"] as? String else {
          result(FlutterError(code: "ARG_ERROR", message: "Missing required arguments", details: nil))
          return
        }
        let width = (args["width"] as? NSNumber)?.doubleValue ?? 1024.0
        let height = (args["height"] as? NSNumber)?.doubleValue ?? 768.0
        self?.takeSnapshot(urlString: urlStr, size: CGSize(width: width, height: height), outPath: outPath, completion: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func takeSnapshot(urlString: String, size: CGSize, outPath: String, completion: @escaping FlutterResult) {
    guard let url = URL(string: urlString) else {
      completion(FlutterError(code: "URL_ERROR", message: "Invalid URL", details: urlString))
      return
    }
    
    let webView = WKWebView(frame: CGRect(origin: .zero, size: size))
    var navDelegate: SnapshotNavDelegate!
    var hasCompleted = false
    
    // タイムアウト設定（15秒）
    let timeout = DispatchWorkItem { [weak self, weak webView, weak navDelegate] in
      if !hasCompleted {
        hasCompleted = true
        completion(FlutterError(code: "TIMEOUT_ERROR", message: "Page load timeout", details: "ページの読み込みがタイムアウトしました"))
        if let webView = webView { self?.snapshotWebViews.removeAll { $0 === webView } }
        if let navDelegate = navDelegate { self?.snapshotDelegates.removeAll { $0 === navDelegate } }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeout)
    
    navDelegate = SnapshotNavDelegate { [weak self, weak webView, weak navDelegate] success, error in
      guard !hasCompleted else { return }
      hasCompleted = true
      timeout.cancel()
      
      guard success else {
        completion(FlutterError(code: "LOAD_ERROR", message: "Failed to load page", details: error?.localizedDescription))
        if let webView = webView { self?.snapshotWebViews.removeAll { $0 === webView } }
        if let navDelegate = navDelegate { self?.snapshotDelegates.removeAll { $0 === navDelegate } }
        return
      }
      let config = WKSnapshotConfiguration()
      config.rect = CGRect(origin: .zero, size: size)
      webView?.takeSnapshot(with: config) { image, err in
        guard let image = image else {
          completion(FlutterError(code: "SNAPSHOT_ERROR", message: "Snapshot returned nil", details: err?.localizedDescription))
          if let webView = webView { self?.snapshotWebViews.removeAll { $0 === webView } }
          if let navDelegate = navDelegate { self?.snapshotDelegates.removeAll { $0 === navDelegate } }
          return
        }
        guard let data = image.pngData() else {
          completion(FlutterError(code: "ENCODE_ERROR", message: "PNG encoding failed", details: nil))
          if let webView = webView { self?.snapshotWebViews.removeAll { $0 === webView } }
          if let navDelegate = navDelegate { self?.snapshotDelegates.removeAll { $0 === navDelegate } }
          return
        }
        do {
          let outUrl = URL(fileURLWithPath: outPath)
          try FileManager.default.createDirectory(at: outUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
          try data.write(to: outUrl)
          completion(outPath)
        } catch {
          completion(FlutterError(code: "WRITE_ERROR", message: "Failed to write file", details: error.localizedDescription))
        }
        if let webView = webView { self?.snapshotWebViews.removeAll { $0 === webView } }
        if let navDelegate = navDelegate { self?.snapshotDelegates.removeAll { $0 === navDelegate } }
      }
    }
    webView.navigationDelegate = navDelegate
    snapshotDelegates.append(navDelegate)
    snapshotWebViews.append(webView)
    
    // URLリクエストにタイムアウトを設定
    var request = URLRequest(url: url)
    request.timeoutInterval = 15.0
    webView.load(request)
  }
}

private class SnapshotNavDelegate: NSObject, WKNavigationDelegate {
  private let onFinish: (_ success: Bool, _ error: Error?) -> Void
  init(onFinish: @escaping (_ success: Bool, _ error: Error?) -> Void) {
    self.onFinish = onFinish
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    onFinish(true, nil)
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    onFinish(false, error)
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    onFinish(false, error)
  }
}
