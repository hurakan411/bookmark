import 'dart:convert';
import 'package:http/http.dart' as http;

class TagSuggestionService {
  // バックエンドAPIのベースURL（開発環境用）
  // 本番環境では適切なURLに変更してください
  static const String baseUrl = 'http://localhost:8000';

  /// ブックマーク情報から適切なタグを自動提案
  /// 
  /// [title] ブックマークのタイトル
  /// [url] ブックマークのURL
  /// [excerpt] ブックマークのメモ・要約
  /// [existingTags] 既存のタグリスト
  /// 
  /// 戻り値: 提案されたタグ名のリスト
  static Future<List<String>> suggestTags({
    required String title,
    required String url,
    required String excerpt,
    required List<String> existingTags,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/suggest-tags'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'title': title,
          'url': url,
          'excerpt': excerpt,
          'existing_tags': existingTags,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('リクエストがタイムアウトしました');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final suggestedTags = (data['suggested_tags'] as List)
            .map((tag) => tag.toString())
            .toList();
        return suggestedTags;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'タグの提案に失敗しました');
      }
    } catch (e) {
      throw Exception('タグ提案APIの呼び出しに失敗しました: $e');
    }
  }

  /// APIの接続チェック
  static Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['openai_api_configured'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
