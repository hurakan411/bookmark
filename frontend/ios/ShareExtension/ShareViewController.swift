import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers
import os
import WebKit

/// Share Sheet 上にポップアップを表示して、アプリと同等の「ブックマーク追加」体験を提供する
class ShareViewController: UIViewController, UITextFieldDelegate {
    private let appGroupId = "group.com.hashinokuchi.bookmark"
    private let logPrefix = "[ShareExt]"

    // 取得した共有コンテンツ
    private var sharedURL: URL?
    private var initialTitle: String?

    // 追加項目は廃止（タイトルは上部のテキストエリアを使用）

    // プレビュー（サムネイル表示）
    private let titleTextField = UITextField()
    private let previewImageView = UIImageView()
    private var downloadedThumbPath: String?

    // スナップショット用 WebView/Delegate を保持（解放タイミング管理）
    private var snapshotWebView: WKWebView?
    private var snapshotNavDelegate: SnapshotNavDelegate?

    private class SnapshotNavDelegate: NSObject, WKNavigationDelegate {
        let onFinish: (_ success: Bool, _ error: Error?) -> Void
        init(onFinish: @escaping (_ success: Bool, _ error: Error?) -> Void) { self.onFinish = onFinish }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish(true, nil) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinish(false, error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFinish(false, error) }
    }

