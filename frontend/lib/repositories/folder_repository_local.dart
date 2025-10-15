import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/folder_model.dart';

class FolderRepository {
  final Future<Database> Function() _getDatabase;

  FolderRepository(this._getDatabase);

  /// すべてのフォルダを取得（階層構造）
  Future<List<FolderModel>> fetchAll() async {
    try {
      final db = await _getDatabase();
      final List<Map<String, dynamic>> maps = await db.query(
        'folders',
        orderBy: 'name ASC',
      );
      
      final allFolders = maps.map((json) => FolderModel.fromJson(json)).toList();
      
      // ルートフォルダ（parent_idがnullのもの）を抽出し、子を再帰的にセット
      final rootFolders = allFolders.where((f) => f.parentId == null).toList();
      for (var folder in rootFolders) {
        _buildChildren(folder, allFolders);
      }
      return rootFolders;
    } catch (e) {
      debugPrint('Error fetching folders: $e');
      rethrow;
    }
  }

  void _buildChildren(FolderModel parent, List<FolderModel> allFolders) {
    parent.children = allFolders.where((f) => f.parentId == parent.id).toList();
    for (var child in parent.children) {
      _buildChildren(child, allFolders);
    }
  }

  /// すべてのフォルダをフラットに取得
  Future<List<FolderModel>> fetchAllFlat() async {
    try {
      final db = await _getDatabase();
      final List<Map<String, dynamic>> maps = await db.query(
        'folders',
        orderBy: 'name ASC',
      );
      
      return maps.map((json) => FolderModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching folders: $e');
      rethrow;
    }
  }

  /// フォルダを追加
  Future<FolderModel> create(String name, {String? parentId, int? sortOrder}) async {
    try {
      final db = await _getDatabase();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      
      await db.insert(
        'folders',
        {
          'id': id,
          'name': name,
          'parent_id': parentId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      final folder = FolderModel(id: id, name: name, parentId: parentId);
      folder.children = [];
      return folder;
    } catch (e) {
      debugPrint('Error creating folder: $e');
      rethrow;
    }
  }

  /// フォルダを更新
  Future<void> update(String id, String name, {String? parentId, int? sortOrder}) async {
    try {
      final db = await _getDatabase();
      final Map<String, dynamic> updates = {'name': name};
      updates['parent_id'] = parentId;
      if (sortOrder != null) {
        updates['sort_order'] = sortOrder;
      }
      await db.update(
        'folders',
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Error updating folder: $e');
      rethrow;
    }
  }

  /// フォルダを削除
  Future<void> delete(String id) async {
    try {
      final db = await _getDatabase();
      await db.delete(
        'folders',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Error deleting folder: $e');
      rethrow;
    }
  }
}
