import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var snapshotDelegates: [SnapshotNavDelegate] = []
  private var snapshotWebViews: [WKWebView] = []
  private var shareChannel: FlutterMethodChannel?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Darwin Notification のリスナーを登録（Share Extensionからの通知を受け取る）
    setupDarwinNotificationListener()
    
    // MethodChannel for webpage snapshot
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "bookmark.snapshot", binaryMessenger: controller.binaryMessenger)
      
      // MethodChannel for Share Extension
      shareChannel = FlutterMethodChannel(name: "bookmark.share", binaryMessenger: controller.binaryMessenger)
      
      // Snapshot channel handler
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
      
      // Share channel handler
      shareChannel?.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "getSharedData" {
          if let data = self?.getSharedData() {
            result(data)
          } else {
            result(nil)
          }
        } else if call.method == "clearSharedData" {
          self?.clearSharedData()
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func setupDarwinNotificationListener() {
    // Share Extension からの Darwin Notification を監視
    let notificationName = "com.hashinokuchi.bookmark.shareExtensionDidSaveData" as CFString
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(self).toOpaque()
    
    CFNotificationCenterAddObserver(center, observer, { (center, observer, name, object, userInfo) in
      // 通知を受け取ったらメインスレッドで処理
      DispatchQueue.main.async {
        if let observer = observer {
          let appDelegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
          appDelegate.handleShareExtensionNotification()
        }
      }
    }, notificationName, nil, .deliverImmediately)
    
    NSLog("[Runner] Darwin notification listener registered")
  }
  
  @objc private func handleShareExtensionNotification() {
    NSLog("[Runner] Received Darwin notification from Share Extension")
    
    // アプリが既にアクティブな場合は、すぐに共有データを処理
    if UIApplication.shared.applicationState == .active {
      NSLog("[Runner] App is active, processing shared data immediately")
      if let data = getSharedData() {
        shareChannel?.invokeMethod("onSharedData", arguments: data)
      }
    } else {
      // バックグラウンドの場合、アクティブになるまで待つ
      NSLog("[Runner] App is in background, will process when active")
      // applicationDidBecomeActive で処理される
    }
  }
  
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    
    // アプリがアクティブになったときに共有データがあれば処理
    NSLog("[Runner] applicationDidBecomeActive")
    if let data = getSharedData() {
      NSLog("[Runner] Found shared data, notifying Flutter")
      shareChannel?.invokeMethod("onSharedData", arguments: data)
    }
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
  
  // MARK: - Share Extension Support
  
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    // カスタムURLスキームからの起動をハンドル
    if url.scheme == "bookmarkapp" && url.host == "share" {
      // 共有データがあることをFlutterに通知
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        if let data = self?.getSharedData() {
          self?.shareChannel?.invokeMethod("onSharedData", arguments: data)
        }
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }
  
  // MARK: - Universal Links
  override func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else {
      return false
    }
    NSLog("[Runner] continue userActivity: \(url.absoluteString)")
    
    // Handle Universal Link: https://shigoshi-gogo.com/share
    if url.host == "shigoshi-gogo.com" && url.path == "/share" {
      // Give Flutter a short moment to be ready, then deliver shared data
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        if let data = self?.getSharedData() {
          self?.shareChannel?.invokeMethod("onSharedData", arguments: data)
        }
      }
      return true
    }
    return false
  }
  
  private func getSharedData() -> [String: String]? {
    guard let userDefaults = UserDefaults(suiteName: "group.com.hashinokuchi.bookmark") else {
      return nil
    }
    
    // キューから最初の要素を取得（取り出さない、peek のみ）
    guard let queue = userDefaults.array(forKey: "shared_bookmarks_queue") as? [[String: String]],
          !queue.isEmpty,
          let firstBookmark = queue.first else {
      return nil
    }
    
    return firstBookmark
  }
  
  private func clearSharedData() {
    guard let userDefaults = UserDefaults(suiteName: "group.com.hashinokuchi.bookmark") else {
      return
    }
    
    // キューから最初の要素を削除
    if var queue = userDefaults.array(forKey: "shared_bookmarks_queue") as? [[String: String]],
       !queue.isEmpty {
      queue.removeFirst()
      
      if queue.isEmpty {
        // キューが空になったらすべてクリア
        userDefaults.removeObject(forKey: "shared_bookmarks_queue")
        userDefaults.removeObject(forKey: "has_pending_share")
        NSLog("[Runner] Cleared last bookmark from queue")
      } else {
        // まだデータが残っている場合は更新
        userDefaults.set(queue, forKey: "shared_bookmarks_queue")
        NSLog("[Runner] Removed first bookmark from queue, \(queue.count) remaining")
      }
      
      userDefaults.synchronize()
    }
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
