import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tag_model.dart';

class TagRepository {
  final SupabaseClient _supabase;

  TagRepository(this._supabase);

  /// すべてのタグを取得（ユーザーIDでフィルタ）
  Future<List<TagModel>> fetchAll(String? userId) async {
    try {
      final query = _supabase.from('tags').select();
      
      final response = userId != null 
          ? await query.eq('user_id', userId).order('name')
          : await query.order('name');
      
      return (response as List)
          .map((json) => TagModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching tags: $e');
      rethrow;
    }
  }

  /// タグを追加
  Future<TagModel> create(String name, String? userId) async {
    try {
      final data = {'name': name};
      if (userId != null) {
        data['user_id'] = userId;
      }
      
      final response = await _supabase
          .from('tags')
          .insert(data)
          .select()
          .single();
      
      return TagModel.fromJson(response);
    } catch (e) {
      debugPrint('Error creating tag: $e');
      rethrow;
    }
  }

  /// タグを更新
  Future<void> update(String id, String name) async {
    try {
      await _supabase
          .from('tags')
          .update({'name': name})
          .eq('id', id);
    } catch (e) {
      debugPrint('Error updating tag: $e');
      rethrow;
    }
  }

  /// タグを削除
  Future<void> delete(String id) async {
    try {
      await _supabase
          .from('tags')
          .delete()
          .eq('id', id);
    } catch (e) {
      debugPrint('Error deleting tag: $e');
      rethrow;
    }
  }

  /// タグ名で検索（重複チェック用）
  Future<bool> existsByName(String name, {String? excludeId}) async {
    try {
      var query = _supabase
          .from('tags')
          .select('id')
          .ilike('name', name);
      
      if (excludeId != null) {
        query = query.neq('id', excludeId);
      }
      
      final response = await query;
      return (response as List).isNotEmpty;
    } catch (e) {
      debugPrint('Error checking tag existence: $e');
      rethrow;
    }
  }
}
