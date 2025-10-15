import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/folder_model.dart';

class FolderRepository {
  final SupabaseClient _supabase;

  FolderRepository(this._supabase);

  /// すべてのフォルダを階層構造で取得（ユーザーIDでフィルタ）
  Future<List<FolderModel>> fetchAll(String? userId) async {
    try {
      final query = _supabase.from('folders').select();
      
      final response = userId != null
          ? await query.eq('user_id', userId).order('sort_order').order('name')
          : await query.order('sort_order').order('name');
      
      final folders = (response as List)
          .map((json) => FolderModel.fromJson(json))
          .toList();
      
      // 階層構造を構築
      return _buildHierarchy(folders);
    } catch (e) {
      debugPrint('Error fetching folders: $e');
      rethrow;
    }
  }

  /// フォルダ階層を構築
  List<FolderModel> _buildHierarchy(List<FolderModel> allFolders) {
    // ルートフォルダを抽出
    final rootFolders = allFolders.where((f) => f.isRoot).toList();
    
    // 各フォルダの子要素を設定
    for (final folder in allFolders) {
      folder.children = allFolders
          .where((f) => f.parentId == folder.id)
          .toList();
      
      // レベルを計算
      folder.level = _calculateLevel(folder, allFolders);
    }
    
    return rootFolders;
  }

  /// フォルダの階層レベルを計算
  int _calculateLevel(FolderModel folder, List<FolderModel> allFolders) {
    if (folder.isRoot) return 0;
    
    final parent = allFolders.where((f) => f.id == folder.parentId).firstOrNull;
    if (parent == null) return 0;
    
    return 1 + _calculateLevel(parent, allFolders);
  }

  /// フォルダをフラットなリストで取得（ドロップダウン用、ユーザーIDでフィルタ）
  Future<List<FolderModel>> fetchAllFlat(String? userId) async {
    try {
      final query = _supabase.from('folders').select();
      
      final response = userId != null
          ? await query.eq('user_id', userId).order('sort_order').order('name')
          : await query.order('sort_order').order('name');
      
      final folders = (response as List)
          .map((json) => FolderModel.fromJson(json))
          .toList();
      
      // レベルだけ計算
      for (final folder in folders) {
        folder.level = _calculateLevel(folder, folders);
      }
      
      return folders;
    } catch (e) {
      debugPrint('Error fetching folders flat: $e');
      rethrow;
    }
  }

  /// フォルダを追加
  Future<FolderModel> create(String name, {String? parentId, int sortOrder = 0, String? userId}) async {
    try {
      final data = {
        'name': name,
        'parent_id': parentId,
        'sort_order': sortOrder,
      };
      if (userId != null) {
        data['user_id'] = userId;
      }
      
      final response = await _supabase
          .from('folders')
          .insert(data)
          .select()
          .single();
      
      return FolderModel.fromJson(response);
    } catch (e) {
      debugPrint('Error creating folder: $e');
      rethrow;
    }
  }

  /// フォルダを更新
  Future<void> update(String id, String name, {String? parentId, int? sortOrder}) async {
    try {
      final data = <String, dynamic>{'name': name};
      if (parentId != null) data['parent_id'] = parentId;
      if (sortOrder != null) data['sort_order'] = sortOrder;
      
      await _supabase
          .from('folders')
          .update(data)
          .eq('id', id);
    } catch (e) {
      debugPrint('Error updating folder: $e');
      rethrow;
    }
  }

  /// フォルダを削除（子フォルダも一緒に削除される）
  Future<void> delete(String id) async {
    try {
      await _supabase
          .from('folders')
          .delete()
          .eq('id', id);
    } catch (e) {
      debugPrint('Error deleting folder: $e');
      rethrow;
    }
  }

  /// 子フォルダを取得
  Future<List<FolderModel>> fetchChildren(String parentId) async {
    try {
      final response = await _supabase
          .from('folders')
          .select()
          .eq('parent_id', parentId)
          .order('sort_order')
          .order('name');
      
      return (response as List)
          .map((json) => FolderModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching children folders: $e');
      rethrow;
    }
  }

  /// フォルダ内のブックマーク数を取得
  Future<int> countBookmarks(String folderId) async {
    try {
      final response = await _supabase
          .from('bookmarks')
          .select()
          .eq('folder_id', folderId);
      
      return (response as List).length;
    } catch (e) {
      debugPrint('Error counting bookmarks in folder: $e');
      rethrow;
    }
  }
}
