import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../main.dart'; // apiBaseUrlをインポート

class TagAnalysisService {
  /// 全ブックマークから最適なタグ構成を分析・提案
  static Future<TagStructureAnalysis> analyzeTagStructure({
    required List<Map<String, dynamic>> bookmarks,
    required List<String> currentTags,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/analyze-tag-structure'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookmarks': bookmarks,
          'current_tags': currentTags,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return TagStructureAnalysis.fromJson(data);
      } else {
        debugPrint('API Error: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        final error = response.statusCode == 404 
            ? 'エンドポイントが見つかりません。バックエンドのデプロイを確認してください。'
            : jsonDecode(utf8.decode(response.bodyBytes))['detail'] ?? 'タグ構成分析に失敗しました';
        throw Exception(error);
      }
    } catch (e) {
      debugPrint('Tag analysis error: $e');
      rethrow;
    }
  }
}

class TagStructureAnalysis {
  final List<SuggestedTag> suggestedTags;
  final List<String> tagsToRemove;
  final String overallReasoning;

  TagStructureAnalysis({
    required this.suggestedTags,
    required this.tagsToRemove,
    required this.overallReasoning,
  });

  factory TagStructureAnalysis.fromJson(Map<String, dynamic> json) {
    return TagStructureAnalysis(
      suggestedTags: (json['suggested_tags'] as List)
          .map((tag) => SuggestedTag.fromJson(tag))
          .toList(),
      tagsToRemove: List<String>.from(json['tags_to_remove'] ?? []),
      overallReasoning: json['overall_reasoning'] ?? '',
    );
  }
}

class SuggestedTag {
  final String name;
  final String description;
  final String reasoning;
  final List<String> mergeFrom;

  SuggestedTag({
    required this.name,
    required this.description,
    required this.reasoning,
    required this.mergeFrom,
  });

  factory SuggestedTag.fromJson(Map<String, dynamic> json) {
    return SuggestedTag(
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      reasoning: json['reasoning'] ?? '',
      mergeFrom: List<String>.from(json['merge_from'] ?? []),
    );
  }

  bool get isNewTag => mergeFrom.isEmpty;
  bool get isMergeTag => mergeFrom.isNotEmpty;
}