    // ログユーティリティ
    private var oslogger: OSLog {
        if #available(iOS 12.0, *) {
            return OSLog(subsystem: "com.example.bookmarkMock", category: "ShareExtension")
        } else {
            return .default
        }
    }
    private func dlog(_ message: String) {
        let msg = "\(logPrefix) \(message)"
        print(msg)
        if #available(iOS 12.0, *) {
            os_log("%{public}@", log: oslogger, type: .info, msg)
        } else {
            NSLog("%{public}@", msg)
        }
        if let ud = UserDefaults(suiteName: appGroupId) {
            ud.set(Date().timeIntervalSince1970, forKey: "debug_last_ts")
            ud.set(message, forKey: "debug_last_step")
            ud.synchronize()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dlog("viewDidLoad")
        setupUI()
        // 入力アイテムからURL/タイトルを抽出し、テキスト欄（タイトル）を初期化
        handleSharedContentAndPrefill()
    }
    
    private func setupUI() {
        // 背景
        view.backgroundColor = UIColor.systemBackground
        
        // ナビゲーションバー
        let navBar = UINavigationBar()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navBar)
        
        let navItem = UINavigationItem(title: "ブックマーク追加")
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(handleCancel))
        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(handleSave))
        navItem.leftBarButtonItem = cancelButton
        navItem.rightBarButtonItem = saveButton
        navBar.items = [navItem]
        
        // スクロールビュー
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        // タイトルセクション
        let titleContainer = createTitleSection()
        contentView.addSubview(titleContainer)
        
        // サムネイルセクション
        let thumbContainer = createThumbnailSection()
        contentView.addSubview(thumbContainer)
        
        NSLayoutConstraint.activate([
            // ナビゲーションバー
            navBar.topAnchor.constraint(equalTo: view.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // スクロールビュー
            scrollView.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // コンテンツビュー
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // タイトルセクション
            titleContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // サムネイルセクション
            thumbContainer.topAnchor.constraint(equalTo: titleContainer.bottomAnchor, constant: 16),
            thumbContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumbContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            thumbContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }
    
    @objc private func handleCancel() {
        dlog("handleCancel")
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    @objc private func handleSave() {
        dlog("handleSave: saving to App Group")
        saveShareToAppGroup()
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private func createTitleSection() -> UIView {
        let titleContainer = UIView()
        titleContainer.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.backgroundColor = UIColor.systemBackground
        titleContainer.layer.cornerRadius = 10
        titleContainer.layer.borderColor = UIColor.separator.cgColor
        titleContainer.layer.borderWidth = 0.5
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "タイトル"
        titleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = UIColor.secondaryLabel
        titleContainer.addSubview(titleLabel)
        
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.font = UIFont.preferredFont(forTextStyle: .body)
        titleTextField.textColor = UIColor.label
        titleTextField.text = initialTitle ?? "読み込み中..."
        titleTextField.borderStyle = .none
        titleTextField.returnKeyType = .done
        titleTextField.delegate = self
        titleContainer.addSubview(titleTextField)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor, constant: 8),
            
            titleTextField.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 12),
            titleTextField.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -12),
            titleTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            titleTextField.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor, constant: -8),
            
            titleContainer.heightAnchor.constraint(equalToConstant: 70),
        ])
        
        return titleContainer
    }
    
    private func createThumbnailSection() -> UIView {
        let thumbContainer = UIView()
        thumbContainer.translatesAutoresizingMaskIntoConstraints = false
        thumbContainer.backgroundColor = UIColor.systemBackground
        thumbContainer.layer.cornerRadius = 10
        thumbContainer.layer.borderColor = UIColor.separator.cgColor
        thumbContainer.layer.borderWidth = 0.5
        
        let thumbLabel = UILabel()
        thumbLabel.translatesAutoresizingMaskIntoConstraints = false
        thumbLabel.text = "サムネイル"
        thumbLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        thumbLabel.textColor = UIColor.secondaryLabel
        thumbContainer.addSubview(thumbLabel)
        
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.contentMode = .scaleAspectFit
        previewImageView.clipsToBounds = true
        previewImageView.layer.cornerRadius = 8
        previewImageView.backgroundColor = UIColor(white: 0.96, alpha: 1.0)
        if #available(iOS 13.0, *) {
            let placeholder = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
            previewImageView.image = placeholder
            previewImageView.tintColor = UIColor.systemGray3
        }
        thumbContainer.addSubview(previewImageView)
        
        NSLayoutConstraint.activate([
            thumbLabel.leadingAnchor.constraint(equalTo: thumbContainer.leadingAnchor, constant: 12),
            thumbLabel.topAnchor.constraint(equalTo: thumbContainer.topAnchor, constant: 8),
            
            previewImageView.leadingAnchor.constraint(equalTo: thumbContainer.leadingAnchor, constant: 12),
            previewImageView.trailingAnchor.constraint(equalTo: thumbContainer.trailingAnchor, constant: -12),
            previewImageView.topAnchor.constraint(equalTo: thumbLabel.bottomAnchor, constant: 8),
            previewImageView.bottomAnchor.constraint(equalTo: thumbContainer.bottomAnchor, constant: -12),
            
            thumbContainer.heightAnchor.constraint(equalToConstant: 400),
        ])
        
        return thumbContainer
    }

    // MARK: - Data extraction & saving
    private func handleSharedContentAndPrefill() {
        dlog("handleSharedContent:start")
        guard let extItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extItem.attachments?.first else {
            dlog("handleSharedContent:no extension item or attachment")
            return
        }

        let assignAndPrefill: (URL) -> Void = { [weak self, weak extItem] url in
            guard let self = self else { return }
            self.sharedURL = url
            // タイトル初期値: 共有元がくれる attributedContentText またはURLホスト
            let title = extItem?.attributedContentText?.string
            self.initialTitle = (title?.isEmpty == false) ? title : url.absoluteString
            // サムネイルを自動取得（まずスクショ、その後フォールバック）
            self.fetchSnapshotThenFallback(from: url)
            // プレビュー内のタイトルを初期化
            DispatchQueue.main.async { [weak self] in self?.titleTextField.text = self?.initialTitle }
        }

        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            dlog("itemProvider: has URL type")
            itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                DispatchQueue.main.async {
                    if let error = error { self?.dlog("loadItem URL error: \(error.localizedDescription)") }
                    if let url = item as? URL {
                        self?.dlog("loadItem URL success: \(url.absoluteString)")
                        assignAndPrefill(url)
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        self?.dlog("loadItem URL(Data) success: \(url.absoluteString)")
                        assignAndPrefill(url)
                    } else {
                        self?.dlog("loadItem URL: unsupported item type")
                    }
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
            dlog("itemProvider: has propertyList type")
            itemProvider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { [weak self] (item, error) in
                DispatchQueue.main.async {
                    if let error = error { self?.dlog("loadItem propertyList error: \(error.localizedDescription)") }
                    guard let dictionary = item as? [String: Any],
                          let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any],
                          let urlString = results["url"] as? String,
                          let url = URL(string: urlString) else {
                        self?.dlog("propertyList: missing fields")
                        return
                    }
                    self?.dlog("propertyList success: \(url.absoluteString)")
                    assignAndPrefill(url)
                }
            }
        } else {
            dlog("itemProvider: no supported type (URL/propertyList)")
        }
    }

    private func saveShareToAppGroup() {
        guard let url = sharedURL else {
            dlog("saveShareToAppGroup: no URL -> abort")
            return
        }
        // タイトルはtitleTextFieldから取得
        let titleToSave = titleTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? initialTitle ?? url.absoluteString
        
        guard let ud = UserDefaults(suiteName: appGroupId) else {
            dlog("saveShareToAppGroup: failed to get UserDefaults with app group (\(appGroupId))")
            return
        }
        
        // 既存のキューを取得（配列として保存）
        var queue = ud.array(forKey: "shared_bookmarks_queue") as? [[String: String]] ?? []
        
        // 新しいブックマークデータを作成
        var bookmarkData: [String: String] = [
            "url": url.absoluteString,
            "title": titleToSave,
            "timestamp": "\(Date().timeIntervalSince1970)"
        ]
        
        if let thumb = downloadedThumbPath {
            bookmarkData["thumbnail_path"] = thumb
        }
        
        // キューに追加
        queue.append(bookmarkData)
        
        // キューを保存
        ud.set(queue, forKey: "shared_bookmarks_queue")
        ud.set(true, forKey: "has_pending_share")
        ud.synchronize()
        
        dlog("saveShareToAppGroup: added bookmark to queue (total: \(queue.count))")
        
        // Darwin Notification を送信してアプリに通知
        let notificationName = "com.hashinokuchi.bookmark.shareExtensionDidSaveData" as CFString
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(notificationName), nil, nil, true)
        dlog("saveShareToAppGroup: posted Darwin notification")
    }

    // MARK: - Helpers
    private func fetchThumbnail(from url: URL) {
        guard let scheme = url.scheme, let host = url.host else { return }
        let candidates = [
            "\(scheme)://\(host)/apple-touch-icon.png",
            "\(scheme)://\(host)/favicon.ico"
        ]

        func tryNext(_ index: Int) {
            if index >= candidates.count { return }
            guard let u = URL(string: candidates[index]) else { return }
            let task = URLSession.shared.dataTask(with: u) { [weak self] data, resp, err in
                if let data = data, let img = UIImage(data: data) {
                    // プレビューに表示
                    DispatchQueue.main.async { self?.previewImageView.image = img }
                    // App Groupに保存してパスを共有
                    if let path = self?.saveImageToAppGroup(img) {
                        self?.downloadedThumbPath = path
                    }
                } else {
                    tryNext(index + 1)
                }
            }
            task.resume()
        }
        tryNext(0)
    }

    private func fetchSnapshotThenFallback(from url: URL) {
        DispatchQueue.main.async {
            let config = WKWebViewConfiguration()
            config.defaultWebpagePreferences.preferredContentMode = .mobile
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
            self.snapshotWebView = wv

            // タイムアウト（12秒）
            var finished = false
            let timeout = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if finished { return }
                finished = true
                self.dlog("snapshot: timeout -> fallback to icons")
                self.cleanupSnapshot()
                self.fetchThumbnail(from: url)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: timeout)

            let delegate = SnapshotNavDelegate { [weak self] success, error in
                guard let self = self else { return }
                if finished { return }
                finished = true
                timeout.cancel()
                if !success {
                    self.dlog("snapshot: load failed -> fallback")
                    self.cleanupSnapshot()
                    self.fetchThumbnail(from: url)
                    return
                }
                let shotConfig = WKSnapshotConfiguration()
                shotConfig.rect = CGRect(origin: .zero, size: CGSize(width: 1024, height: 768))
                self.snapshotWebView?.takeSnapshot(with: shotConfig) { [weak self] image, err in
                    guard let self = self else { return }
                    if let img = image {
                        DispatchQueue.main.async { self.previewImageView.image = img }
                        if let path = self.saveImageToAppGroup(img) { self.downloadedThumbPath = path }
                        self.dlog("snapshot: success")
                    } else {
                        self.dlog("snapshot: nil image -> fallback")
                        self.fetchThumbnail(from: url)
                    }
                    self.cleanupSnapshot()
                }
            }

            self.snapshotNavDelegate = delegate
            wv.navigationDelegate = delegate
            var req = URLRequest(url: url)
            req.timeoutInterval = 12.0
            wv.load(req)
        }
    }

    private func cleanupSnapshot() {
        snapshotWebView?.navigationDelegate = nil
        snapshotNavDelegate = nil
        snapshotWebView = nil
    }

    private func saveImageToAppGroup(_ image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return nil }
        let dir = containerURL.appendingPathComponent("SharedThumbnails", isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { }
        let filename = "thumb_\(UUID().uuidString).png"
        let fileURL = dir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            return nil
        }
    }
    private func presentTextInputAlert(title: String, message: String?, placeholder: String?, current: String?, onDone: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = placeholder
            tf.text = current
        }
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel, handler: { _ in onDone(nil) }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            let text = alert.textFields?.first?.text
            onDone(text)
        }))
        self.present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate
extension ShareViewController {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
