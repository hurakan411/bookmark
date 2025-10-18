import 'package:flutter/services.dart';

class ShareExtensionService {
  static const MethodChannel _channel = MethodChannel('bookmark.share');

  /// 共有データを取得
  static Future<Map<String, String>?> getSharedData() async {
    try {
      final result = await _channel.invokeMethod('getSharedData');
      if (result != null && result is Map) {
        return Map<String, String>.from(result);
      }
      return null;
    } catch (e) {
      print('Error getting shared data: $e');
      return null;
    }
  }

  /// 共有データをクリア
  static Future<void> clearSharedData() async {
    try {
      await _channel.invokeMethod('clearSharedData');
    } catch (e) {
      print('Error clearing shared data: $e');
    }
  }

  /// 共有データがあるかチェック
  static Future<bool> hasSharedData() async {
    final data = await getSharedData();
    return data != null && data.containsKey('url');
  }

  /// 初期化（アプリ起動時に一度だけ呼ぶ）
  static void initialize() {
    // MethodChannelの準備
    _channel.setMethodCallHandler((call) async {
      // 必要に応じてコールバックを処理
      return null;
    });
  }

  /// 共有データのコールバックを設定
  static void setOnSharedDataCallback(Function(Map<String, String>) callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedData') {
        final data = Map<String, String>.from(call.arguments);
        callback(data);
      }
      return null;
    });
  }
}
