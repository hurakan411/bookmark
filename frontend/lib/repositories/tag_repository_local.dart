import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/tag_model.dart';

class TagRepository {
  final Future<Database> Function() _getDatabase;

  TagRepository(this._getDatabase);

  /// すべてのタグを取得
  Future<List<TagModel>> fetchAll() async {
    try {
      final db = await _getDatabase();
      final List<Map<String, dynamic>> maps = await db.query(
        'tags',
        orderBy: 'name ASC',
      );
      
      return maps.map((json) => TagModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching tags: $e');
      rethrow;
    }
  }

  /// タグを追加
  Future<TagModel> create(String name) async {
    try {
      final db = await _getDatabase();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      
      await db.insert(
        'tags',
        {'id': id, 'name': name},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      return TagModel(id: id, name: name);
    } catch (e) {
      debugPrint('Error creating tag: $e');
      rethrow;
    }
  }

  /// タグを更新
  Future<void> update(String id, String name) async {
    try {
      final db = await _getDatabase();
      await db.update(
        'tags',
        {'name': name},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Error updating tag: $e');
      rethrow;
    }
  }

  /// タグを削除
  Future<void> delete(String id) async {
    try {
      final db = await _getDatabase();
      // 関連するbookmark_tagsも削除
      await db.delete(
        'bookmark_tags',
        where: 'tag_id = ?',
        whereArgs: [id],
      );
      await db.delete(
        'tags',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Error deleting tag: $e');
      rethrow;
    }
  }
}
