import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bookmark_model.dart';
import '../models/tag_model.dart';

class BookmarkRepository {
  final SupabaseClient _supabase;

  BookmarkRepository(this._supabase);

  /// すべてのブックマークを取得（タグ情報含む、ユーザーIDでフィルタ）
  Future<List<BookmarkModel>> fetchAll(List<TagModel> allTags, String? userId) async {
    try {
      // ブックマーク取得
      final query = _supabase.from('bookmarks').select();
      
      final bookmarksData = userId != null
          ? await query.eq('user_id', userId).order('created_at', ascending: false)
          : await query.order('created_at', ascending: false);

      // 各ブックマークのタグを取得
      final List<BookmarkModel> loadedBookmarks = [];
      for (final bmData in bookmarksData as List) {
        final tagIds = await _supabase
            .from('bookmark_tags')
            .select('tag_id')
            .eq('bookmark_id', bmData['id']);

        final bookmarkTags = <TagModel>[];
        for (final tagId in tagIds as List) {
          try {
            final tag = allTags.firstWhere((t) => t.id == tagId['tag_id']);
            bookmarkTags.add(tag);
          } catch (e) {
            // タグが見つからない場合はスキップ
            debugPrint('Tag not found: ${tagId['tag_id']}');
          }
        }

        loadedBookmarks.add(BookmarkModel.fromJson(bmData, bookmarkTags));
      }

      return loadedBookmarks;
    } catch (e) {
      debugPrint('Error fetching bookmarks: $e');
      rethrow;
    }
  }

  /// フォルダ内のブックマークを取得（ユーザーIDでフィルタ）
  Future<List<BookmarkModel>> fetchByFolder(String folderId, List<TagModel> allTags, String? userId) async {
    try {
      var query = _supabase.from('bookmarks').select().eq('folder_id', folderId);
      
      if (userId != null) {
        query = query.eq('user_id', userId);
      }
      
      final bookmarksData = await query.order('created_at', ascending: false);

      final List<BookmarkModel> loadedBookmarks = [];
      for (final bmData in bookmarksData as List) {
        final tagIds = await _supabase
            .from('bookmark_tags')
            .select('tag_id')
            .eq('bookmark_id', bmData['id']);

        final bookmarkTags = <TagModel>[];
        for (final tagId in tagIds as List) {
          try {
            final tag = allTags.firstWhere((t) => t.id == tagId['tag_id']);
            bookmarkTags.add(tag);
          } catch (e) {
            debugPrint('Tag not found: ${tagId['tag_id']}');
          }
        }

        loadedBookmarks.add(BookmarkModel.fromJson(bmData, bookmarkTags));
      }

      return loadedBookmarks;
    } catch (e) {
      debugPrint('Error fetching bookmarks by folder: $e');
      rethrow;
    }
  }

  /// ブックマークを追加
  Future<BookmarkModel> create(BookmarkModel bookmark, String? userId) async {
    try {
      // ブックマーク挿入
      final data = bookmark.toJson();
      if (userId != null) {
        data['user_id'] = userId;
      }
      
      final response = await _supabase
          .from('bookmarks')
          .insert(data)
          .select()
          .single();

      final newId = response['id'];

      // タグ関連付け
      if (bookmark.tags.isNotEmpty) {
        final tagInserts = bookmark.tags
            .map((t) => {
                  'bookmark_id': newId,
                  'tag_id': t.id,
                })
            .toList();
        await _supabase.from('bookmark_tags').insert(tagInserts);
      }

      return BookmarkModel.fromJson(response, bookmark.tags);
    } catch (e) {
      debugPrint('Error creating bookmark: $e');
      rethrow;
    }
  }

  /// ブックマークを更新
  Future<void> update(BookmarkModel bookmark) async {
    try {
      // ブックマーク更新
      await _supabase
          .from('bookmarks')
          .update(bookmark.toJson())
          .eq('id', bookmark.id);

      // タグ関連付けを更新（既存削除→再挿入）
      await _supabase
          .from('bookmark_tags')
          .delete()
          .eq('bookmark_id', bookmark.id);

      if (bookmark.tags.isNotEmpty) {
        final tagInserts = bookmark.tags
            .map((t) => {
                  'bookmark_id': bookmark.id,
                  'tag_id': t.id,
                })
            .toList();
        await _supabase.from('bookmark_tags').insert(tagInserts);
      }
    } catch (e) {
      debugPrint('Error updating bookmark: $e');
      rethrow;
    }
  }

  /// ブックマークを削除
  Future<void> delete(String id) async {
    try {
      await _supabase
          .from('bookmarks')
          .delete()
          .eq('id', id);
    } catch (e) {
      debugPrint('Error deleting bookmark: $e');
      rethrow;
    }
  }

  /// 既読/未読を切り替え
  Future<void> toggleRead(BookmarkModel bookmark) async {
    bookmark.readAt = bookmark.readAt == null ? DateTime.now() : null;
    await update(bookmark);
  }

  /// ピン留めを切り替え
  Future<void> togglePin(BookmarkModel bookmark) async {
    bookmark.isPinned = !bookmark.isPinned;
    await update(bookmark);
  }

  /// 開封数を増加
  Future<void> incrementOpenCount(BookmarkModel bookmark) async {
    bookmark.openCount += 1;
    bookmark.lastOpenedAt = DateTime.now();
    await update(bookmark);
  }
}
