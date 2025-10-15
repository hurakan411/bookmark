import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/bookmark_model.dart';
import '../models/tag_model.dart';

class BookmarkRepository {
  final Future<Database> Function() _getDatabase;

  BookmarkRepository(this._getDatabase);

  /// すべてのブックマークを取得
  Future<List<BookmarkModel>> fetchAll(List<TagModel> allTags) async {
    try {
      final db = await _getDatabase();
      final List<Map<String, dynamic>> maps = await db.query(
        'bookmarks',
        orderBy: 'created_at DESC',
      );
      
      List<BookmarkModel> bookmarks = [];
      for (var json in maps) {
        // このブックマークに紐づくタグを取得
        final tagMaps = await db.rawQuery('''
          SELECT tags.* FROM tags
          INNER JOIN bookmark_tags ON tags.id = bookmark_tags.tag_id
          WHERE bookmark_tags.bookmark_id = ?
        ''', [json['id']]);
        
        final tags = tagMaps.map((t) => TagModel.fromJson(t)).toList();
        bookmarks.add(BookmarkModel.fromJson(json, tags));
      }
      
      return bookmarks;
    } catch (e) {
      debugPrint('Error fetching bookmarks: $e');
      rethrow;
    }
  }

  /// ブックマークを追加
  Future<void> create(BookmarkModel bm) async {
    try {
      final db = await _getDatabase();
      
      // bookmarksテーブルに挿入
      await db.insert(
        'bookmarks',
        {
          'id': bm.id,
          'url': bm.url,
          'title': bm.title,
          'excerpt': bm.excerpt,
          'created_at': bm.createdAt.toIso8601String(),
          'read_at': bm.readAt?.toIso8601String(),
          'is_pinned': bm.isPinned ? 1 : 0,
          'is_archived': bm.isArchived ? 1 : 0,
          'folder_id': bm.folderId,
          'open_count': bm.openCount,
          'last_opened_at': bm.lastOpenedAt?.toIso8601String(),
          'thumbnail_url': bm.thumbnailUrl,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      // bookmark_tagsテーブルにタグとの関連を挿入
      for (var tag in bm.tags) {
        await db.insert(
          'bookmark_tags',
          {'bookmark_id': bm.id, 'tag_id': tag.id},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      debugPrint('Error creating bookmark: $e');
      rethrow;
    }
  }

  /// ブックマークを更新
  Future<void> update(BookmarkModel bm) async {
    try {
      final db = await _getDatabase();
      
      // bookmarksテーブルを更新
      await db.update(
        'bookmarks',
        {
          'url': bm.url,
          'title': bm.title,
          'excerpt': bm.excerpt,
          'read_at': bm.readAt?.toIso8601String(),
          'is_pinned': bm.isPinned ? 1 : 0,
          'is_archived': bm.isArchived ? 1 : 0,
          'folder_id': bm.folderId,
          'open_count': bm.openCount,
          'last_opened_at': bm.lastOpenedAt?.toIso8601String(),
          'thumbnail_url': bm.thumbnailUrl,
        },
        where: 'id = ?',
        whereArgs: [bm.id],
      );
      
      // bookmark_tagsを一度削除して再挿入
      await db.delete(
        'bookmark_tags',
        where: 'bookmark_id = ?',
        whereArgs: [bm.id],
      );
      for (var tag in bm.tags) {
        await db.insert(
          'bookmark_tags',
          {'bookmark_id': bm.id, 'tag_id': tag.id},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      debugPrint('Error updating bookmark: $e');
      rethrow;
    }
  }

  /// ブックマークを削除
  Future<void> delete(String id) async {
    try {
      final db = await _getDatabase();
      
      // bookmark_tagsも削除
      await db.delete(
        'bookmark_tags',
        where: 'bookmark_id = ?',
        whereArgs: [id],
      );
      
      await db.delete(
        'bookmarks',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Error deleting bookmark: $e');
      rethrow;
    }
  }

  /// 既読/未読を切り替え
  Future<void> toggleRead(BookmarkModel bm) async {
    try {
      final db = await _getDatabase();
      final newReadAt = bm.isRead ? null : DateTime.now().toIso8601String();
      
      await db.update(
        'bookmarks',
        {'read_at': newReadAt},
        where: 'id = ?',
        whereArgs: [bm.id],
      );
      
      // モデルも更新
      bm.readAt = bm.isRead ? null : DateTime.now();
    } catch (e) {
      debugPrint('Error toggling read: $e');
      rethrow;
    }
  }

  /// ピン留めを切り替え
  Future<void> togglePin(BookmarkModel bm) async {
    try {
      final db = await _getDatabase();
      bm.isPinned = !bm.isPinned;
      
      await db.update(
        'bookmarks',
        {'is_pinned': bm.isPinned ? 1 : 0},
        where: 'id = ?',
        whereArgs: [bm.id],
      );
    } catch (e) {
      debugPrint('Error toggling pin: $e');
      rethrow;
    }
  }

  /// 開いた回数をインクリメント
  Future<void> incrementOpenCount(BookmarkModel bm) async {
    try {
      final db = await _getDatabase();
      bm.openCount++;
      bm.lastOpenedAt = DateTime.now();
      
      await db.update(
        'bookmarks',
        {
          'open_count': bm.openCount,
          'last_opened_at': bm.lastOpenedAt!.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [bm.id],
      );
    } catch (e) {
      debugPrint('Error incrementing open count: $e');
      rethrow;
    }
  }
}
