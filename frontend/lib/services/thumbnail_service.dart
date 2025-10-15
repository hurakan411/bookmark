import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class ThumbnailService {
  static const MethodChannel _channel = MethodChannel('bookmark.snapshot');

  /// サムネイルを取得（スクショ→OGP→ファビコンの順にフォールバック）
  static Future<String?> getThumbnailWithFallback(String url) async {
    // 1. スクリーンショットを試す（iOSのみ）
    if (Platform.isIOS) {
      final snapshot = await ensureSnapshot(url);
      if (snapshot != null && snapshot.isNotEmpty) {
        debugPrint('Thumbnail: スクリーンショット取得成功');
        return snapshot;
      }
      debugPrint('Thumbnail: スクリーンショット取得失敗、OGP画像を試行');
    }

    // 2. OGP画像を試す
    final ogpImage = await _fetchOGPImage(url);
    if (ogpImage != null && ogpImage.isNotEmpty) {
      final savedPath = await _downloadAndSaveImage(ogpImage, url, 'ogp');
      if (savedPath != null) {
        debugPrint('Thumbnail: OGP画像取得成功');
        return savedPath;
      }
    }
    debugPrint('Thumbnail: OGP画像取得失敗、ファビコンを試行');

    // 3. ファビコンを試す
    final favicon = await _fetchFavicon(url);
    if (favicon != null && favicon.isNotEmpty) {
      final savedPath = await _downloadAndSaveImage(favicon, url, 'favicon');
      if (savedPath != null) {
        debugPrint('Thumbnail: ファビコン取得成功');
        return savedPath;
      }
    }

    debugPrint('Thumbnail: すべての取得方法が失敗');
    return null;
  }

  /// HTMLからOGP画像URLを取得
  static Future<String?> _fetchOGPImage(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) {
        return null;
      }

      final document = html_parser.parse(response.body);
      
      // og:image を探す
      final ogImage = document.querySelector('meta[property="og:image"]');
      if (ogImage != null) {
        final content = ogImage.attributes['content'];
        if (content != null && content.isNotEmpty) {
          return _resolveUrl(url, content);
        }
      }

      // twitter:image を探す
      final twitterImage = document.querySelector('meta[name="twitter:image"]');
      if (twitterImage != null) {
        final content = twitterImage.attributes['content'];
        if (content != null && content.isNotEmpty) {
          return _resolveUrl(url, content);
        }
      }

      return null;
    } catch (e) {
      debugPrint('OGP画像取得エラー: $e');
      return null;
    }
  }

  /// ファビコンURLを取得
  static Future<String?> _fetchFavicon(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) {
        // HTMLが取得できない場合は、デフォルトのファビコンパスを試す
        final defaultFavicon = '${uri.scheme}://${uri.host}/favicon.ico';
        return defaultFavicon;
      }

      final document = html_parser.parse(response.body);
      
      // link[rel="icon"] を探す
      final iconLink = document.querySelector('link[rel="icon"]') ??
                      document.querySelector('link[rel="shortcut icon"]') ??
                      document.querySelector('link[rel="apple-touch-icon"]');
      
      if (iconLink != null) {
        final href = iconLink.attributes['href'];
        if (href != null && href.isNotEmpty) {
          return _resolveUrl(url, href);
        }
      }

      // デフォルトのファビコンパスを返す
      return '${uri.scheme}://${uri.host}/favicon.ico';
    } catch (e) {
      debugPrint('ファビコン取得エラー: $e');
      // エラーの場合もデフォルトパスを試す
      try {
        final uri = Uri.parse(url);
        return '${uri.scheme}://${uri.host}/favicon.ico';
      } catch (_) {
        return null;
      }
    }
  }

  /// 相対URLを絶対URLに変換
  static String _resolveUrl(String baseUrl, String relativeUrl) {
    if (relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }
    
    final uri = Uri.parse(baseUrl);
    if (relativeUrl.startsWith('//')) {
      return '${uri.scheme}:$relativeUrl';
    }
    if (relativeUrl.startsWith('/')) {
      return '${uri.scheme}://${uri.host}$relativeUrl';
    }
    
    // 相対パスの場合
    final basePath = uri.path.substring(0, uri.path.lastIndexOf('/') + 1);
    return '${uri.scheme}://${uri.host}$basePath$relativeUrl';
  }

  /// 画像をダウンロードして保存
  static Future<String?> _downloadAndSaveImage(String imageUrl, String sourceUrl, String type) async {
    try {
      final response = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) {
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'thumb_${type}_${sourceUrl.hashCode}.${_getExtension(imageUrl)}';
      final outPath = p.join(dir.path, fileName);
      final file = File(outPath);
      
      await file.writeAsBytes(response.bodyBytes);
      return outPath;
    } catch (e) {
      debugPrint('画像ダウンロードエラー: $e');
      return null;
    }
  }

  /// URLから拡張子を取得（デフォルトはpng）
  static String _getExtension(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'jpg';
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.gif')) return 'gif';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.ico')) return 'ico';
    return 'png'; // デフォルト
  }

  // 既存のスクリーンショット取得メソッド
  // Returns local file path to thumbnail or null on failure.
  static Future<String?> ensureSnapshot(String url, {int width = 1024, int height = 768}) async {
    if (!Platform.isIOS) return null; // iOSのみ実装
    try {
  final dir = await getApplicationDocumentsDirectory();
      final fileName = 'thumb_${url.hashCode}.png';
      final outPath = p.join(dir.path, fileName);
      final file = File(outPath);
      if (await file.exists()) {
        return outPath;
      }
      final result = await _channel.invokeMethod<String>('takeSnapshot', {
        'url': url,
        'width': width,
        'height': height,
        'outPath': outPath,
      });
      if (result != null && result.isNotEmpty) {
        return result;
      }
    } catch (e) {
      // ネットワークエラーやページ読み込み失敗は想定内のエラー
      if (e is PlatformException) {
        switch (e.code) {
          case 'LOAD_ERROR':
            debugPrint('Thumbnail: ページの読み込みに失敗 - URL: $url');
            break;
          case 'TIMEOUT_ERROR':
            debugPrint('Thumbnail: タイムアウト（15秒） - URL: $url');
            break;
          case 'URL_ERROR':
            debugPrint('Thumbnail: 無効なURL - $url');
            break;
          default:
            debugPrint('Thumbnail: ${e.code} - ${e.message}');
        }
      } else {
        debugPrint('Thumbnail: サムネイル取得失敗 - $e');
      }
    }
    return null;
  }
}
