import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' hide context;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

// Models
import 'models/tag_model.dart';
import 'models/folder_model.dart';
import 'models/bookmark_model.dart';
import 'marquee_text.dart';
import 'bulk_folder_assignment_result_sheet.dart';

// Repositories (SQLite版)
import 'repositories/tag_repository_local.dart';
import 'repositories/folder_repository_local.dart';
import 'repositories/bookmark_repository_local.dart';

import 'utils_title_fetcher.dart';

import '_accordion_folder_selector.dart';
import 'services/thumbnail_service.dart';
import 'services/tag_suggestion_service.dart';
import 'services/tag_analysis_service.dart';
import 'services/share_extension_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'widgets/rewarded_ad_manager.dart';
import 'widgets/ad_banner.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:in_app_review/in_app_review.dart';

// ====== API設定 ======
// バックエンドAPI環境の切り替え
enum ApiEnvironment {
  local,    // ローカル開発環境 (localhost:8000)
  render,   // Render.com 本番環境
}

// 現在の環境設定（ここを変更するだけで切り替え可能）
const ApiEnvironment currentApiEnvironment = ApiEnvironment.render;

// 環境ごとのベースURL
const Map<ApiEnvironment, String> apiBaseUrls = {
  ApiEnvironment.local: 'http://localhost:8000',
  ApiEnvironment.render: 'https://bookmark-zhnd.onrender.com',
};

// 現在使用するベースURL
String get apiBaseUrl => apiBaseUrls[currentApiEnvironment]!;

// ====== デバッグ用: リワード広告必須フラグ ======
const bool requireRewardedAdForAI = true; // falseで広告スキップ（デバッグ用）

// フォルダカードのアコーディオン展開/折りたたみアイコン付きタイル
class _AccordionFolderTile extends StatefulWidget {
  final FolderModel folder;
  final int count;
  final AppStore store;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget Function() childBuilder;
  _AccordionFolderTile({
    required this.folder,
    required this.count,
    required this.store,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.childBuilder,
    Key? key,
  }) : super(key: key);

  @override
  State<_AccordionFolderTile> createState() => _AccordionFolderTileState();
}

class _AccordionFolderTileState extends State<_AccordionFolderTile> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.folder.children.isNotEmpty;
    return Column(
      children: [
        ListTile(
          key: ValueKey(widget.folder.id),
          leading: const Icon(Icons.folder_open_outlined),
          title: Text(widget.folder.name),
          subtitle: Text('${widget.count} 件'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StoreProvider(
                  store: widget.store,
                  child: FolderScreen(folder: widget.folder),
                ),
              ),
            );
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                onPressed: widget.onAdd,
                tooltip: 'サブフォルダ追加',
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'フォルダ編集',
                onSelected: (value) {
                  if (value == 'edit') {
                    widget.onEdit();
                  } else if (value == 'delete') {
                    widget.onDelete();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('編集')),
                  const PopupMenuItem(value: 'delete', child: Text('削除')),
                ],
              ),
              if (hasChildren)
                IconButton(
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  tooltip: _expanded ? '折りたたむ' : '展開',
                ),
            ],
          ),
        ),
        if (_expanded && hasChildren)
          widget.childBuilder(),
      ],
    );
  }
}

// ローカルDBのグローバルインスタンス
Database? _database;

Future<Database> getDatabase() async {
  if (_database != null) return _database!;
  
  final documentsDirectory = await getApplicationDocumentsDirectory();
  final path = join(documentsDirectory.path, 'bookmarks.db');
  
  _database = await openDatabase(
    path,
    version: 2,
    onCreate: (db, version) async {
      // bookmarksテーブル
      await db.execute('''
        CREATE TABLE bookmarks (
          id TEXT PRIMARY KEY,
          url TEXT NOT NULL,
          title TEXT NOT NULL,
          excerpt TEXT,
          created_at TEXT NOT NULL,
          read_at TEXT,
          is_pinned INTEGER DEFAULT 0,
          is_archived INTEGER DEFAULT 0,
          folder_id TEXT,
          open_count INTEGER DEFAULT 0,
          last_opened_at TEXT,
          thumbnail_url TEXT,
          sort_order INTEGER DEFAULT 0
        )
      ''');
      
      // tagsテーブル
      await db.execute('''
        CREATE TABLE tags (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE
        )
      ''');
      
      // bookmark_tagsテーブル（多対多の中間テーブル）
      await db.execute('''
        CREATE TABLE bookmark_tags (
          bookmark_id TEXT NOT NULL,
          tag_id TEXT NOT NULL,
          PRIMARY KEY (bookmark_id, tag_id)
        )
      ''');
      
      // foldersテーブル
      await db.execute('''
        CREATE TABLE folders (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          parent_id TEXT,
          sort_order INTEGER DEFAULT 0
        )
      ''');
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        // バージョン1から2へのアップグレード：sort_orderカラムを追加
        await db.execute('ALTER TABLE bookmarks ADD COLUMN sort_order INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE folders ADD COLUMN sort_order INTEGER DEFAULT 0');
      }
    },
  );
  
  return _database!;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Google Mobile Ads SDK の初期化
  MobileAds.instance.initialize();
  
  // Share Extension サービスの初期化
  ShareExtensionService.initialize();
  
  // ローカルDBの初期化
  await getDatabase();
  
  // リワード広告を事前に読み込み
  RewardedAdManager.loadAd();
  
  // App Tracking Transparency (ATT) のリクエスト (iOS のみ)
  if (Platform.isIOS) {
    await _requestATT();
  }
  
  runApp(const BookmarkApp());
}

// ATTリクエスト処理
Future<void> _requestATT() async {
  try {
    // トラッキング許可状況を確認
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    
    // まだ許可を求めていない場合のみ表示
    if (status == TrackingStatus.notDetermined) {
      // 少し待ってからダイアログを表示（アプリが完全に起動してから）
      await Future.delayed(const Duration(milliseconds: 500));
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  } catch (e) {
    debugPrint('ATTリクエストエラー: $e');
  }
}

// レビュー催促処理（ブックマーク10個登録時）
Future<void> _checkAndRequestReviewOnBookmarkMilestone() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    const String reviewRequestedKey = 'review_requested';
    
    // すでにレビュー催促を表示したことがあるか確認
    final bool reviewRequested = prefs.getBool(reviewRequestedKey) ?? false;
    if (reviewRequested) {
      return; // すでに表示済みなら何もしない
    }
    
    // ブックマークの総数を取得
    final db = await getDatabase();
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM bookmarks');
    final int bookmarkCount = Sqflite.firstIntValue(result) ?? 0;
    
    debugPrint('� 現在のブックマーク数: $bookmarkCount');
    
    // 10個に達したらレビュー催促
    if (bookmarkCount >= 10) {
      final InAppReview inAppReview = InAppReview.instance;
      
      // レビュー機能が利用可能か確認
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
        await prefs.setBool(reviewRequestedKey, true); // 催促済みフラグを立てる
        debugPrint('✅ レビュー催促を表示しました（ブックマーク10個達成）');
      }
    }
  } catch (e) {
    debugPrint('レビュー催促エラー: $e');
  }
}

// ===== App Root =====
class BookmarkApp extends StatelessWidget {
  const BookmarkApp({super.key});
  @override
  Widget build(BuildContext context) {
    return StoreProvider(
      store: AppStore(),
      child: MaterialApp(
        title: 'Bookmarks',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF90A4AE), // ブルーグレー
            brightness: Brightness.light,
            primary: const Color(0xFF607D8B), // アクセント
            secondary: const Color(0xFFB0BEC5), // サブ
            surface: const Color(0xFFF5F7FA), // カード・背景
            background: const Color(0xFFF5F7FA),
            onPrimary: Colors.white,
            onSecondary: const Color(0xFF263238),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF90A4AE), // ヘッダー
            foregroundColor: Color(0xFF263238),
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: Color(0xFFF5F7FA),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF607D8B),
            foregroundColor: Colors.white,
          ),
          chipTheme: ChipThemeData(
            backgroundColor: const Color(0xFFE3F2FD),
            labelStyle: const TextStyle(color: Color(0xFF263238)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFE3F2FD),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF90A4AE), width: 2),
            ),
          ),
          textTheme: const TextTheme(
            titleLarge: TextStyle(color: Color(0xFF263238)),
            bodyMedium: TextStyle(color: Color(0xFF263238)),
          ),
        ),
        home: const RootScreen(),
      ),
    );
  }
}

const String appVersion = 'v1.0';

// ===== Store (ChangeNotifier) =====
class AppStore extends ChangeNotifier {
  // ドラッグ＆ドロップでサブフォルダの順序を更新
  Future<void> updateFolderOrder(String parentId, List<FolderModel> subfolders) async {
    try {
      for (int i = 0; i < subfolders.length; i++) {
        subfolders[i].sortOrder = i;
        await _folderRepo.update(subfolders[i].id, subfolders[i].name, parentId: subfolders[i].parentId, sortOrder: i);
      }
      await fetchFolders();
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating folder order: $e');
    }
  }

  // ドラッグ＆ドロップでブックマークの順序を更新
  Future<void> updateBookmarkOrder(String folderId, List<BookmarkModel> bookmarks) async {
    try {
      for (int i = 0; i < bookmarks.length; i++) {
        bookmarks[i].sortOrder = i;
        await _bookmarkRepo.update(bookmarks[i]);
      }
      await fetchBookmarks();
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating bookmark order: $e');
    }
  }
  // Repositories
  late final TagRepository _tagRepo;
  late final FolderRepository _folderRepo;
  late final BookmarkRepository _bookmarkRepo;

  // Data
  List<TagModel> tags = [];
  List<FolderModel> folders = [];
  List<BookmarkModel> bookmarks = [];

  String searchText = '';
  QuickFilter quick = QuickFilter.none;
  bool isLoading = false;
  AppStore() {
    _tagRepo = TagRepository(getDatabase);
    _folderRepo = FolderRepository(getDatabase);
    _bookmarkRepo = BookmarkRepository(getDatabase);
  }

  void updateSearchText(String text) {
    searchText = text;
    notifyListeners();
  }

  void updateQuickFilter(QuickFilter filter) {
    quick = filter;
    notifyListeners();
  }

  // ===== データ取得 =====
  Future<void> fetchTags() async {
    try {
      tags = await _tagRepo.fetchAll();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching tags: $e');
    }
  }

  Future<void> fetchFolders() async {
    try {
      folders = await _folderRepo.fetchAll();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching folders: $e');
    }
  }

  Future<void> fetchBookmarks() async {
    try {
      isLoading = true;
      notifyListeners();

      bookmarks = await _bookmarkRepo.fetchAll(tags);
    } catch (e) {
      debugPrint('Error fetching bookmarks: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    await fetchTags();
    await fetchFolders();
    await fetchBookmarks();
  }

  // ===== CRUD - Bookmarks =====
  Future<void> addBookmark(BookmarkModel bm) async {
    try {
      await _bookmarkRepo.create(bm);
      await fetchBookmarks();
    } catch (e) {
      debugPrint('Error adding bookmark: $e');
    }
  }

  Future<void> updateBookmark(BookmarkModel bm) async {
    try {
      await _bookmarkRepo.update(bm);
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating bookmark: $e');
    }
  }

  Future<void> toggleRead(BookmarkModel bm) async {
    await _bookmarkRepo.toggleRead(bm);
    notifyListeners();
  }

  Future<void> togglePin(BookmarkModel bm) async {
    await _bookmarkRepo.togglePin(bm);
    notifyListeners();
  }

  Future<void> removeBookmark(BookmarkModel bm) async {
    try {
      // サムネ画像ファイル削除
      if (bm.thumbnailUrl != null && bm.thumbnailUrl!.isNotEmpty) {
        try {
          final file = File(bm.thumbnailUrl!);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('Error deleting thumbnail file: $e');
        }
      }
      await _bookmarkRepo.delete(bm.id);
      await fetchBookmarks();
    } catch (e) {
      debugPrint('Error removing bookmark: $e');
    }
  }

  Future<void> opened(BookmarkModel bm) async {
    await _bookmarkRepo.incrementOpenCount(bm);
    notifyListeners();
  }
  
  // ===== CRUD - Tags =====
  Future<void> addTag(TagModel tag) async {
    try {
      await _tagRepo.create(tag.name);
      await fetchTags();
    } catch (e) {
      debugPrint('Error adding tag: $e');
    }
  }

  Future<void> updateTag(TagModel tag) async {
    try {
      await _tagRepo.update(tag.id, tag.name);
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating tag: $e');
    }
  }

  Future<void> removeTag(TagModel tag) async {
    try {
      await _tagRepo.delete(tag.id);
      await fetchTags();
      await fetchBookmarks();
    } catch (e) {
      debugPrint('Error removing tag: $e');
    }
  }
  
  // ===== CRUD - Folders =====
  Future<void> addFolder(String name, {String? parentId}) async {
    await _folderRepo.create(name, parentId: parentId);
    await fetchFolders(); // 追加直後に再取得・反映
  }

  Future<void> updateFolder(String id, String name, {String? parentId, int? sortOrder}) async {
    try {
      await _folderRepo.update(id, name, parentId: parentId);
      await fetchFolders();
    } catch (e) {
      debugPrint('Error updating folder: $e');
    }
  }

  Future<void> deleteFolder(String id) async {
    try {
      await _folderRepo.delete(id);
      await fetchFolders();
    } catch (e) {
      debugPrint('Error deleting folder: $e');
    }
  }

  /// フォルダをフラットなリストで取得（ドロップダウン用）
  Future<List<FolderModel>> getFlatFolders() async {
    try {
      return await _folderRepo.fetchAllFlat();
    } catch (e) {
      debugPrint('Error fetching flat folders: $e');
      return [];
    }
  }

  // ===== Filters =====
  List<BookmarkModel> get filtered {
    Iterable<BookmarkModel> it = bookmarks;
    if (searchText.trim().isNotEmpty) {
      final q = searchText.toLowerCase();
      it = it.where((b) => b.title.toLowerCase().contains(q) || b.url.toLowerCase().contains(q) || b.excerpt.toLowerCase().contains(q) || b.tags.any((t) => t.name.toLowerCase().contains(q)));
    }
    switch (quick) {
    case QuickFilter.none: break;
    }
    final list = it.toList();
    list.sort((a, b) {
      int p = (b.isPinned ? 1 : 0) - (a.isPinned ? 1 : 0);
      if (p != 0) return p;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  List<BookmarkModel> get frequent {
    final list = bookmarks.toList();
    list.sort((a, b) {
      final lb = b.lastOpenedAt?.millisecondsSinceEpoch ?? 0;
      final la = a.lastOpenedAt?.millisecondsSinceEpoch ?? 0;
      return lb.compareTo(la); // 新しいものが先頭
    });
    return list.take(10).toList();
  }

  List<BookmarkModel> byFolder(String folderId) => bookmarks.where((b) => b.folderId == folderId).toList();

  /// フォルダとそのすべてのサブフォルダ内のブックマーク数を再帰的にカウント
  int countBookmarksRecursive(String folderId) {
    int count = byFolder(folderId).length;
    
    // サブフォルダを探す
    FolderModel? findFolder(List<FolderModel> folders) {
      for (final f in folders) {
        if (f.id == folderId) return f;
        final sub = findFolder(f.children);
        if (sub != null) return sub;
      }
      return null;
    }
    
    final folder = findFolder(folders);
    if (folder != null) {
      for (final child in folder.children) {
        count += countBookmarksRecursive(child.id);
      }
    }
    
    return count;
  }

  // ===== バックアップ機能 =====
  
  /// データをJSON形式でエクスポート
  Future<Map<String, dynamic>> exportData() async {
    try {
      await fetchTags();
      await fetchFolders();
      await fetchBookmarks();

      return {
        'version': '1.0.0',
        'exported_at': DateTime.now().toIso8601String(),
        'tags': tags.map((tag) => {
          'id': tag.id,
          'name': tag.name,
        }).toList(),
        'folders': _exportFoldersRecursive(folders),
        'bookmarks': bookmarks.map((bm) => {
          'id': bm.id,
          'title': bm.title,
          'url': bm.url,
          'excerpt': bm.excerpt,
          'folder_id': bm.folderId,
          'thumbnail_url': bm.thumbnailUrl,
          'is_pinned': bm.isPinned,
          'is_read': bm.readAt != null,
          'is_archived': bm.isArchived,
          'open_count': bm.openCount,
          'created_at': bm.createdAt.toIso8601String(),
          'read_at': bm.readAt?.toIso8601String(),
          'last_opened_at': bm.lastOpenedAt?.toIso8601String(),
          'sort_order': bm.sortOrder,
          'tags': bm.tags.map((t) => t.id).toList(),
        }).toList(),
      };
    } catch (e) {
      debugPrint('Error exporting data: $e');
      rethrow;
    }
  }

  List<Map<String, dynamic>> _exportFoldersRecursive(List<FolderModel> folders) {
    return folders.map((folder) => {
      'id': folder.id,
      'name': folder.name,
      'parent_id': folder.parentId,
      'sort_order': folder.sortOrder,
      'children': _exportFoldersRecursive(folder.children),
    }).toList();
  }

  /// JSONデータからインポート
  Future<void> importData(Map<String, dynamic> data, {bool clearExisting = false}) async {
    try {
      if (clearExisting) {
        // 既存データをクリア
        for (final bm in bookmarks) {
          await _bookmarkRepo.delete(bm.id);
        }
        for (final folder in folders) {
          await _folderRepo.delete(folder.id);
        }
        for (final tag in tags) {
          await _tagRepo.delete(tag.id);
        }
      }

      // タグをインポート（IDを保持）
      final tagsData = data['tags'] as List<dynamic>;
      final db = await getDatabase();
      for (final tagData in tagsData) {
        await db.insert(
          'tags',
          {
            'id': tagData['id'] as String,
            'name': tagData['name'] as String,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // フォルダを階層的にインポート（IDを保持）
      final foldersData = data['folders'] as List<dynamic>;
      await _importFoldersRecursive(foldersData, null, db);

      // ブックマークをインポート
      await fetchTags(); // タグIDマッピング用
      final bookmarksData = data['bookmarks'] as List<dynamic>;
      for (final bmData in bookmarksData) {
        final tagIds = (bmData['tags'] as List<dynamic>).cast<String>();
        final bmTags = tags.where((t) => tagIds.contains(t.id)).toList();
        
        final bm = BookmarkModel(
          id: bmData['id'] as String,
          title: bmData['title'] as String,
          url: bmData['url'] as String,
          excerpt: bmData['excerpt'] as String? ?? '',
          folderId: bmData['folder_id'] as String?,
          tags: bmTags,
          thumbnailUrl: bmData['thumbnail_url'] as String?,
          isPinned: bmData['is_pinned'] as bool? ?? false,
          isArchived: bmData['is_archived'] as bool? ?? false,
          openCount: bmData['open_count'] as int? ?? 0,
          createdAt: DateTime.parse(bmData['created_at'] as String),
          readAt: bmData['read_at'] != null ? DateTime.parse(bmData['read_at'] as String) : null,
          lastOpenedAt: bmData['last_opened_at'] != null ? DateTime.parse(bmData['last_opened_at'] as String) : null,
          sortOrder: bmData['sort_order'] as int? ?? 0,
        );
        
        await _bookmarkRepo.create(bm);
      }

      // データを再取得
      await fetchTags();
      await fetchFolders();
      await fetchBookmarks();
      notifyListeners();
    } catch (e) {
      debugPrint('Error importing data: $e');
      rethrow;
    }
  }

  Future<void> _importFoldersRecursive(List<dynamic> foldersData, String? parentId, Database db) async {
    for (final folderData in foldersData) {
      await db.insert(
        'folders',
        {
          'id': folderData['id'] as String,
          'name': folderData['name'] as String,
          'parent_id': parentId,
          'sort_order': folderData['sort_order'] as int? ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      // 子フォルダを再帰的にインポート
      final children = folderData['children'] as List<dynamic>?;
      if (children != null && children.isNotEmpty) {
        await _importFoldersRecursive(children, folderData['id'] as String, db);
      }
    }
  }
}

enum QuickFilter { none }

// ===== Inherited Store =====
class StoreProvider extends InheritedNotifier<AppStore> {
  const StoreProvider({super.key, required AppStore store, required Widget child}) : super(notifier: store, child: child);
  
  static AppStore? maybeOf(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<StoreProvider>();
    return provider?.notifier;
  }
  
  static AppStore of(BuildContext context) {
    final store = maybeOf(context);
    if (store == null) {
      throw FlutterError('StoreProvider.of(context) called with a context that does not contain a StoreProvider.');
    }
    return store;
  }
  
  @override bool updateShouldNotify(covariant InheritedNotifier<AppStore> oldWidget) => true;
}

// ===== Root with Drawer + Bottom Nav =====
// ===== Root with Drawer + Bottom Nav =====
class RootScreen extends StatefulWidget { const RootScreen({super.key}); @override State<RootScreen> createState() => _RootScreenState(); }
class _RootScreenState extends State<RootScreen> {
  // Use the shared AppStore from StoreProvider instead of creating a new one
  late AppStore store;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  int idx = 0;
  bool _initialized = false;
  // All tab selection state
  bool _allSelectionMode = false;
  int _allSelectedCount = 0;
  final GlobalKey<_AllBookmarksScreenState> _allKey = GlobalKey<_AllBookmarksScreenState>();
  
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Obtain the shared store from the provider once the context is ready
    store = StoreProvider.of(context);
    if (!_initialized) {
      _initialize();
    }
  }
  
  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await store.initialize();
    setState(() => _initialized = true);
  }
  
  void _initDeepLinks() async {
    _appLinks = AppLinks();
    
    // アプリが起動していない状態からのリンク処理
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _handleDeepLink(initialUri);
    }
    
    // アプリが既に起動している状態でのリンク処理
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }
  
  void _handleDeepLink(Uri uri) {
    // bookmark://open の場合はホーム画面を表示
    if (uri.scheme == 'bookmark' && uri.host == 'open') {
      setState(() => idx = 0);
    }
  }

  void _goTab(int i) => setState(() => idx = i);

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return StoreProvider(
      store: store,
      child: Scaffold(
        key: scaffoldKey,
        drawer: AppDrawer(onSelect: (route) {
          switch (route) {
            case 'home': _goTab(0); break;
            case 'all': _goTab(1); break;
            case 'tags': _goTab(2); break;
            case 'smart': _goTab(3); break;
          }
        }),
        body: IndexedStack(
          index: idx,
          children: [
            HomeScreen(onOpenDrawer: () => scaffoldKey.currentState?.openDrawer()),
            AllBookmarksScreen(
              key: _allKey,
              onSelectionChanged: (mode, count) {
                setState(() {
                  _allSelectionMode = mode;
                  _allSelectedCount = count;
                });
              },
            ),
            const TagsScreen(),
            SmartFolderScreen(scaffoldKey: scaffoldKey),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AdBanner(),
            NavigationBar(
              selectedIndex: idx,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'ホーム'),
                NavigationDestination(icon: Icon(Icons.bookmark_outline), selectedIcon: Icon(Icons.bookmark), label: '全ブックマーク'),
                NavigationDestination(icon: Icon(Icons.tag_outlined), selectedIcon: Icon(Icons.tag), label: 'タグ一覧'),
                NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'AIツール'),
              ],
              onDestinationSelected: _goTab,
            ),
          ],
        ),
        floatingActionButton: (idx == 3 || idx == 2)
            ? null // タグ一覧ページ・AIツールページは追加ボタン非表示
            : Builder(
                builder: (context) {
                  // On "All" tab, switch FAB based on selection mode
                  if (idx == 1) {
                    if (_allSelectionMode) {
                      return FloatingActionButton.extended(
                        onPressed: _allSelectedCount == 0
                            ? null
                            : () => _allKey.currentState?.deleteSelectedViaParent(context),
                        icon: const Icon(Icons.delete),
                        label: const Text('削除'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      );
                    }
                  }
                  // Default: Add button
                  return FloatingActionButton.extended(
                    onPressed: () {
                      final store = StoreProvider.of(context);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (ctx) => StoreProvider(
                          store: store,
                          child: const AddBookmarkSheet(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('追加'),
                  );
                },
              ),
      ),
    );
  }
}

// ===== Drawer (Flat) =====
class AppDrawer extends StatelessWidget {
  final void Function(String route) onSelect;
  const AppDrawer({super.key, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: const Color(0xFFF5F7FA),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                color: const Color(0xFF90A4AE),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFF607D8B),
                          child: const Icon(Icons.bookmark, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('AI Bookmark Manager', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 0),

              // --- ナビ（固定）
              _GroupTitle('ナビゲーション'),

              ListTile(leading: const Icon(Icons.home), title: const Text('ホーム'), onTap: () { Navigator.pop(context); onSelect('home'); }),
              ListTile(leading: const Icon(Icons.bookmark), title: const Text('ブックマーク一覧'), onTap: () { Navigator.pop(context); onSelect('all'); }),
              ListTile(leading: const Icon(Icons.tag), title: const Text('タグ一覧'), onTap: () { Navigator.pop(context); onSelect('tags'); }),
              ListTile(leading: const Icon(Icons.auto_awesome), title: const Text('AIツール'), onTap: () { Navigator.pop(context); onSelect('smart'); }),

              // --- チュートリアル（見出し→ボタン群）
              _GroupTitle('チュートリアル'),
              _NavTile(context, icon: Icons.menu_book_outlined, label: '使い方', page: const TutorialScreen()),
              _NavTile(context, icon: Icons.settings_outlined, label: '各種設定', page: const SettingsScreen()),

              // --- バックアップ（見出し→ボタン群）
              _GroupTitle('バックアップ'),
              ListTile(
                leading: const Icon(Icons.upload_outlined),
                title: const Text('データエクスポート'),
                onTap: () async {
                  Navigator.pop(context);
                  await _exportBackup(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('データインポート'),
                onTap: () async {
                  Navigator.pop(context);
                  await _importBackup(context);
                },
              ),

              // --- AI（見出し→ボタン）

              // --- 問い合わせ（見出し→ボタン）
              _GroupTitle('問い合わせ'),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('不具合報告/改善依頼'),
                onTap: () async {
                  Navigator.pop(context);
                  final url = Uri.parse('https://forms.gle/Z1mfnV3CXnC45aSS9');
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),

              // --- App課金（見出し→ボタン）
              _GroupTitle('App課金'),
              ListTile(
                leading: const Icon(Icons.hide_image_outlined),
                title: const Text('広告削除'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('近日中に実装予定です。お待ちください')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('購入記録を復元'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('近日中に実装予定です。お待ちください')),
                  );
                },
              ),

              // --- その他（見出し→ボタン）
              _GroupTitle('その他'),
              _NavTile(context, icon: Icons.privacy_tip_outlined, label: 'プライバシーポリシー', page: const PrivacyScreen()),
              const ListTile(
                leading: Icon(Icons.verified_outlined),
                title: Text('バージョン'),
                subtitle: Text(appVersion),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  final String title; const _GroupTitle(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
    );
  }
}

Widget _NavTile(BuildContext context, {required IconData icon, required String label, required Widget page}) {
  return ListTile(
    leading: Icon(icon),
    title: Text(label),
    onTap: () {
      Navigator.pop(context);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    },
  );
}

// ===== バックアップ機能 =====

/// データをエクスポート
Future<void> _exportBackup(BuildContext context) async {
  final store = StoreProvider.of(context);
  
  try {
    // データをエクスポート
    final data = await store.exportData();
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    
    // 一時ファイルに保存
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final filePath = '${directory.path}/bookmark_backup_$timestamp.json';
    final file = File(filePath);
    await file.writeAsString(jsonString);
    
    // 共有
    final result = await Share.shareXFiles(
      [XFile(filePath)],
      subject: 'ブックマークバックアップ',
      text: 'ブックマークデータをエクスポートしました',
    );
    
    if (context.mounted) {
      if (result.status == ShareResultStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('データをエクスポートしました')),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エクスポートエラー: $e')),
      );
    }
  }
}

/// データをインポート
Future<void> _importBackup(BuildContext context) async {
  final store = StoreProvider.of(context);
  
  try {
    // ファイル選択
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    
    if (result == null || result.files.isEmpty) {
      return; // キャンセル
    }
    
    final filePath = result.files.single.path;
    if (filePath == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ファイルパスが取得できませんでした')),
        );
      }
      return;
    }
    
    // ファイル読み込み
    final file = File(filePath);
    final jsonString = await file.readAsString();
    final data = json.decode(jsonString) as Map<String, dynamic>;
    
    // 確認ダイアログ
    if (context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('データインポート'),
          content: const Text(
            '既存のデータを削除して、バックアップデータをインポートしますか？\n'
            '\n※この操作は取り消せません',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('インポート'),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
    }
    
    // インポート実行
    await store.importData(data, clearExisting: true);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('データをインポートしました')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('インポートエラー: $e')),
      );
    }
  }
}

// ===== Home (Frequent + Folders + List) =====
class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenDrawer;
  const HomeScreen({super.key, required this.onOpenDrawer});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String pinnedSort = 'created_desc';
  String folderSort = 'name_asc';
  List<BookmarkModel>? pinnedOrder;
  List<FolderModel>? folderOrder;
  bool _isProcessingSharedData = false; // 共有データ処理中フラグ

  @override
  void initState() {
    super.initState();
    // Share Extensionからの共有データをチェック
    _checkSharedData();
    
    // 共有データのコールバックを設定
    ShareExtensionService.setOnSharedDataCallback((data) {
      _handleSharedData(data);
    });
  }

  // Share Extensionからの共有データをチェック
  void _checkSharedData() async {
    final data = await ShareExtensionService.getSharedData();
    if (data != null && mounted) {
      _handleSharedData(data);
    }
  }

  // 共有データを処理
  void _handleSharedData(Map<String, String> data) async {
    if (!mounted) return;
    
    // 共有処理開始フラグ
    final isFirstInBatch = !_isProcessingSharedData;
    _isProcessingSharedData = true;
    
    final url = data['url'];
    final title = data['title'];
    
    if (url != null) {
      // 直接保存（シートは表示しない）
      if (!mounted) return;
      final store = StoreProvider.of(this.context);

      // 既存タグへマッピング
      final List<TagModel> selectedTags = [];
      final tagsText = data['tags_text'] ?? '';
      if (tagsText.isNotEmpty) {
        final names = tagsText.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
        for (final name in names) {
          final tag = store.tags.firstWhere(
            (t) => t.name == name,
            orElse: () => TagModel(id: '', name: ''),
          );
          if (tag.id.isNotEmpty && !selectedTags.any((t) => t.id == tag.id)) {
            selectedTags.add(tag);
          }
        }
      }

      // フォルダ名からID解決
      String? folderId;
      final folderName = data['folder_name'];
      if (folderName != null && folderName.isNotEmpty) {
        final folder = store.folders.firstWhere(
          (f) => f.name == folderName,
          orElse: () => FolderModel(id: '', name: '', sortOrder: 0),
        );
        if (folder.id.isNotEmpty) folderId = folder.id;
      }

      final bm = BookmarkModel(
        id: _id(),
        url: url,
        title: (title?.isNotEmpty == true) ? title! : url,
        excerpt: data['excerpt'] ?? '',
        createdAt: DateTime.now(),
        readAt: null,
        isPinned: data['is_pinned'] == 'true',
        isArchived: false,
        tags: selectedTags,
        folderId: folderId,
        thumbnailUrl: data['thumbnail_path'],
      );

      try {
        await store.addBookmark(bm);
        // 最初のブックマーク追加時のみSnackBarを表示
        if (mounted && isFirstInBatch) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            const SnackBar(content: Text('共有からブックマークを追加しました')),
          );
        }
        // ブックマーク登録後、レビュー催促チェック
        await _checkAndRequestReviewOnBookmarkMilestone();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(content: Text('追加に失敗しました: $e')),
          );
        }
      }
      
      // このブックマークの処理が完了したら、共有データをクリア
      ShareExtensionService.clearSharedData();
      
      // 次のブックマークがあるかチェック（100ms後）
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        final nextData = await ShareExtensionService.getSharedData();
        if (nextData != null) {
          // 次のブックマークを処理
          _handleSharedData(nextData);
        } else {
          // すべての処理が完了したらフラグをリセット
          _isProcessingSharedData = false;
        }
      } else {
        _isProcessingSharedData = false;
      }
    } else {
      _isProcessingSharedData = false;
    }
  }

  // Expose a safe way to refresh folder list from external helpers
  void refreshFolders(AppStore store) {
    if (!mounted) return;
    setState(() {
      folderOrder = List.from(store.folders);
      _sortFolders();
    });
  }

  void _sortPinned() {
    if (pinnedOrder == null) return;
    switch (pinnedSort) {
      case 'name_asc':
        pinnedOrder!.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'name_desc':
        pinnedOrder!.sort((a, b) => b.title.compareTo(a.title));
        break;
      case 'created_asc':
        pinnedOrder!.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'created_desc':
        pinnedOrder!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
  }

  void _sortFolders() {
    if (folderOrder == null) return;
    switch (folderSort) {
      case 'name_asc':
        folderOrder!.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'name_desc':
        folderOrder!.sort((a, b) => b.name.compareTo(a.name));
        break;
      case 'created_asc':
        folderOrder!.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        break;
      case 'created_desc':
        folderOrder!.sort((a, b) => b.sortOrder.compareTo(a.sortOrder));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
  final store = StoreProvider.of(context);
  final theme = Theme.of(context);
    final frequent = store.frequent;
    final folders = store.folders;
    final pinned = store.bookmarks.where((b) => b.isPinned).toList();

    // Calculate the same tile size as the "All" grid (2 columns, padding=12, spacing=8, aspect=0.85)
    final screenWidth = MediaQuery.of(context).size.width;
    const horizontalPadding = 12.0 * 2; // left + right in SliverPadding
    const crossAxisSpacing = 8.0;       // spacing between the 2 columns
    const childAspectRatio = 0.85;      // width / height in the grid
    final tileWidth = (screenWidth - horizontalPadding - crossAxisSpacing) / 2;
    final tileHeight = tileWidth / childAspectRatio;

    // 初回のみ順序を初期化
    if (pinnedOrder == null || pinnedOrder!.length != pinned.length) {
      pinnedOrder = List.from(pinned);
    }
    // フォルダが更新されたら反映
    if (folderOrder == null || folderOrder!.length != folders.length || 
        !folderOrder!.every((f) => folders.any((sf) => sf.id == f.id))) {
      folderOrder = List.from(folders);
      _sortFolders();
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.primary,
        statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness,
      ),
      child: Stack(
        children: [
          Container(
            height: MediaQuery.of(context).padding.top,
            color: theme.colorScheme.primary,
          ),
          SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            store.fetchFolders(),
            store.fetchBookmarks(),
            store.fetchTags(),
          ]);
          setState(() {
            folderOrder = List.from(store.folders);
            pinnedOrder = store.bookmarks.where((b) => b.isPinned).toList();
            _sortFolders();
            _sortPinned();
          });
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          SliverAppBar(
            backgroundColor: theme.colorScheme.primary,
            floating: true, snap: true,
            title: const Text('ホーム', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            leading: IconButton(icon: const Icon(Icons.menu), onPressed: widget.onOpenDrawer),
          ),
          const SliverToBoxAdapter(
            child: AdBanner(),
          ),
          if (pinned.isNotEmpty)
            SliverToBoxAdapter(
              child: _Section(
                title: 'ピン留め',
                action: Row(
                  children: [
                    PopupMenuButton<String>(
                      tooltip: '並び替え',
                      icon: const Icon(Icons.sort),
                      onSelected: (v) {
                        setState(() {
                          pinnedSort = v;
                          _sortPinned();
                        });
                      },
                      itemBuilder: (c) => [
                        const PopupMenuItem(value: 'name_asc', child: Text('名前昇順')),
                        const PopupMenuItem(value: 'name_desc', child: Text('名前降順')),
                        const PopupMenuItem(value: 'created_asc', child: Text('登録日時昇順')),
                        const PopupMenuItem(value: 'created_desc', child: Text('登録日時降順')),
                      ],
                    ),
                  ],
                ),
                child: SizedBox(
                  height: tileHeight,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: pinnedOrder!.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = pinnedOrder!.removeAt(oldIndex);
                        pinnedOrder!.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (c, i) => Container(
                      key: ValueKey(pinnedOrder![i].id),
                      width: tileWidth,
                      margin: const EdgeInsets.only(right: 12),
                      child: BookmarkGridCard(bm: pinnedOrder![i], store: store),
                    ),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: _Section(
              title: '最近よく使ったブックマーク',
              child: frequent.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Text('まだ使用履歴がありません'))
                  : SizedBox(
                      height: tileHeight,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        scrollDirection: Axis.horizontal,
                        itemCount: frequent.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (c, i) => SizedBox(
                          width: tileWidth,
                          child: BookmarkGridCard(bm: frequent[i], store: store),
                        ),
                      ),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: _Section(
              title: 'フォルダ一覧',
              action: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _showAddFolderDialog(context, null),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('新規フォルダ'),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '並び替え',
                    icon: const Icon(Icons.sort),
                    onSelected: (v) {
                      setState(() {
                        folderSort = v;
                        _sortFolders();
                      });
                    },
                    itemBuilder: (c) => [
                      const PopupMenuItem(value: 'name_asc', child: Text('名前昇順')),
                      const PopupMenuItem(value: 'name_desc', child: Text('名前降順')),
                      const PopupMenuItem(value: 'created_asc', child: Text('登録日時昇順')),
                      const PopupMenuItem(value: 'created_desc', child: Text('登録日時降順')),
                    ],
                  ),
                ],
              ),
              child: _FolderTreeView(
                folders: folderOrder!,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = folderOrder!.removeAt(oldIndex);
                    folderOrder!.insert(newIndex, item);
                  });
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ), // CustomScrollView
    ), // RefreshIndicator
          ), // SafeArea
        ],
      ),
    ); // AnnotatedRegion
}
}

// ===== All Bookmarks Tab =====
class AllBookmarksScreen extends StatefulWidget {
  final void Function(bool selectionMode, int selectedCount)? onSelectionChanged;
  const AllBookmarksScreen({super.key, this.onSelectionChanged});
  @override
  State<AllBookmarksScreen> createState() => _AllBookmarksScreenState();
}

class _AllBookmarksScreenState extends State<AllBookmarksScreen> {
  String? _tagFilter; // null: 全て, 'none': タグなし, その他: タグID

  void _showFilterDialog() async {
  final store = StoreProvider.of(this.context);
  // 実際にブックマークに使われているタグのみ抽出
  final usedTagIds = store.bookmarks.expand((b) => b.tags.map((t) => t.id)).toSet();
  final tags = store.tags.where((t) => usedTagIds.contains(t.id)).toList();
    final selected = await showDialog<String?> (
      context: this.context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('タグでフィルター'),
          children: [
            SimpleDialogOption(
              child: const Text('全て'),
              onPressed: () => Navigator.pop(ctx, null),
            ),
            SimpleDialogOption(
              child: const Text('タグなし'),
              onPressed: () => Navigator.pop(ctx, 'none'),
            ),
            SizedBox(
              height: 48.0 * 10, // 常に10個分の高さで固定
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...tags.map((t) => SimpleDialogOption(
                          child: Text(t.name),
                          onPressed: () => Navigator.pop(ctx, t.id),
                        )),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
    setState(() => _tagFilter = selected);
  }
  final ValueNotifier<String> allSort = ValueNotifier('created_desc');
  final Set<String> selectedIds = {};
  bool selectionMode = false;

  void _toggleSelect(String id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
      selectionMode = selectedIds.isNotEmpty;
      widget.onSelectionChanged?.call(selectionMode, selectedIds.length);
    });
  }

  void _clearSelection() {
    setState(() {
      selectedIds.clear();
      selectionMode = false;
      widget.onSelectionChanged?.call(false, 0);
    });
  }

  Future<void> _deleteSelected(AppStore store) async {
    final ids = selectedIds.toList();
    if (ids.isEmpty) return;
    final count = ids.length;
    final bmTitles = ids.map((id) => store.bookmarks.firstWhere((b) => b.id == id).title).toList();
    final BuildContext ctx = this.context;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('ブックマークを削除しますか？'),
        content: Text(count == 1
            ? '「${bmTitles.first}」を削除します。'
            : '選択した${count}件のブックマークを削除します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok == true) {
      for (final id in ids) {
        final matches = store.bookmarks.where((b) => b.id == id).toList();
        if (matches.isNotEmpty) {
          await store.removeBookmark(matches.first);
        }
      }
      _clearSelection();
      await store.fetchBookmarks();
      setState(() {});
    }
  }

  // Called from parent FAB
  Future<void> deleteSelectedViaParent(BuildContext ctx) async {
  await _deleteSelected(StoreProvider.of(ctx));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreProvider.of(context);
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.primary,
        statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness,
      ),
      child: Stack(
        children: [
          Container(
            height: MediaQuery.of(context).padding.top,
            color: theme.colorScheme.primary,
          ),
          SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await store.fetchBookmarks();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: theme.colorScheme.primary,
              floating: true,
              snap: true,
              title: selectionMode
                  ? Text('${selectedIds.length}件選択中', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  : const Text('ブックマーク一覧', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              leading: selectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _clearSelection,
                      tooltip: '選択解除',
                    )
                  : null,
              actions: [
              ],
            ),
            const SliverToBoxAdapter(
              child: AdBanner(),
            ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const _SearchBar(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: Icon(selectionMode ? Icons.delete : Icons.check_box),
                        color: selectionMode ? Colors.red : null,
                        onPressed: selectionMode
          ? (selectedIds.isEmpty
            ? null
            : () => _deleteSelected(StoreProvider.of(context)))
                            : () {
                                setState(() {
                                  selectionMode = true;
                                });
                              },
                        tooltip: selectionMode
                            ? '選択したブックマークを削除'
                            : '複数選択モード',
                      ),
                      IconButton(
                        icon: const Icon(Icons.filter_list),
                        onPressed: _showFilterDialog,
                        tooltip: 'フィルター',
                      ),
                      PopupMenuButton<String>(
                        tooltip: '並び替え',
                        icon: const Icon(Icons.sort),
                        onSelected: (v) => allSort.value = v,
                        itemBuilder: (c) => [
                          const PopupMenuItem(value: 'name_asc', child: Text('名前昇順')),
                          const PopupMenuItem(value: 'name_desc', child: Text('名前降順')),
                          const PopupMenuItem(value: 'created_asc', child: Text('登録日時昇順')),
                          const PopupMenuItem(value: 'created_desc', child: Text('登録日時降順')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: allSort,
              builder: (context, sort, _) {
                List<BookmarkModel> filtered = List.from(store.filtered);
                if (_tagFilter == 'none') {
                  filtered = filtered.where((b) => b.tags.isEmpty).toList();
                } else if (_tagFilter != null) {
                  filtered = filtered.where((b) => b.tags.any((t) => t.id == _tagFilter)).toList();
                }
                List<BookmarkModel> sorted = List.from(filtered);
                switch (sort) {
                  case 'name_asc':
                    sorted.sort((a, b) => a.title.compareTo(b.title));
                    break;
                  case 'name_desc':
                    sorted.sort((a, b) => b.title.compareTo(a.title));
                    break;
                  case 'created_asc':
                    sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                    break;
                  case 'created_desc':
                    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                    break;
                }
                if (sorted.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: Text('ブックマークはありません')),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: sorted.length,
                    itemBuilder: (c, i) {
                      final bm = sorted[i];
                      final selected = selectedIds.contains(bm.id);
                      return Stack(
                        children: [
                          BookmarkGridCard(bm: bm, store: store),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: selectionMode
                                ? Checkbox(
                                    value: selected,
                                    onChanged: (_) => _toggleSelect(bm.id),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          if (selectionMode)
                            Positioned.fill(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _toggleSelect(bm.id),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
      ),
          ),
        ],
      ),
    );
  }
}

// フォルダ構成分析結果のモデル
class FolderStructureAnalysis {
  final List<SuggestedFolder> suggestedFolders;
  final List<String> foldersToRemove;
  final String overallReasoning;

  FolderStructureAnalysis({
    required this.suggestedFolders,
    required this.foldersToRemove,
    required this.overallReasoning,
  });
}

class SuggestedFolder {
  final String name;
  final String description;
  final String reasoning;
  final List<String> mergeFrom;
  final String? parent;  // 親フォルダ名（階層構造）

  SuggestedFolder({
    required this.name,
    required this.description,
    required this.reasoning,
    required this.mergeFrom,
    this.parent,
  });
}

// ===== Smart & Tags =====
class SmartFolderScreen extends StatefulWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  const SmartFolderScreen({super.key, required this.scaffoldKey});
  @override
  State<SmartFolderScreen> createState() => _SmartFolderScreenState();
}

class _SmartFolderScreenState extends State<SmartFolderScreen> {
  bool _isAnalyzing = false;
  bool _isBulkAssigning = false;
  bool _isAnalyzingFolders = false;
  bool _isBulkAssigningFolders = false;
  // 最大階層数の選択機能は廃止

  // 共通のローディング状態
  bool get _isAnyProcessing => _isAnalyzing || _isBulkAssigning || _isAnalyzingFolders || _isBulkAssigningFolders;
  
  String get _currentProcessingMessage {
    if (_isAnalyzing) return 'タグ構成を分析中...';
    if (_isBulkAssigning) return 'タグを一括割り当て中...';
    if (_isAnalyzingFolders) return 'フォルダ構成を分析中...';
    if (_isBulkAssigningFolders) return 'フォルダを一括割り当て中...';
    return '';
  }

  Future<void> _analyzeTagStructure(BuildContext context) async {
    // リワード広告チェック（デバッグ用フラグで制御）
    if (requireRewardedAdForAI) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('広告視聴'),
          content: const Text('AI機能を使用するには、広告を視聴する必要があります。広告を視聴しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('視聴する'),
            ),
          ],
        ),
      );

      if (shouldProceed != true) return;

      // 広告を表示して報酬獲得を待つ
      final adCompleted = await RewardedAdManager.showAd();

      if (!adCompleted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('広告を最後まで視聴する必要があります'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }

    final store = StoreProvider.of(context);
    
    setState(() => _isAnalyzing = true);

    try {
      // ブックマークデータを準備
      final bookmarksData = store.bookmarks.map((bm) => {
        'title': bm.title,
        'url': bm.url,
        'excerpt': bm.excerpt,
        'current_tags': bm.tags.map((t) => t.name).toList(),
      }).toList();

      // 現在のタグリストを準備
      final currentTags = store.tags.map((t) => t.name).toList();

      // バックエンドAPIを呼び出し
      final analysis = await TagAnalysisService.analyzeTagStructure(
        bookmarks: bookmarksData,
        currentTags: currentTags,
      );

      if (!mounted) return;

      // 結果を表示
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,  // 背景タップで閉じない
        enableDrag: false,  // 下にスライドで閉じない
        builder: (ctx) => StoreProvider(
          store: store,
          child: TagAnalysisResultSheet(analysis: analysis),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラー: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  Future<void> _bulkAssignTags(BuildContext context) async {
    // リワード広告チェック（デバッグ用フラグで制御）
    if (requireRewardedAdForAI) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('広告視聴'),
          content: const Text('AI機能を使用するには、広告を視聴する必要があります。広告を視聴しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('視聴する'),
            ),
          ],
        ),
      );

      if (shouldProceed != true) return;

      // 広告を表示して報酬獲得を待つ
      final adCompleted = await RewardedAdManager.showAd();

      if (!adCompleted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('広告を最後まで視聴する必要があります'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }

    final store = StoreProvider.of(context);
    
    setState(() => _isBulkAssigning = true);

    try {
      // ブックマークとタグのデータを準備
      final bookmarksData = store.bookmarks.map((bm) => {
        'id': bm.id,
        'title': bm.title,
        'url': bm.url,
        'excerpt': bm.excerpt,
        'current_tags': bm.tags.map((t) => t.name).toList(),
      }).toList();

      final availableTags = store.tags.map((t) => t.name).toList();

      // APIリクエスト
      final response = await http.post(
        Uri.parse('$apiBaseUrl/bulk-assign-tags'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'bookmarks': bookmarksData,
          'available_tags': availableTags,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('APIエラー: ${response.statusCode}');
      }

      final result = json.decode(response.body);
      final suggestions = result['suggestions'] as List;

      if (!mounted) return;

      // 結果を表示
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => StoreProvider(
          store: store,
          child: BulkTagAssignmentResultSheet(
            suggestions: suggestions,
            totalProcessed: result['total_processed'],
            overallReasoning: result['overall_reasoning'],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラー: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBulkAssigning = false);
      }
    }
  }

  Future<void> _bulkAssignFolders(BuildContext context) async {
    // リワード広告チェック（デバッグ用フラグで制御）
    if (requireRewardedAdForAI) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('広告視聴'),
          content: const Text('AI機能を使用するには、広告を視聴する必要があります。広告を視聴しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('視聴する'),
            ),
          ],
        ),
      );

      if (shouldProceed != true) return;

      // 広告を表示して報酬獲得を待つ
      final adCompleted = await RewardedAdManager.showAd();

      if (!adCompleted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('広告を最後まで視聴する必要があります'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }

    final store = StoreProvider.of(context);
    
    setState(() => _isBulkAssigningFolders = true);

    try {
      // フォルダツリーをフラット化して「全フォルダ一覧」を作る（getPathの親探索にも使用）
      List<FolderModel> _flattenFolders(List<FolderModel> roots) {
        final List<FolderModel> flat = [];
        void visit(FolderModel f) {
          flat.add(f);
          for (final c in f.children) {
            visit(c);
          }
        }
        for (final r in roots) {
          visit(r);
        }
        return flat;
      }

      final allFoldersFlat = _flattenFolders(store.folders);

      // フォルダリストを準備（階層パスを含める）
      final availableFolders = allFoldersFlat.map((f) => f.getPath(allFoldersFlat)).toList();

      if (availableFolders.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('フォルダが存在しません')),
          );
        }
        return;
      }

      // ブックマークデータを準備（現在フォルダはフルパスで渡す）
      final bookmarksData = store.bookmarks.map((bm) {
        // フォルダ名を取得
        String folderPath = '未分類';
        if (bm.folderId != null) {
          try {
            final folder = allFoldersFlat.firstWhere((f) => f.id == bm.folderId);
            folderPath = folder.getPath(allFoldersFlat);
          } catch (e) {
            // フォルダが見つからない場合は未分類
          }
        }
        
        return {
          'id': bm.id,
          'title': bm.title,
          'url': bm.url,
          'excerpt': bm.excerpt,
          'current_folder': folderPath,
        };
      }).toList();

      // APIリクエスト
      final response = await http.post(
        Uri.parse('$apiBaseUrl/bulk-assign-folders'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'bookmarks': bookmarksData,
          'available_folders': availableFolders,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('APIエラー: ${response.statusCode}');
      }

      final result = json.decode(utf8.decode(response.bodyBytes));
      final allSuggestions = result['suggestions'] as List;
      
      // 変化があったブックマークのみをフィルタリング
      final changedSuggestions = allSuggestions.where((suggestion) {
        final bookmarkId = suggestion['bookmark_id'] as String;
        final suggestedFolder = suggestion['suggested_folder'] as String;
        
        // 該当するブックマークを検索
        try {
          final bm = bookmarksData.firstWhere((b) => b['id'] == bookmarkId);
          final currentFolder = bm['current_folder']?.toString() ?? '未分類';
          
          // 現在のフォルダと提案されたフォルダが異なる場合のみ含める
          return currentFolder != suggestedFolder;
        } catch (e) {
          return false;
        }
      }).toList();
      
      // suggestions に bookmark_title と current_folder を追加
      final enrichedSuggestions = changedSuggestions.map((suggestion) {
        final bookmarkId = suggestion['bookmark_id'] as String;
        final bm = bookmarksData.firstWhere((b) => b['id'] == bookmarkId);
        
        return <String, dynamic>{
          ...Map<String, dynamic>.from(suggestion),
          'bookmark_title': bm['title'],
          'current_folder': bm['current_folder'],
        };
      }).toList();

      if (!mounted) return;

      // 結果を表示
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => StoreProvider(
          store: store,
          child: BulkFolderAssignmentResultSheet(
            suggestions: enrichedSuggestions,
            onApply: (assignments) async {
              // フォルダ割り当てを適用
              int successCount = 0;
              int failCount = 0;

              // 適用時点の最新のフラット一覧を作成
              List<FolderModel> _flattenApply(List<FolderModel> roots) {
                final List<FolderModel> flat = [];
                void visit(FolderModel f) {
                  flat.add(f);
                  for (final c in f.children) {
                    visit(c);
                  }
                }
                for (final r in roots) {
                  visit(r);
                }
                return flat;
              }
              final allFlatAtApply = _flattenApply(store.folders);

              for (var entry in assignments.entries) {
                final bookmarkId = entry.key;
                final folderPath = entry.value; // 階層パス（例: 「プログラミング / Python」）

                try {
                  // ブックマークを取得
                  final bookmark = store.bookmarks.firstWhere(
                    (bm) => bm.id == bookmarkId,
                  );

                  // フォルダを階層パスで検索（全フォルダから）
                  FolderModel folder = allFlatAtApply.firstWhere(
                    (f) => f.getPath(allFlatAtApply) == folderPath,
                    orElse: () {
                      // 見つからない場合は名前だけで検索（後方互換性）
                      return allFlatAtApply.firstWhere(
                        (f) => f.name == folderPath,
                        orElse: () => allFlatAtApply.first,
                      );
                    },
                  );

                  // フォルダを更新
                  bookmark.folderId = folder.id;
                  await store.updateBookmark(bookmark);

                  successCount++;
                } catch (e) {
                  print('フォルダ割り当てエラー: $e');
                  failCount++;
                }
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '完了: ${successCount}件成功${failCount > 0 ? ", ${failCount}件失敗" : ""}',
                    ),
                    backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
                  ),
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラー: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBulkAssigningFolders = false);
      }
    }
  }

  Future<void> _analyzeFolderStructure(BuildContext context) async {
    // リワード広告チェック（デバッグ用フラグで制御）
    if (requireRewardedAdForAI) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('広告視聴'),
          content: const Text('AI機能を使用するには、広告を視聴する必要があります。広告を視聴しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('視聴する'),
            ),
          ],
        ),
      );

      if (shouldProceed != true) return;

      // 広告を表示して報酬獲得を待つ
      final adCompleted = await RewardedAdManager.showAd();

      if (!adCompleted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('広告を最後まで視聴する必要があります'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }

    final store = StoreProvider.of(context);
    
    setState(() => _isAnalyzingFolders = true);

    try {
      // ブックマークとフォルダのデータを準備
      final bookmarksData = store.bookmarks.map((bm) {
        final folder = store.folders.firstWhere(
          (f) => f.id == bm.folderId,
          orElse: () => FolderModel(id: '', name: '未分類', sortOrder: 0),
        );
        return {
          'title': bm.title,
          'url': bm.url,
          'excerpt': bm.excerpt,
          'current_folder': folder.name,
        };
      }).toList();

      final currentFolders = store.folders.map((f) => f.name).toList();

      // APIリクエスト
      final response = await http.post(
        Uri.parse('$apiBaseUrl/analyze-folder-structure'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'bookmarks': bookmarksData,
          'current_folders': currentFolders,
          // 最大階層数は送信しない（AIが自動で最適な階層を決定）
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('APIエラー: ${response.statusCode}');
      }

      final result = json.decode(response.body);
      
      // FolderStructureAnalysisオブジェクトを作成
      final analysis = FolderStructureAnalysis(
        suggestedFolders: (result['suggested_folders'] as List).map((f) => 
          SuggestedFolder(
            name: f['name'],
            description: f['description'] ?? '',
            reasoning: f['reasoning'] ?? '',
            mergeFrom: (f['merge_from'] as List?)?.cast<String>() ?? [],
            parent: f['parent'] as String?,  // 親フォルダ情報を追加
          )
        ).toList(),
        foldersToRemove: (result['folders_to_remove'] as List).cast<String>(),
        overallReasoning: result['overall_reasoning'],
      );

      if (!mounted) return;

      // 結果を表示
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => StoreProvider(
          store: store,
          child: FolderAnalysisResultSheet(analysis: analysis),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラー: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingFolders = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.primary,
        statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness,
      ),
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _isAnyProcessing ? null : () => widget.scaffoldKey.currentState?.openDrawer(),
          tooltip: 'メニュー',
        ),
        title: const Text('AIツール', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [
          // メインコンテンツ
          AbsorbPointer(
            absorbing: _isAnyProcessing,
            child: Opacity(
              opacity: _isAnyProcessing ? 0.5 : 1.0,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const AdBanner(),
                  const SizedBox(height: 16),
                  // 注意書き
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'AI機能について',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '• 大量のブックマークを効率的に整理・管理するための機能です\n'
                          '• 各機能の利用には動画広告の視聴が必要です',
                          style: TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.auto_awesome, size: 32),
                      title: const Text(
                        'AI タグ構成分析',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      subtitle: const Text(
                        '全ブックマークを分析して最適なタグ構成を提案します',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: _isAnalyzing
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_ios),
                      onTap: _isAnalyzing ? null : () => _analyzeTagStructure(context),
                    ),
                  ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'AIがブックマークの内容を分析し、以下を提案します：\n'
              '• 新しいタグの追加提案\n'
              '• 類似タグの統合提案\n'
              '• 不要なタグの削除提案',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          
          const SizedBox(height: 24),
          
          Card(
            child: ListTile(
              leading: const Icon(Icons.label, size: 32),
              title: const Text(
                'AI 一括タグ割り当て',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: const Text(
                '全ブックマークに対してAIが最適なタグを一括で割り当てます',
                style: TextStyle(fontSize: 12),
              ),
              trailing: _isBulkAssigning
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_ios),
              onTap: _isBulkAssigning ? null : () => _bulkAssignTags(context),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'AIが各ブックマークを分析し、適切なタグを自動的に割り当てます：\n'
              '• 既存のタグから最適なものを選択\n'
              '• ブックマークの内容に基づいて判断\n'
              '• 検索・フィルタリングに役立つタグを優先',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          
          const SizedBox(height: 24),
          
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_special, size: 32),
              title: const Text(
                'AI フォルダ構成分析',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: const Text(
                '全ブックマークを分析して最適なフォルダ構成を提案します',
                style: TextStyle(fontSize: 12),
              ),
              trailing: _isAnalyzingFolders
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_ios),
              onTap: _isAnalyzingFolders ? null : () => _analyzeFolderStructure(context),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AIがブックマークの内容を分析し、以下を提案します：\n'
                  '• 新しいフォルダの追加提案\n'
                  '• 類似フォルダの統合提案\n'
                  '• 不要なフォルダの削除提案\n'
                  '※ 現在のフォルダとブックマークの紐付きは全て解除されます\n',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder, size: 32),
              title: const Text(
                'AI 一括フォルダ割り当て',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: const Text(
                '全ブックマークに対してAIが最適なフォルダを一括で割り当てます',
                style: TextStyle(fontSize: 12),
              ),
              trailing: _isBulkAssigningFolders
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_ios),
              onTap: _isBulkAssigningFolders ? null : () => _bulkAssignFolders(context),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'AIが各ブックマークを分析し、適切なフォルダを自動的に割り当てます：\n'
              '• 既存のフォルダから最適なものを選択\n'
              '• ブックマークの内容に基づいて判断\n'
              '• 整理・分類に役立つフォルダを優先',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
                ],
              ),
            ),
          ),
          
          // ローディングオーバーレイ
          if (_isAnyProcessing)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          strokeWidth: 4,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _currentProcessingMessage,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'しばらくお待ちください...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }
}

class TagsScreen extends StatelessWidget { const TagsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreProvider.of(context);
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.primary,
        statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness,
      ),
      child: Stack(
        children: [
          Container(
            height: MediaQuery.of(context).padding.top,
            color: theme.colorScheme.primary,
          ),
          SafeArea(child: _TagsScreenBody(store: store)),
        ],
      ),
    );
  }
}

class _TagsScreenBody extends StatefulWidget {
  final AppStore store;
  const _TagsScreenBody({required this.store});
  @override
  State<_TagsScreenBody> createState() => _TagsScreenBodyState();
}

class _TagsScreenBodyState extends State<_TagsScreenBody> {
  String _searchText = '';
  String _sort = 'name_asc';
  final Set<String> _selectedIds = {};
  bool _selectionModeFlag = false;
  bool get _selectionMode => _selectionModeFlag;

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectionModeFlag = false;
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
  final BuildContext ctx = this.context;
    if (ids.isEmpty) return;
    final tagNames = ids.map((id) => widget.store.tags.firstWhere((t) => t.id == id).name).toList();
    final count = ids.length;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('タグを削除しますか？'),
        content: Text(count == 1
            ? 'タグ「${tagNames.first}」を削除します。'
            : '選択した${count}件のタグを削除します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok == true) {
      for (final id in ids) {
        final tag = widget.store.tags.firstWhere((t) => t.id == id);
        await widget.store.removeTag(tag);
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('タグ「${tag.name}」を削除しました')));
      }
      _clearSelection();
      await widget.store.fetchTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    List<TagModel> tags = widget.store.tags.where((t) => t.name.contains(_searchText)).toList();
    switch (_sort) {
      case 'name_asc':
        tags.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'name_desc':
        tags.sort((a, b) => b.name.compareTo(a.name));
        break;
    }

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              floating: true,
              snap: true,
              title: _selectionMode
                  ? Text('${_selectedIds.length}件選択中', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  : const Text('タグ一覧', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              leading: _selectionMode
                  ? IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection, tooltip: '選択解除')
                  : null,
              actions: [],
            ),
            const SliverToBoxAdapter(
              child: AdBanner(),
            ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'タグ名で検索',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _searchText = v),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => _showAddTagDialog(context),
                        tooltip: '新規タグ作成',
                      ),
                      IconButton(
                        icon: Icon(_selectionMode ? Icons.delete : Icons.check_box),
                        color: _selectionMode ? Colors.red : null,
                        onPressed: _selectionMode
                            ? (_selectedIds.isEmpty ? null : _deleteSelected)
                            : () => setState(() {
                                  _selectedIds.clear();
                                  _selectionModeFlag = true;
                                }),
                        tooltip: _selectionMode ? '選択したタグを削除' : '複数選択モード',
                      ),
                      PopupMenuButton<String>(
                        tooltip: '並び替え',
                        icon: const Icon(Icons.sort),
                        onSelected: (v) => setState(() => _sort = v),
                        itemBuilder: (c) => const [
                          PopupMenuItem(value: 'name_asc', child: Text('名前昇順')),
                          PopupMenuItem(value: 'name_desc', child: Text('名前降順')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (tags.isEmpty)
              const SliverFillRemaining(child: Center(child: Text('タグがありません')))
            else
              SliverList.separated(
                itemCount: tags.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (c, i) {
                  final t = tags[i];
                  final count = widget.store.bookmarks.where((b) => b.tags.any((x) => x.id == t.id)).length;
                  return ListTile(
                    leading: const Icon(Icons.tag),
                    title: Text(t.name),
                    subtitle: Text('$count 件'),
                    trailing: _selectionMode
                        ? Checkbox(
                            value: _selectedIds.contains(t.id),
                            onChanged: (_) => _toggleSelect(t.id),
                          )
                        : PopupMenuButton<String>(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: '編集・削除',
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showEditTagDialog(context, t);
                              } else if (value == 'delete') {
                                _confirmDeleteTag(context, t);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('編集')),
                              PopupMenuItem(value: 'delete', child: Text('削除')),
                            ],
                          ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
        if (_selectionMode)
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton.extended(
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete),
              label: const Text('削除'),
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
          ),
      ],
    );
  }
}

class FolderScreen extends StatelessWidget {
  final FolderModel folder;
  const FolderScreen({super.key, required this.folder});

  @override
  Widget build(BuildContext context) {
    final store = StoreProvider.of(context);

    FolderModel? findFolderById(List<FolderModel> list, String id) {
      for (final f in list) {
        if (f.id == id) return f;
        final sub = findFolderById(f.children, id);
        if (sub != null) return sub;
      }
      return null;
    }

    final currentFolder = findFolderById(store.folders, folder.id) ?? folder;

    List<FolderModel> buildBreadcrumb(FolderModel node) {
      final path = <FolderModel>[];
      FolderModel? cur = node;
      while (cur != null) {
        path.insert(0, cur);
        if (cur.parentId == null) break;
        cur = findFolderById(store.folders, cur.parentId!);
      }
      return path;
    }

    final bookmarks = store.byFolder(currentFolder.id);
    final subfolders = currentFolder.children;
    final breadcrumbPath = buildBreadcrumb(currentFolder);

  final theme = Theme.of(context);
  return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.primary,
        statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness,
      ),
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        title: Text(currentFolder.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _showAddFolderDialog(context, currentFolder.id),
            tooltip: 'サブフォルダ追加',
          ),
        ],
      ),
      body: bookmarks.isEmpty && subfolders.isEmpty
          ? const Center(child: Text('このフォルダは空です'))
          : CustomScrollView(
              slivers: [
                if (breadcrumbPath.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                        border: Border(
                          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (int i = 0; i < breadcrumbPath.length; i++) ...[
                              if (i > 0)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(Icons.chevron_right, size: 16, color: Theme.of(context).textTheme.bodySmall?.color),
                                ),
                              InkWell(
                                onTap: i < breadcrumbPath.length - 1
                                    ? () {
                                        Navigator.of(context).pushReplacement(
                                          MaterialPageRoute(
                                            builder: (ctx) => StoreProvider(
                                              store: store,
                                              child: FolderScreen(folder: breadcrumbPath[i]),
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Text(
                                    breadcrumbPath[i].name,
                                    style: TextStyle(
                                      color: i < breadcrumbPath.length - 1
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).textTheme.bodyMedium?.color,
                                      fontWeight: i == breadcrumbPath.length - 1 ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                if (subfolders.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text('サブフォルダ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          onReorder: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex--;
                            final moved = subfolders.removeAt(oldIndex);
                            subfolders.insert(newIndex, moved);
                            for (int i = 0; i < subfolders.length; i++) {
                              subfolders[i].sortOrder = i;
                            }
                            store.updateFolderOrder(currentFolder.id, subfolders);
                          },
                          children: [
                            for (int i = 0; i < subfolders.length; i++)
                              ListTile(
                                key: ValueKey(subfolders[i].id),
                                leading: Icon(subfolders[i].children.isNotEmpty ? Icons.folder_open_outlined : Icons.folder_outlined),
                                title: Text(subfolders[i].name),
                                subtitle: Text('${store.byFolder(subfolders[i].id).length} 件'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                                      onPressed: () => _showAddFolderDialog(context, subfolders[i].id),
                                      tooltip: 'サブフォルダ追加',
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      tooltip: 'フォルダ編集',
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _showEditFolderDialog(context, subfolders[i]);
                                        } else if (value == 'delete') {
                                          _confirmDeleteFolder(context, subfolders[i]);
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(value: 'edit', child: Text('編集')),
                                        PopupMenuItem(value: 'delete', child: Text('削除')),
                                      ],
                                    ),
                                    const Icon(Icons.drag_handle),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (ctx) => StoreProvider(
                                        store: store,
                                        child: FolderScreen(folder: subfolders[i]),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        const Divider(height: 24),
                      ],
                    ),
                  ),
                if (bookmarks.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: bookmarks.length,
                      itemBuilder: (c, i) => BookmarkGridCard(bm: bookmarks[i], store: store),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (ctx) => StoreProvider(
              store: store,
              child: AddBookmarkSheet(folderId: currentFolder.id),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('追加'),
      ),
    ),
    );
  }
}

class DetailScreen extends StatelessWidget { final BookmarkModel bm; const DetailScreen({super.key, required this.bm});
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context); final store = StoreProvider.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.primary,
        statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness,
      ),
      child: Scaffold(
  appBar: AppBar(title: Text(bm.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: theme.colorScheme.primary),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bm.url, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 12),
          Text('要約', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(bm.excerpt),
          const Spacer(),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () { store.opened(bm); Navigator.pop(context); }, icon: const Icon(Icons.open_in_browser), label: const Text('開く'))),
          ])
        ]),
      ),
    ),
    );
  }
}

// ===== Home Widgets =====
class _SearchBar extends StatefulWidget { const _SearchBar(); @override State<_SearchBar> createState() => _SearchBarState(); }
class _SearchBarState extends State<_SearchBar> {
  final controller = TextEditingController();
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final store = StoreProvider.of(context);
    controller.text = store.searchText;
    controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: (v) => store.updateSearchText(v),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '検索（タイトル / URL / タグ / 要約）', border: OutlineInputBorder()),
      ),
    );
  }
}


class _Section extends StatelessWidget { final String title; final Widget child; final Widget? action; const _Section({required this.title, required this.child, this.action});
  @override Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [ Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))), if (action != null) action! ]),
        ),
        child,
      ]),
    );
  }
}


class BookmarkCard extends StatelessWidget {
  final BookmarkModel bm;
  final AppStore store;
  const BookmarkCard({super.key, required this.bm, required this.store});
  @override Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          store.opened(bm);
          final uri = Uri.parse(bm.url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              bm.thumbnailUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: _buildThumbnailWidget(
                        bm.thumbnailUrl!,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Icon(Icons.link, size: 72),
              const SizedBox(width: 16),
              Expanded(child: Text(bm.title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
              PopupMenuButton<String>(
                tooltip: '編集・削除',
                icon: const Icon(Icons.edit_outlined),
                onSelected: (value) async {
                  if (value == 'edit') {
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (ctx) => StoreProvider(
                        store: store,
                        child: AddBookmarkSheet(bm: bm),
                      ),
                    );
                  } else if (value == 'delete') {
                    // 確認ダイアログ
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('ブックマークを削除しますか？'),
                        content: const Text('この操作は元に戻せません。'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await store.removeBookmark(bm);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ブックマークを削除しました')));
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('編集')),
                  const PopupMenuItem(value: 'delete', child: Text('削除')),
                ],
              ),
              IconButton(tooltip: bm.isPinned ? 'ピン解除' : 'ピン留め', icon: Icon(bm.isPinned ? Icons.push_pin : Icons.push_pin_outlined), onPressed: () => store.togglePin(bm)),
            ]),
            const SizedBox(height: 4),
            Text(bm.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: -8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ...bm.tags.map((t) => Chip(label: Text('#${t.name}'), visualDensity: VisualDensity.compact)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text(bm.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary))),
              const SizedBox(width: 8),
                // 削除ボタンはPopupMenuに統一
            ])
          ]),
        ),
      ),
    );
  }
}

class BookmarkGridCard extends StatelessWidget {
  final BookmarkModel bm;
  final AppStore store;
  const BookmarkGridCard({super.key, required this.bm, required this.store});
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          store.opened(bm);
          final uri = Uri.parse(bm.url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: MarqueeText(
                      text: bm.title,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

                const SizedBox(height: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey, width: 1.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      width: double.infinity,
                      child: bm.thumbnailUrl != null
                          ? _buildThumbnailWidget(
                              bm.thumbnailUrl!,
                              fit: BoxFit.cover,
                            )
                          : const Center(child: Icon(Icons.link, size: 48)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8, left: 8),
                  child: Builder(builder: (context) {
                    final tags = bm.tags;
                    if (tags.isEmpty) return const SizedBox.shrink();
                    return SizedBox(
                      height: 22,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: tags.length,
                        separatorBuilder: (context, i) => const SizedBox(width: 4),
                        itemBuilder: (context, i) => Chip(
                          label: Text(tags[i].name, style: const TextStyle(fontSize: 10, color: Color(0xFF607D8B))),
                          backgroundColor: Colors.grey[200],
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                          side: BorderSide.none,
                        ),
                      ),
                    );
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 0, right: 8, left: 8, bottom: 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: '編集・削除',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (ctx) => StoreProvider(
                                store: store,
                                child: AddBookmarkSheet(bm: bm),
                              ),
                            );
                          } else if (value == 'delete') {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('ブックマークを削除しますか？'),
                                content: const Text('この操作は元に戻せません。'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await store.removeBookmark(bm);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ブックマークを削除しました')));
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'edit', child: Text('編集')),
                          const PopupMenuItem(value: 'delete', child: Text('削除')),
                        ],
                      ),
                      IconButton(
                        tooltip: bm.isPinned ? 'ピン解除' : 'ピン留め',
                        icon: Icon(bm.isPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                        onPressed: () => store.togglePin(bm),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
                // URL表示削除
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Folder Tree View =====
class _FolderTreeView extends StatelessWidget {
  final List<FolderModel> folders;
  final Function(int, int)? onReorder;
  const _FolderTreeView({required this.folders, this.onReorder});

  @override
  Widget build(BuildContext context) {
    final store = StoreProvider.of(context);
    if (onReorder != null) {
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: folders.length,
        onReorder: onReorder!,
        itemBuilder: (c, i) {
          final folder = folders[i];
          final count = store.countBookmarksRecursive(folder.id);
          // final hasChildren = folder.children.isNotEmpty; // not used

          // 全てのフォルダカードをAccordionFolderTileで統一
          return _AccordionFolderTile(
            key: ValueKey(folder.id),
            folder: folder,
            count: count,
            store: store,
            onAdd: () => _showAddFolderDialog(context, folder.id),
            onEdit: () => _showEditFolderDialog(context, folder),
            onDelete: () => _confirmDeleteFolder(context, folder),
            childBuilder: () => Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _buildFolderList(context, folder.children, store),
            ),
          );
        },
      );
    }
    return _buildFolderList(context, folders, store);
  }

  Widget _buildFolderList(BuildContext context, List<FolderModel> folders, AppStore store) {
    return ReorderableListView.builder(
      key: const PageStorageKey<String>('folder_list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: folders.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        final item = folders.removeAt(oldIndex);
        folders.insert(newIndex, item);
      },
      itemBuilder: (c, i) {
        final folder = folders[i];
        final count = store.countBookmarksRecursive(folder.id);
        // すべてのフォルダカードをアコーディオンカードで表示
        return _AccordionFolderTile(
          key: ValueKey(folder.id),
          folder: folder,
          count: count,
          store: store,
          onAdd: () => _showAddFolderDialog(context, folder.id),
          onEdit: () => _showEditFolderDialog(context, folder),
          onDelete: () => _confirmDeleteFolder(context, folder),
          childBuilder: () => Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _buildFolderList(context, folder.children, store),
          ),
        );
      },
    );
  }
}

// ===== Aux Screens =====
class TutorialScreen extends StatelessWidget { 
  const TutorialScreen({super.key});
  
  @override 
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.primary,
        statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness,
      ),
      child: Scaffold(
  appBar: AppBar(title: const Text('使い方', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: theme.colorScheme.primary),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          // アプリの概要
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('このアプリについて', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('ウェブ記事を簡単にブックマークし、整理・検索・活用できるアプリです。AIによるサポートも今後充実させていきます。'),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          
          // 基本的な使い方
          Text('基本的な使い方', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          
          ListTile(
            leading: Icon(Icons.add_circle_outline, color: Colors.green),
            title: Text('1. ブックマークを追加', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('画面右下の「＋追加」ボタンをタップして情報を入力しましょう。Safariなどの共有メニューからも追加できます。タイトルやサムネイルはボタン一つで自動で取得されます。'),
          ),
          Divider(),
          
          ListTile(
            leading: Icon(Icons.folder_open, color: Colors.orange),
            title: Text('2. フォルダで整理', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('フォルダを作成してブックマークを分類、管理しましょう。ドラッグ＆ドロップで並び替えも可能です。フォルダの中に子フォルダを作成できます。'),
          ),
          Divider(),
          
          ListTile(
            leading: Icon(Icons.label_outline, color: Colors.purple),
            title: Text('3. タグで分類', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('タグを付けることで検索しやすくしましょう。1つのブックマークに複数のタグを付けられます。AIによる自動タグ提案機能も利用可能です。'),
          ),
          Divider(),
          
          ListTile(
            leading: Icon(Icons.search, color: Colors.blue),
            title: Text('4. 検索とフィルタ', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('キーワードで検索したり、タグ・フォルダで絞り込んで目当てのブックマークを探しましょう。'),
          ),
          Divider(),
          
          // ListTile(
          //   leading: Icon(Icons.check_circle_outline, color: Colors.teal),
          //   title: Text('5. 読了マーク＆メモ', style: TextStyle(fontWeight: FontWeight.bold)),
          //   subtitle: Text('読んだ記事には「読了」マークを付けたり、メモを残したりできます。後で見返すときに便利です。'),
          // ),
          
          SizedBox(height: 24),
          
          // 便利な機能
          Text('便利な機能', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          
          // ListTile(
          //   leading: Icon(Icons.share, color: Colors.indigo),
          //   title: Text('共有シートから追加', style: TextStyle(fontWeight: FontWeight.bold)),
          //   subtitle: Text('Safariや他のアプリで見つけた記事を、共有メニューから直接このアプリに保存できます。'),
          // ),
          // Divider(),
          
          ListTile(
            leading: Icon(Icons.pin_outlined, color: Colors.red),
            title: Text('ピン留め機能', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('重要なブックマークをピン留めして、ホーム画面の上部に固定表示できます。'),
          ),
          Divider(),
          
          ListTile(
            leading: Icon(Icons.sort, color: Colors.brown),
            title: Text('AIブックマーク管理', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('フォルダやタグの構成提案、各ブックマークの割り当てをAIがサポートします。大量のブックマークを効率的に整理できます。'),
          ),
          Divider(),
          
          ListTile(
            leading: Icon(Icons.backup_outlined, color: Colors.green),
            title: Text('バックアップ機能', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('メニューから「データエクスポート」でブックマーク、フォルダ、タグをJSON形式で保存できます。「データインポート」で復元も可能です。機種変更時やデータ移行に便利です。'),
          ),
          
          SizedBox(height: 24),
          
          // よくある質問
          Text('よくある質問', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Q. サムネイルが表示されない', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('A. 一部のサイト（特にログインが必要なサイト）では自動取得できない場合があります。その場合は手動で画像を設定することも可能です。'),
                  SizedBox(height: 12),
                  Text('Q. データのバックアップは？', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('A. データはユーザーの端末内に保存されています。メニューの"バックアップ"からデータをエクスポート、インポートすることでバックアップ、復元が可能です。'),
                  SizedBox(height: 12),
                  Text('Q. フォルダを削除するとどうなる？', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('A. フォルダ内のブックマークは削除されず、「未分類」に移動します。'),
                ],
              ),
            ),
          ),
          
          SizedBox(height: 24),
          
          // フッター
          Center(
            child: Text(
              'その他の使い方やご要望は「不具合報告/改善依頼」からご連絡ください',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24),
        ],
      ),
    ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedBrowser = 'default'; // default, safari, chrome, edge
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedBrowser = prefs.getString('selectedBrowser') ?? 'default';
      _isLoading = false;
    });
  }
  
  Future<void> _saveBrowserSetting(String browser) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedBrowser', browser);
    setState(() {
      _selectedBrowser = browser;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: theme.colorScheme.primary,
          statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
          statusBarBrightness: theme.brightness,
        ),
        child: Scaffold(
          appBar: AppBar(title: const Text('各種設定'), backgroundColor: theme.colorScheme.primary),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.primary,
        statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness,
      ),
      child: Scaffold(
  appBar: AppBar(title: const Text('各種設定', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: theme.colorScheme.primary),
      body: ListView(
        children: [
          // ブラウザ設定（コメントアウト）
          // const Padding(
          //   padding: EdgeInsets.all(16),
          //   child: Text(
          //     'ブラウザ設定',
          //     style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
          //   ),
          // ),
          // ListTile(
          //   leading: const Icon(Icons.open_in_browser),
          //   title: const Text('ブックマークを開くブラウザ'),
          //   subtitle: Text(_getBrowserLabel()),
          //   trailing: const Icon(Icons.chevron_right),
          //   onTap: () {
          //     _showBrowserDialog();
          //   },
          // ),
          // const Padding(
          //   padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          //   child: Text(
          //     'ブックマークをタップした際に開くブラウザを選択できます',
          //     style: TextStyle(fontSize: 12, color: Colors.grey),
          //   ),
          // ),
          // const Divider(),
          
          // データ管理
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'データ管理',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('すべてのデータを削除', style: TextStyle(color: Colors.red)),
            subtitle: const Text('ブックマーク、フォルダ、タグ、サムネイル画像などをすべて削除'),
            onTap: () {
              _showDeleteAllDataDialog();
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '端末内の本アプリに関連するすべてのデータが削除されます。この操作は取り消せません。',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    ),
    );
  }
  
  String _getBrowserLabel() {
    switch (_selectedBrowser) {
      case 'default':
        return 'デバイスのデフォルトブラウザ';
      case 'safari':
        return 'Safari';
      case 'chrome':
        return 'Google Chrome';
      case 'edge':
        return 'Microsoft Edge';
      default:
        return 'デバイスのデフォルトブラウザ';
    }
  }
  
  void _showBrowserDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ブラウザを選択'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('デバイスのデフォルトブラウザ'),
              value: 'default',
              groupValue: _selectedBrowser,
              onChanged: (value) async {
                await _saveBrowserSetting(value!);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('デバイスのデフォルトブラウザに設定しました')),
                  );
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('Safari'),
              value: 'safari',
              groupValue: _selectedBrowser,
              onChanged: (value) async {
                await _saveBrowserSetting(value!);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Safariに設定しました')),
                  );
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('Google Chrome'),
              value: 'chrome',
              groupValue: _selectedBrowser,
              onChanged: (value) async {
                await _saveBrowserSetting(value!);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Google Chromeに設定しました')),
                  );
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('Microsoft Edge'),
              value: 'edge',
              groupValue: _selectedBrowser,
              onChanged: (value) async {
                await _saveBrowserSetting(value!);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Microsoft Edgeに設定しました')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
  
  void _showDeleteAllDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('データ削除の確認'),
        content: const Text(
          'すべてのブックマーク、フォルダ、タグ、サムネイル画像が完全に削除されます。\n\nこの操作は取り消せません。本当に削除しますか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              // 削除処理を実行
              try {
                final store = StoreProvider.of(context);
                
                // すべてのブックマークを削除（サムネイル画像も削除される）
                final bookmarks = List.from(store.bookmarks);
                for (final bm in bookmarks) {
                  await store.removeBookmark(bm);
                }
                
                // すべてのタグを削除
                final tags = List.from(store.tags);
                for (final tag in tags) {
                  await store.removeTag(tag);
                }
                
                // すべてのフォルダを削除
                final folders = List.from(store.folders);
                for (final folder in folders) {
                  await store.deleteFolder(folder.id);
                }
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('すべてのデータを削除しました'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('削除中にエラーが発生しました: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }
}

class ReportScreen extends StatelessWidget { const ReportScreen({super.key});
  @override Widget build(BuildContext context) {
    final controller = TextEditingController();
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.primary,
        statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness,
      ),
  child: Scaffold(appBar: AppBar(title: const Text('不具合報告/改善依頼', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: theme.colorScheme.primary),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        TextField(controller: controller, minLines: 6, maxLines: 12, decoration: const InputDecoration(labelText: '内容を入力', border: OutlineInputBorder(), hintText: '再現手順・期待する挙動 など…')),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('送信'),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('送信しました')));
            Navigator.pop(context);
          },
        ))
      ])),
    ));
  }
}

class PrivacyScreen extends StatelessWidget { 
  const PrivacyScreen({super.key});
  
  @override 
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.primary,
        statusBarIconBrightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness,
      ),
      child: Scaffold(
  appBar: AppBar(title: const Text('プライバシーポリシー', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: theme.colorScheme.primary),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'プライバシーポリシー',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            '最終更新日: 2025年10月18日',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          SizedBox(height: 24),
          
          // データの保存場所
          Text(
            '1. データの保存について',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            '本アプリで作成・保存されたブックマーク、フォルダ、タグ、メモなどのすべてのデータは、ユーザー様の端末内にのみ保存されます。',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 8),
          Text(
            '第三者のサーバーや外部サービスにデータが送信されることは、AI機能を使用する場合を除き、一切ありません。',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 24),
          
          // AI機能について
          Text(
            '2. AI機能のデータ送信について',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            '本アプリでは、AI機能（自動タグ提案、フォルダ分類など）を提供しています。これらの機能を使用する場合に限り、以下の情報がサーバーに送信されます：',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ブックマークのタイトル', style: TextStyle(height: 1.5)),
                Text('• フォルダ名', style: TextStyle(height: 1.5)),
                Text('• タグ名', style: TextStyle(height: 1.5)),
                Text('• ブックマークの概要（抜粋）', style: TextStyle(height: 1.5)),
              ],
            ),
          ),
          SizedBox(height: 8),
          Text(
            '送信されたデータは、AI機能の提供および改善のために使用され、機械学習モデルのトレーニングに用いられる可能性があります。',
            style: TextStyle(height: 1.5, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'AI機能は任意でご利用いただけます。使用しない場合、データがサーバーに送信されることはありません。',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 24),
          
          // 診断情報
          Text(
            '3. 診断情報・分析について',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            '本アプリは、ユーザー様の利用状況、診断情報、分析データなどを収集いたしません。',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 24),
          
          // 第三者への提供
          Text(
            '4. 第三者への情報提供',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            '本アプリは、ユーザー様の個人情報や利用データを第三者に販売、共有、または提供することはありません。',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 8),
          Text(
            'ただし、AI機能を使用する場合は、前述の通り、AI処理のために必要なデータがサーバーに送信されます。',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 24),
          
          // データの削除
          Text(
            '5. データの削除',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'アプリをアンインストールすることで、端末内に保存されているすべてのデータが削除されます。',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 24),
          
          // セキュリティ
          Text(
            '6. セキュリティ',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'データは端末内に保存されるため、端末のセキュリティ設定（パスコード、生体認証など）によって保護されます。',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 24),
          
          // ポリシーの変更
          Text(
            '7. プライバシーポリシーの変更',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            '本プライバシーポリシーは、必要に応じて変更されることがあります。変更後のポリシーは、アプリ内で確認できます。',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 24),
          
          // お問い合わせ
          Text(
            '8. お問い合わせ',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'プライバシーポリシーに関するご質問は、「不具合報告/改善依頼」からお問い合わせください。',
            style: TextStyle(height: 1.5),
          ),
          SizedBox(height: 32),
        ],
      ),
    ),
    );
  }
}

// ===== Add Sheet =====
class AddBookmarkSheet extends StatefulWidget { 
  final String? folderId;
  final BookmarkModel? bm; // 編集モード用
  final String? initialUrl; // Share Extensionから渡されるURL
  final String? initialTitle; // Share Extensionから渡されるタイトル
  final String? initialExcerpt; // Share Extensionから渡されるメモ
  final String? initialTagsText; // Share Extensionから渡されるタグ（カンマ区切り）
  final String? initialFolderName; // Share Extensionから渡されるフォルダ名
  
  const AddBookmarkSheet({
    super.key, 
    this.folderId, 
    this.bm,
    this.initialUrl,
    this.initialTitle,
    this.initialExcerpt,
    this.initialTagsText,
    this.initialFolderName,
  }); 
  
  @override 
  State<AddBookmarkSheet> createState() => _AddBookmarkSheetState(); 
}

class _AddBookmarkSheetState extends State<AddBookmarkSheet> {
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _memo = TextEditingController();
  final List<TagModel> _selected = [];
  String? _folderId;
  final _newTagController = TextEditingController();
  String? _thumbnailUrl; // サムネイルURL保存用
  
  @override 
  void initState() {
    super.initState();
    _folderId = widget.folderId ?? widget.bm?.folderId;
    // 編集モードの場合は既存データを設定
    if (widget.bm != null) {
      _title.text = widget.bm!.title;
      _url.text = widget.bm!.url;
      _memo.text = widget.bm!.excerpt;
      _selected.addAll(widget.bm!.tags);
      _thumbnailUrl = widget.bm!.thumbnailUrl;
    } else {
      // Share Extensionからのデータを設定
      if (widget.initialUrl != null) {
        _url.text = widget.initialUrl!;
      }
      if (widget.initialTitle != null) {
        _title.text = widget.initialTitle!;
      }
      if (widget.initialExcerpt != null && widget.initialExcerpt!.isNotEmpty) {
        _memo.text = widget.initialExcerpt!;
      }
      // Build後にcontextを使ってフォルダ/タグを解決
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final store = StoreProvider.of(context);
        // フォルダ名からIDを解決
        if (widget.initialFolderName != null && widget.initialFolderName!.isNotEmpty) {
          final folder = store.folders.firstWhere(
            (f) => f.name == widget.initialFolderName,
            orElse: () => FolderModel(id: '', name: '', sortOrder: 0),
          );
          if (folder.id.isNotEmpty) {
            setState(() { _folderId = folder.id; });
          }
        }
        // タグ文字列を選択に反映（既存タグのみ）
        if (widget.initialTagsText != null && widget.initialTagsText!.isNotEmpty) {
          final names = widget.initialTagsText!
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (names.isNotEmpty) {
            setState(() {
              for (final name in names) {
                final tag = store.tags.firstWhere(
                  (t) => t.name == name,
                  orElse: () => TagModel(id: '', name: ''),
                );
                if (tag.id.isNotEmpty && !_selected.any((t) => t.id == tag.id)) {
                  _selected.add(tag);
                }
              }
            });
          }
        }
      });
    }
  }
  
  @override void dispose() { _title.dispose(); _url.dispose(); _memo.dispose(); _newTagController.dispose(); super.dispose(); }
  
  /// AIを使ってタグを自動提案
  Future<void> _suggestTagsWithAI(BuildContext context) async {
    final store = StoreProvider.of(context);
    
    // 入力チェック
    if (_title.text.trim().isEmpty && _url.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タイトルまたはURLを入力してください')),
      );
      return;
    }
    
    // 既存タグがない場合
    if (store.tags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('既存のタグがありません。先にタグを作成してください。')),
      );
      return;
    }
    
    // ローディング表示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('AIがタグを分析中...'),
              ],
            ),
          ),
        ),
      ),
    );
    
    try {
      // API呼び出し
      final suggestedTagNames = await TagSuggestionService.suggestTags(
        title: _title.text.trim(),
        url: _url.text.trim(),
        excerpt: _memo.text.trim(),
        existingTags: store.tags.map((t) => t.name).toList(),
      );
      
      // ローディングを閉じる
      Navigator.of(context).pop();
      
      if (suggestedTagNames.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('適切なタグが見つかりませんでした')),
        );
        return;
      }
      
      // タグ名からTagModelを検索して選択状態に追加
      setState(() {
        for (final tagName in suggestedTagNames) {
          final tag = store.tags.firstWhere(
            (t) => t.name == tagName,
            orElse: () => TagModel(id: '', name: ''),
          );
          if (tag.id.isNotEmpty && !_selected.any((t) => t.id == tag.id)) {
            _selected.add(tag);
          }
        }
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${suggestedTagNames.length}個のタグを提案しました: ${suggestedTagNames.join(", ")}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // ローディングを閉じる
      Navigator.of(context).pop();
      // デバッグ用にエラー内容をコンソール出力
      print('[AIタグ提案エラー] $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('タグ提案に失敗しました: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  
  @override Widget build(BuildContext context) {
    final store = StoreProvider.of(context); 
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [ Expanded(child: Text(widget.bm != null ? 'ブックマークを編集' : 'ブックマークを追加', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)) ]),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'タイトル', border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'タイトルを入力' : null,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'タイトルをクリア',
                    onPressed: () {
                      setState(() {
                        _title.clear();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('タイトル自動'),
                    onPressed: () async {
                      final url = _url.text.trim();
                      if (url.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URLを入力してください')));
                        return;
                      }
                      final title = await fetchWebPageTitle(url);
                      if (title != null && title.isNotEmpty) {
                        setState(() => _title.text = title);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('タイトルを取得しました')));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('タイトルを取得できませんでした')));
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _url,
                      decoration: const InputDecoration(labelText: 'URL', border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'URLを入力' : null,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'URLをクリア',
                    onPressed: () {
                      setState(() {
                        _url.clear();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.image),
                      label: const Text('サムネイル自動取得'),
                      onPressed: () async {
                        final url = _url.text.trim();
                        if (url.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('URLを入力してください'))
                          );
                          return;
                        }
                        
                        // 取得中の表示
                        ScaffoldMessenger.of(context).clearSnackBars();
                        final messenger = ScaffoldMessenger.of(context);
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('サムネイルを取得中...\n（スクショ→OGP画像→ファビコンの順に試行）'),
                            duration: Duration(seconds: 30),
                          )
                        );
                        
                        // フォールバック機能を使用
                        final thumbnailPath = await ThumbnailService.getThumbnailWithFallback(url);
                        
                        if (!mounted) return;
                        
                        // 「取得中」メッセージをクリア
                        messenger.clearSnackBars();
                        
                        if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
                          setState(() {
                            _thumbnailUrl = thumbnailPath;
                          });
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('✓ サムネイルを取得しました'),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            )
                          );
                        } else {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('サムネイルを取得できませんでした\n（すべての取得方法が失敗しました）'),
                              backgroundColor: Colors.orange,
                              duration: Duration(seconds: 4),
                            )
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('画像アップロード'),
                      onPressed: () async {
                        final picked = await _picker.pickImage(source: ImageSource.gallery);
                        if (picked != null) {
                          setState(() {
                            _thumbnailUrl = picked.path;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('画像を選択しました')));
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // サムネイルプレビュー
              if (_thumbnailUrl != null && _thumbnailUrl!.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('サムネイル', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.delete, size: 16),
                          label: const Text('削除'),
                          onPressed: () {
                            setState(() {
                              _thumbnailUrl = null;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: _isFavicon(_thumbnailUrl)
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: _buildThumbnailWidget(
                                      _thumbnailUrl!,
                                      width: 64,
                                      height: 64,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'ファビコン（元サイズ）',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _buildThumbnailWidget(
                                _thumbnailUrl!,
                                height: 192,
                                width: 192 / 0.85,
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              TextFormField(controller: _memo, decoration: const InputDecoration(labelText: 'メモ', border: OutlineInputBorder()), maxLines: 3),
              const SizedBox(height: 12),
              _BookmarkFolderSelector(
                selectedFolderId: _folderId,
                onFolderSelected: (folderId) => setState(() => _folderId = folderId),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('タグ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('AI自動提案'),
                    onPressed: () => _suggestTagsWithAI(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: store.tags.map((t) { final selected = _selected.any((x) => x.id == t.id); return FilterChip(label: Text('#${t.name}'), selected: selected, onSelected: (v) { setState(() { if (v) { _selected.add(t); } else { _selected.removeWhere((x) => x.id == t.id); } }); }); }).toList()),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTagController,
                        decoration: const InputDecoration(labelText: '新しいタグ', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('追加'),
                      onPressed: () {
                        final name = _newTagController.text.trim();
                        if (name.isEmpty) return;
                        final newTag = TagModel(id: UniqueKey().toString(), name: name);
                        store.addTag(newTag);
                        Future.delayed(const Duration(milliseconds: 100), () {
                          final tag = store.tags.lastWhere(
                            (t) => t.name == name,
                            orElse: () => TagModel(id: '', name: ''),
                          );
                          if (tag.id.isNotEmpty) {
                            setState(() {
                              _selected.add(tag);
                              _newTagController.clear();
                            });
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                icon: const Icon(Icons.save), 
                label: Text(widget.bm != null ? '更新' : '保存'), 
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  final store = StoreProvider.of(context);
                  
                  if (widget.bm != null) {
                    // 編集モード
                    widget.bm!.title = _title.text.trim();
                    widget.bm!.url = _url.text.trim();
                    widget.bm!.excerpt = _memo.text.trim();
                    widget.bm!.folderId = _folderId;
                    widget.bm!.tags = List.of(_selected);
                    widget.bm!.thumbnailUrl = _thumbnailUrl;
                    try {
                      await store.updateBookmark(widget.bm!);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ブックマークを更新しました')));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('更新失敗: $e')),
                      );
                    }
                  } else {
                    // 新規追加モード
                    final bm = BookmarkModel(
                      id: _id(),
                      url: _url.text.trim(),
                      title: _title.text.trim(),
                      excerpt: _memo.text.trim(),
                      createdAt: DateTime.now(),
                      readAt: null,
                      isPinned: false,
                      isArchived: false,
                      tags: List.of(_selected),
                      folderId: _folderId,
                      thumbnailUrl: _thumbnailUrl, // サムネイルURLを保存
                    );
                    try {
                      await store.addBookmark(bm);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ブックマークを保存しました')));
                      // ブックマーク登録後、レビュー催促チェック
                      await _checkAndRequestReviewOnBookmarkMilestone();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('保存失敗: $e')),
                      );
                    }
                  }
                }
              ))
            ]),
          ),
        ),
      ),
    ),
    );
  }
}

// ===== Helpers =====
String _id() => UniqueKey().toString();

/// サムネイルがファビコンかどうかを判定
bool _isFavicon(String? thumbnailPath) {
  if (thumbnailPath == null || thumbnailPath.isEmpty) return false;
  return thumbnailPath.contains('thumb_favicon_');
}

/// サムネイル表示用のウィジェットを生成（ファビコンは拡大しない）
Widget _buildThumbnailWidget(String thumbnailUrl, {double? width, double? height, BoxFit? fit}) {
  final isFavicon = _isFavicon(thumbnailUrl);
  final effectiveFit = isFavicon ? BoxFit.scaleDown : (fit ?? BoxFit.cover);
  
  if (thumbnailUrl.startsWith('http')) {
    return Image.network(
      thumbnailUrl,
      width: width,
      height: height,
      fit: effectiveFit,
      errorBuilder: (context, error, stackTrace) => const Icon(Icons.link),
    );
  } else {
    return Image.file(
      File(thumbnailUrl),
      width: width,
      height: height,
      fit: effectiveFit,
      errorBuilder: (context, error, stackTrace) => const Icon(Icons.link),
    );
  }
}

// ===== Bookmark Folder Selector =====
class _BookmarkFolderSelector extends StatefulWidget {
  final String? selectedFolderId;
  final ValueChanged<String?> onFolderSelected;
  
  const _BookmarkFolderSelector({
    required this.selectedFolderId,
    required this.onFolderSelected,
  });

  @override
  State<_BookmarkFolderSelector> createState() => _BookmarkFolderSelectorState();
}

class _BookmarkFolderSelectorState extends State<_BookmarkFolderSelector> {
  bool _expanded = false;
  final List<FolderModel> _path = []; // 現在潜っている階層パス

  List<FolderModel> _getCurrentList(AppStore store) {
    return _path.isEmpty ? store.folders : _path.last.children;
  }

  String _getSelectedFolderName(AppStore store) {
    if (widget.selectedFolderId == null) return 'フォルダ未選択';
    
    FolderModel? findFolder(List<FolderModel> folders, String id) {
      for (final f in folders) {
        if (f.id == id) return f;
        final sub = findFolder(f.children, id);
        if (sub != null) return sub;
      }
      return null;
    }
    
    final folder = findFolder(store.folders, widget.selectedFolderId!);
    return folder?.name ?? 'フォルダ未選択';
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreProvider.of(context);
    final candidates = _getCurrentList(store);
    final depth = _path.length;
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 選択ボタン（展開/折りたたみ）
          ListTile(
            title: Text(_getSelectedFolderName(store)),
            leading: const Icon(Icons.folder_outlined),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          
          // 展開時のフォルダ一覧
          if (_expanded) ...[
            const Divider(height: 0),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // パンくず/戻る
                    if (depth > 0)
                      ListTile(
                        leading: const Icon(Icons.arrow_back),
                        title: Text(_path.map((f) => f.name).join(' / ')),
                        onTap: () => setState(() { if (_path.isNotEmpty) _path.removeLast(); }),
                      ),
                    
                    // トップ階層オプション
                    if (depth == 0)
                      ListTile(
                        title: Text(
                          'フォルダ未選択',
                          style: TextStyle(
                            fontWeight: widget.selectedFolderId == null ? FontWeight.bold : FontWeight.normal,
                            color: widget.selectedFolderId == null ? Theme.of(context).colorScheme.primary : null,
                          ),
                        ),
                        leading: Radio<String?>(
                          value: null,
                          groupValue: widget.selectedFolderId,
                          onChanged: (v) {
                            widget.onFolderSelected(v);
                            setState(() => _expanded = false);
                          },
                        ),
                        onTap: () {
                          widget.onFolderSelected(null);
                          setState(() => _expanded = false);
                        },
                      ),
                    
                    // フォルダ一覧
                    if (candidates.isEmpty && depth > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text('サブフォルダはありません', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ...candidates.map((f) {
                        final isSelected = widget.selectedFolderId == f.id;
                        final hasChildren = f.children.isNotEmpty;
                        return ListTile(
                          key: ValueKey('bm_sel_${f.id}'),
                          leading: Radio<String?>(
                            value: f.id,
                            groupValue: widget.selectedFolderId,
                            onChanged: (v) {
                              widget.onFolderSelected(v);
                              setState(() => _expanded = false);
                            },
                          ),
                          title: Text(
                            f.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Theme.of(context).colorScheme.primary : null,
                            ),
                          ),
                          trailing: hasChildren ? const Icon(Icons.chevron_right) : null,
                          onTap: () {
                            if (hasChildren) {
                              setState(() => _path.add(f));
                            } else {
                              widget.onFolderSelected(f.id);
                              setState(() => _expanded = false);
                            }
                          },
                          // 長押しで選択だけ（ナビゲーションせず）
                          onLongPress: () {
                            widget.onFolderSelected(f.id);
                            setState(() => _expanded = false);
                          },
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Removed unused _fmtDate

// removed unused _confirmDelete helper

void _mockPurchase(BuildContext context, {required String title}) {
  showDialog(
    context: context,
    builder: (c) => AlertDialog(
  title: Text(title),
      content: const Text('近日中に実装予定。今しばらくお待ちください'),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}

void _mockRestore(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('購入情報を復元しました')));
}


// ===== Tag Management Dialogs =====
void _showAddTagDialog(BuildContext context) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('新規タグ作成'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'タグ名', border: OutlineInputBorder()),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isEmpty) return;
            final store = StoreProvider.of(context);
            final exists = store.tags.any((t) => t.name.toLowerCase() == name.toLowerCase());
            if (exists) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同じ名前のタグが既に存在します')));
              return;
            }
            store.addTag(TagModel(id: _id(), name: name));
            Navigator.pop(c);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('タグ「$name」を作成しました')));
          },
          child: const Text('作成'),
        ),
      ],
    ),
  );
}

void _showEditTagDialog(BuildContext context, TagModel tag) {
  final controller = TextEditingController(text: tag.name);
  showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('タグ名編集'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'タグ名', border: OutlineInputBorder()),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isEmpty) return;
            final store = StoreProvider.of(context);
            final exists = store.tags.any((t) => t.id != tag.id && t.name.toLowerCase() == name.toLowerCase());
            if (exists) {
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同じ名前のタグが既に存在します')));
              return;
            }
            tag.name = name;
            store.updateTag(tag);
            Navigator.pop(c);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('タグ名を「$name」に変更しました')));
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

Future<bool> _confirmDeleteTag(BuildContext context, TagModel tag) async {
  final store = StoreProvider.of(context);
  final count = store.bookmarks.where((b) => b.tags.any((t) => t.id == tag.id)).length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('タグを削除しますか？'),
      content: Text(count > 0 
        ? 'このタグは$count個のブックマークで使用されています。削除すると、すべてのブックマークからこのタグが削除されます。' 
        : 'このタグを削除します。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除')),
      ],
    ),
  );
  if (ok == true) {
    await store.removeTag(tag);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('タグ「${tag.name}」を削除しました')));
    return true;
  }
  return false;
}

// ===== Folder Management Dialogs =====
void _showAddFolderDialog(BuildContext context, String? parentId) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(parentId == null ? '新規フォルダ作成' : 'サブフォルダ作成'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'フォルダ名', border: OutlineInputBorder()),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(c); // ダイアログを先に閉じる
            final store = StoreProvider.of(context);
            await store.addFolder(name, parentId: parentId);
            // HomeScreenの場合はfolderOrderを即座に更新
            final state = context.findAncestorStateOfType<_HomeScreenState>();
            state?.refreshFolders(store);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('フォルダ「$name」を作成しました')),
            );
          },
          child: const Text('作成'),
        ),
      ],
    ),
  );
}

void _showEditFolderDialog(BuildContext context, FolderModel folder) {
  final controller = TextEditingController(text: folder.name);
  final store = StoreProvider.of(context);
  
  // 全フォルダを再帰的に収集（重複除去）
  Set<String> seenIds = {};
  List<FolderModel> allFolders = [];
  
  void collectFolders(List<FolderModel> folders) {
    for (var f in folders) {
      if (!seenIds.contains(f.id)) {
        seenIds.add(f.id);
        allFolders.add(f);
        collectFolders(f.children);
      }
    }
  }
  
  collectFolders(store.folders);
  
  // 移動先候補から自分自身と自分の子孫を除外
  List<FolderModel> candidates = allFolders.where((f) {
    if (f.id == folder.id) return false; // 自分自身は除外
    return !_isDescendantOf(folder, f); // 自分の子孫も除外
  }).toList();
  
  // 候補IDのセットを作成
  Set<String> candidateIds = candidates.map((f) => f.id).toSet();
  
  // 現在のparentIdが候補に含まれていない場合はnullにリセット
  String? selectedParentId = folder.parentId;
  if (selectedParentId != null && !candidateIds.contains(selectedParentId)) {
    selectedParentId = null;
  }
  
  showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('フォルダ編集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'フォルダ名',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Container(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('親フォルダ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  AccordionFolderSelector(
                    folders: store.folders,
                    selectedId: selectedParentId,
                    excludeId: folder.id,
                    onSelect: (id) => setState(() => selectedParentId = id),
                  ),
                  const SizedBox(height: 4),
                  Text(selectedParentId == null ? 'トップ階層' : candidates.firstWhere((f) => f.id == selectedParentId, orElse: () => FolderModel(id: '', name: '不明')).name, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(c);
              _confirmDeleteFolder(context, folder);
            },
            child: const Text('削除'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              await store.updateFolder(folder.id, name, parentId: selectedParentId);
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('フォルダを更新しました')),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

void _confirmDeleteFolder(BuildContext context, FolderModel folder) async {
  final store = StoreProvider.of(context);
  final count = store.byFolder(folder.id).length;
  final hasChildren = folder.children.isNotEmpty;
  
  String message = 'このフォルダを削除しますか？';
  if (hasChildren) {
    message += '\n\n警告: サブフォルダも一緒に削除されます。';
  }
  if (count > 0) {
    message += '\n\nこのフォルダには$count個のブックマークがあります。';
  }
  
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('フォルダ削除'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('削除'),
        ),
      ],
    ),
  );

  if (ok == true) {
    await store.deleteFolder(folder.id);
    // HomeScreenの場合はfolderOrderを即座に更新
    final state = context.findAncestorStateOfType<_HomeScreenState>();
    state?.refreshFolders(store);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('フォルダ「${folder.name}」を削除しました')),
    );
  }
}

// candidateがfolderの子孫かどうかをチェック
bool _isDescendantOf(FolderModel folder, FolderModel candidate) {
  if (candidate.children.isEmpty) return false;
  for (final child in candidate.children) {
    if (child.id == folder.id || _isDescendantOf(folder, child)) {
      return true;
    }
  }
  return false;
}

// ===== AI Tag Analysis Result Sheet =====
class TagAnalysisResultSheet extends StatefulWidget {
  final TagStructureAnalysis analysis;
  
  const TagAnalysisResultSheet({
    super.key,
    required this.analysis,
  });

  @override
  State<TagAnalysisResultSheet> createState() => _TagAnalysisResultSheetState();
}

class _TagAnalysisResultSheetState extends State<TagAnalysisResultSheet> {
  final Set<String> _selectedNewTags = {};
  final Set<String> _selectedMergeTags = {};
  final Set<String> _selectedRemoveTags = {};

  @override
  void initState() {
    super.initState();
    // デフォルトで全て選択
    _selectedNewTags.addAll(
      widget.analysis.suggestedTags.where((t) => t.isNewTag).map((t) => t.name)
    );
    _selectedMergeTags.addAll(
      widget.analysis.suggestedTags.where((t) => t.isMergeTag).map((t) => t.name)
    );
    _selectedRemoveTags.addAll(widget.analysis.tagsToRemove);
  }

  Future<void> _applyChanges() async {
    final context = this.context;
    final store = StoreProvider.of(context);
    int changes = 0;

    try {
      // 1. 新しいタグを追加
      for (final tagName in _selectedNewTags) {
        await store.addTag(TagModel(id: '', name: tagName));
        changes++;
      }

      // 2. タグの統合（既存タグを削除して新しいタグを追加）
      for (final suggestedTag in widget.analysis.suggestedTags) {
        if (suggestedTag.isMergeTag && _selectedMergeTags.contains(suggestedTag.name)) {
          // 統合元のタグを削除
          for (final oldTagName in suggestedTag.mergeFrom) {
            final oldTag = store.tags.firstWhere((t) => t.name == oldTagName, orElse: () => TagModel(id: '', name: ''));
            if (oldTag.id.isNotEmpty) {
              await store.removeTag(oldTag);
              changes++;
            }
          }
          // 統合先のタグを追加（まだ存在しない場合）
          if (!store.tags.any((t) => t.name == suggestedTag.name)) {
            await store.addTag(TagModel(id: '', name: suggestedTag.name));
            changes++;
          }
        }
      }

      // 3. 不要なタグを削除
      for (final tagName in _selectedRemoveTags) {
        final tag = store.tags.firstWhere((t) => t.name == tagName, orElse: () => TagModel(id: '', name: ''));
        if (tag.id.isNotEmpty) {
          await store.removeTag(tag);
          changes++;
        }
      }

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$changes 件の変更を適用しました'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラー: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final newTags = widget.analysis.suggestedTags.where((t) => t.isNewTag).toList();
    // 統合元が2個以上あるタグのみを表示
    final mergeTags = widget.analysis.suggestedTags
        .where((t) => t.isMergeTag && t.mergeFrom.length >= 2)
        .toList();
    final removeTags = widget.analysis.tagsToRemove;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'AI タグ構成分析結果',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Overall Reasoning
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lightbulb_outline, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              '分析結果',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.analysis.overallReasoning,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),

                // New Tags
                if (newTags.isNotEmpty) ...[
                  _buildSectionHeader('新規タグの提案', Icons.add_circle_outline, Colors.green),
                  ...newTags.map((tag) => _buildTagCard(
                    tag: tag,
                    isSelected: _selectedNewTags.contains(tag.name),
                    onToggle: () {
                      setState(() {
                        if (_selectedNewTags.contains(tag.name)) {
                          _selectedNewTags.remove(tag.name);
                        } else {
                          _selectedNewTags.add(tag.name);
                        }
                      });
                    },
                    color: Colors.green,
                  )),
                  const SizedBox(height: 16),
                ],

                // Merge Tags
                if (mergeTags.isNotEmpty) ...[
                  _buildSectionHeader('タグ統合の提案', Icons.merge_type, Colors.orange),
                  ...mergeTags.map((tag) => _buildTagCard(
                    tag: tag,
                    isSelected: _selectedMergeTags.contains(tag.name),
                    onToggle: () {
                      setState(() {
                        if (_selectedMergeTags.contains(tag.name)) {
                          _selectedMergeTags.remove(tag.name);
                        } else {
                          _selectedMergeTags.add(tag.name);
                        }
                      });
                    },
                    color: Colors.orange,
                  )),
                  const SizedBox(height: 16),
                ],

                // Remove Tags
                if (removeTags.isNotEmpty) ...[
                  _buildSectionHeader('削除推奨タグ', Icons.delete_outline, Colors.red),
                  ...removeTags.map((tagName) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      value: _selectedRemoveTags.contains(tagName),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedRemoveTags.add(tagName);
                          } else {
                            _selectedRemoveTags.remove(tagName);
                          }
                        });
                      },
                      title: Text(
                        tagName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text('使用頻度が低いか、分類として役立っていません'),
                      secondary: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                  )),
                ],
              ],
            ),
          ),

          // Apply Button          // Apply Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_selectedNewTags.isEmpty && 
                             _selectedMergeTags.isEmpty && 
                             _selectedRemoveTags.isEmpty)
                      ? null
                      : _applyChanges,
                  icon: const Icon(Icons.check),
                  label: Text(
                    '選択した変更を適用 (${_selectedNewTags.length + _selectedMergeTags.length + _selectedRemoveTags.length}件)',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagCard({
    required SuggestedTag tag,
    required bool isSelected,
    required VoidCallback onToggle,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (_) => onToggle(),
        title: Text(
          tag.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tag.description),
            const SizedBox(height: 4),
            Text(
              tag.reasoning,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            if (tag.isMergeTag) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: tag.mergeFrom.map((oldTag) => Chip(
                  label: Text(oldTag, style: const TextStyle(fontSize: 10)),
                  backgroundColor: Colors.grey.shade200,
                  visualDensity: VisualDensity.compact,
                )).toList(),
              ),
            ],
          ],
        ),
        secondary: Icon(
          tag.isNewTag ? Icons.add_circle : Icons.merge_type,
          color: color,
        ),
      ),
    );
  }
}

// ===== Folder Analysis Result Sheet =====
class FolderAnalysisResultSheet extends StatefulWidget {
  final FolderStructureAnalysis analysis;
  
  const FolderAnalysisResultSheet({
    super.key,
    required this.analysis,
  });

  @override
  State<FolderAnalysisResultSheet> createState() => _FolderAnalysisResultSheetState();
}

class _FolderAnalysisResultSheetState extends State<FolderAnalysisResultSheet> {
  final Set<String> _selectedNewFolders = {};
  final Set<String> _selectedMergeFolders = {};
  final Set<String> _selectedRemoveFolders = {};

  @override
  void initState() {
    super.initState();
    // デフォルトで全て選択
    // 新規フォルダ（merge_fromが空のもの）
    _selectedNewFolders.addAll(
      widget.analysis.suggestedFolders
        .where((f) => f.mergeFrom.isEmpty)
        .map((f) => f.name)
    );
    // 統合フォルダ（merge_fromが2個以上あるもの）
    _selectedMergeFolders.addAll(
      widget.analysis.suggestedFolders
        .where((f) => f.mergeFrom.length >= 2)
        .map((f) => f.name)
    );
    _selectedRemoveFolders.addAll(widget.analysis.foldersToRemove);
  }

  Future<void> _applyChanges() async {
    final context = this.context;
    final store = StoreProvider.of(context);
    int changes = 0;

    try {
      // 作成済みフォルダ名とIDのマップ
      final Map<String, String> createdFolderIds = {};
      
      // 選択されたすべてのフォルダ名（新規 + 統合）
      final allSelectedNames = {..._selectedNewFolders, ..._selectedMergeFolders};
      
      // 1. 親フォルダから順番に作成（階層を考慮）
      // まず親を持たないフォルダ（トップレベル）を作成
      for (final selectedName in allSelectedNames) {
        final suggested = widget.analysis.suggestedFolders.firstWhere((f) => f.name == selectedName);
        
        if (suggested.parent == null || suggested.parent!.isEmpty) {
          // 統合元フォルダがある場合は削除
          for (final oldFolderName in suggested.mergeFrom) {
            final oldFolder = store.folders.firstWhere(
              (f) => f.name == oldFolderName, 
              orElse: () => FolderModel(id: '', name: '', sortOrder: 0)
            );
            if (oldFolder.id.isNotEmpty) {
              await store.deleteFolder(oldFolder.id);
              changes++;
            }
          }
          
          // 新しいフォルダを追加（まだ存在しない場合）
          if (!store.folders.any((f) => f.name == suggested.name)) {
            await store.addFolder(suggested.name);
            changes++;
            // 作成したフォルダのIDを記録（後で参照できるように再取得）
            await store.fetchFolders();
            final created = store.folders.firstWhere((f) => f.name == suggested.name);
            createdFolderIds[suggested.name] = created.id;
          } else {
            // 既存フォルダのIDを記録
            final existing = store.folders.firstWhere((f) => f.name == suggested.name);
            createdFolderIds[suggested.name] = existing.id;
          }
        }
      }
      
      // 次に子フォルダを作成（親フォルダが存在する場合のみ）
      for (final selectedName in allSelectedNames) {
        final suggested = widget.analysis.suggestedFolders.firstWhere((f) => f.name == selectedName);
        
        if (suggested.parent != null && suggested.parent!.isNotEmpty) {
          // 親フォルダのIDを取得
          String? parentId;
          if (createdFolderIds.containsKey(suggested.parent)) {
            parentId = createdFolderIds[suggested.parent];
          } else {
            final parentFolder = store.folders.firstWhere(
              (f) => f.name == suggested.parent,
              orElse: () => FolderModel(id: '', name: '', sortOrder: 0)
            );
            if (parentFolder.id.isNotEmpty) {
              parentId = parentFolder.id;
            }
          }
          
          // 統合元フォルダがある場合は削除
          for (final oldFolderName in suggested.mergeFrom) {
            final oldFolder = store.folders.firstWhere(
              (f) => f.name == oldFolderName, 
              orElse: () => FolderModel(id: '', name: '', sortOrder: 0)
            );
            if (oldFolder.id.isNotEmpty) {
              await store.deleteFolder(oldFolder.id);
              changes++;
            }
          }
          
          // 新しいフォルダを追加（まだ存在しない場合）
          if (!store.folders.any((f) => f.name == suggested.name)) {
            await store.addFolder(suggested.name, parentId: parentId);
            changes++;
          }
        }
      }

      // 2. 不要なフォルダを削除
      for (final folderName in _selectedRemoveFolders) {
        final folder = store.folders.firstWhere(
          (f) => f.name == folderName, 
          orElse: () => FolderModel(id: '', name: '', sortOrder: 0)
        );
        if (folder.id.isNotEmpty) {
          await store.deleteFolder(folder.id);
          changes++;
        }
      }

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$changes 件の変更を適用しました'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラー: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 新規フォルダ（merge_fromが空）
    final newFolders = widget.analysis.suggestedFolders
        .where((f) => f.mergeFrom.isEmpty)
        .toList();
    // 統合フォルダ（merge_fromが2個以上）
    final mergeFolders = widget.analysis.suggestedFolders
        .where((f) => f.mergeFrom.length >= 2)
        .toList();
    final removeFolders = widget.analysis.foldersToRemove;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_special, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'AI フォルダ構成分析結果',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Overall Reasoning
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lightbulb_outline, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              '分析結果',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.analysis.overallReasoning,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),

                // New Folders
                if (newFolders.isNotEmpty) ...[
                  _buildSectionHeader('新規フォルダの提案', Icons.add_circle_outline, Colors.green),
                  ...newFolders.map((folder) => _buildFolderCard(
                    folder: folder,
                    isSelected: _selectedNewFolders.contains(folder.name),
                    onToggle: () {
                      setState(() {
                        if (_selectedNewFolders.contains(folder.name)) {
                          _selectedNewFolders.remove(folder.name);
                        } else {
                          _selectedNewFolders.add(folder.name);
                        }
                      });
                    },
                    color: Colors.green,
                  )),
                  const SizedBox(height: 16),
                ],

                // Merge Folders
                if (mergeFolders.isNotEmpty) ...[
                  _buildSectionHeader('フォルダ統合の提案', Icons.merge_type, Colors.orange),
                  ...mergeFolders.map((folder) => _buildFolderCard(
                    folder: folder,
                    isSelected: _selectedMergeFolders.contains(folder.name),
                    onToggle: () {
                      setState(() {
                        if (_selectedMergeFolders.contains(folder.name)) {
                          _selectedMergeFolders.remove(folder.name);
                        } else {
                          _selectedMergeFolders.add(folder.name);
                        }
                      });
                    },
                    color: Colors.orange,
                  )),
                  const SizedBox(height: 16),
                ],

                // Remove Folders
                if (removeFolders.isNotEmpty) ...[
                  _buildSectionHeader('削除推奨フォルダ', Icons.delete_outline, Colors.red),
                  ...removeFolders.map((folderName) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      value: _selectedRemoveFolders.contains(folderName),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedRemoveFolders.add(folderName);
                          } else {
                            _selectedRemoveFolders.remove(folderName);
                          }
                        });
                      },
                      title: Text(
                        folderName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text('使用頻度が低いか、分類として役立っていません'),
                      secondary: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                  )),
                ],
              ],
            ),
          ),

          // Apply Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_selectedNewFolders.isEmpty && 
                             _selectedMergeFolders.isEmpty && 
                             _selectedRemoveFolders.isEmpty)
                      ? null
                      : _applyChanges,
                  icon: const Icon(Icons.check),
                  label: Text(
                    '選択した変更を適用 (${_selectedNewFolders.length + _selectedMergeFolders.length + _selectedRemoveFolders.length}件)',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // フォルダの階層レベルを計算するヘルパーメソッド
  int _calculateFolderDepth(SuggestedFolder folder, List<SuggestedFolder> allFolders) {
    if (folder.parent == null || folder.parent!.isEmpty) {
      return 1; // トップレベル
    }
    
    // 親フォルダを探して再帰的に計算
    final parentFolder = allFolders.firstWhere(
      (f) => f.name == folder.parent,
      orElse: () => SuggestedFolder(name: '', description: '', reasoning: '', mergeFrom: []),
    );
    
    if (parentFolder.name.isEmpty) {
      return 2; // 親が見つからない場合は2層として扱う
    }
    
    return 1 + _calculateFolderDepth(parentFolder, allFolders);
  }
  
  // 階層に応じた色を取得
  Color _getDepthColor(int depth) {
    switch (depth) {
      case 1:
        return Colors.blue.shade100;
      case 2:
        return Colors.orange.shade100;
      case 3:
        return Colors.purple.shade100;
      case 4:
        return Colors.green.shade100;
      default:
        return Colors.grey.shade200;
    }
  }
  
  // 階層に応じたテキスト色を取得
  Color _getDepthTextColor(int depth) {
    switch (depth) {
      case 1:
        return Colors.blue.shade800;
      case 2:
        return Colors.orange.shade800;
      case 3:
        return Colors.purple.shade800;
      case 4:
        return Colors.green.shade800;
      default:
        return Colors.grey.shade800;
    }
  }

  Widget _buildFolderCard({
    required SuggestedFolder folder,
    required bool isSelected,
    required VoidCallback onToggle,
    required Color color,
  }) {
    // 階層レベルを計算
    final depth = _calculateFolderDepth(folder, widget.analysis.suggestedFolders);
    final hasParent = folder.parent != null && folder.parent!.isNotEmpty;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (_) => onToggle(),
        title: Row(
          children: [
            // 階層インジケーター
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getDepthColor(depth),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '第${depth}層',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _getDepthTextColor(depth),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 階層インデント（深さに応じて増やす）
            if (hasParent) ...[
              for (int i = 1; i < depth; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.grey.shade400),
                ),
              Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                folder.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasParent) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '親: ${folder.parent}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text(folder.description),
            const SizedBox(height: 4),
            Text(
              folder.reasoning,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            if (folder.mergeFrom.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: folder.mergeFrom.map((oldFolder) => Chip(
                  label: Text(oldFolder, style: const TextStyle(fontSize: 10)),
                  backgroundColor: Colors.grey.shade200,
                  visualDensity: VisualDensity.compact,
                )).toList(),
              ),
            ],
          ],
        ),
        secondary: Icon(
          folder.mergeFrom.isEmpty ? Icons.create_new_folder : Icons.merge_type,
          color: color,
        ),
      ),
    );
  }
}

// ===== Bulk Tag Assignment Result Sheet =====
class BulkTagAssignmentResultSheet extends StatefulWidget {
  final List<dynamic> suggestions;
  final int totalProcessed;
  final String overallReasoning;
  
  const BulkTagAssignmentResultSheet({
    super.key,
    required this.suggestions,
    required this.totalProcessed,
    required this.overallReasoning,
  });

  @override
  State<BulkTagAssignmentResultSheet> createState() => _BulkTagAssignmentResultSheetState();
}

class _BulkTagAssignmentResultSheetState extends State<BulkTagAssignmentResultSheet> {
  final Map<String, List<String>> _selectedTags = {};

  @override
  void initState() {
    super.initState();
    // デフォルトで全て選択
    for (var suggestion in widget.suggestions) {
      final bookmarkId = suggestion['bookmark_id'] as String;
      final suggestedTags = (suggestion['suggested_tags'] as List).cast<String>();
      _selectedTags[bookmarkId] = List.from(suggestedTags);
    }
  }

  Future<void> _applyChanges() async {
    final context = this.context;
    final store = StoreProvider.of(context);
    int changes = 0;

    try {
      for (var entry in _selectedTags.entries) {
        final bookmarkId = entry.key;
        final tagsToAdd = entry.value;
        
        if (tagsToAdd.isEmpty) continue;

        // ブックマークを取得
        final bookmark = store.bookmarks.firstWhere(
          (b) => b.id == bookmarkId,
          orElse: () => BookmarkModel(
            id: '', 
            title: '', 
            url: '', 
            tags: [], 
            folderId: '',
            excerpt: '',
            createdAt: DateTime.now(),
          ),
        );
        
        if (bookmark.id.isEmpty) continue;

        // タグを追加
        final newTags = List<TagModel>.from(bookmark.tags);
        for (final tagName in tagsToAdd) {
          final tag = store.tags.firstWhere(
            (t) => t.name == tagName,
            orElse: () => TagModel(id: '', name: ''),
          );
          
          if (tag.id.isNotEmpty && !newTags.any((t) => t.id == tag.id)) {
            newTags.add(tag);
            changes++;
          }
        }
        
        // ブックマークを更新
        if (newTags.length > bookmark.tags.length) {
          final updatedBookmark = BookmarkModel(
            id: bookmark.id,
            title: bookmark.title,
            url: bookmark.url,
            tags: newTags,
            folderId: bookmark.folderId,
            excerpt: bookmark.excerpt,
            createdAt: bookmark.createdAt,
            thumbnailUrl: bookmark.thumbnailUrl,
          );
          await store.updateBookmark(updatedBookmark);
        }
      }

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$changes 件のタグを追加しました'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラー: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreProvider.of(context);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.label, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'AI 一括タグ割り当て結果',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Overall Reasoning
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lightbulb_outline, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              '分析結果',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.overallReasoning,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),

                // Suggestions
                ...widget.suggestions.map((suggestion) {
                  final bookmarkId = suggestion['bookmark_id'] as String;
                  final suggestedTags = (suggestion['suggested_tags'] as List).cast<String>();
                  
                  if (suggestedTags.isEmpty) return const SizedBox.shrink();

                  final bookmark = store.bookmarks.firstWhere(
                    (b) => b.id == bookmarkId,
                    orElse: () => BookmarkModel(
                      id: '', 
                      title: '', 
                      url: '', 
                      tags: [], 
                      folderId: '',
                      excerpt: '',
                      createdAt: DateTime.now(),
                    ),
                  );

                  if (bookmark.id.isEmpty) return const SizedBox.shrink();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bookmark.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: suggestedTags.map((tagName) {
                              final isSelected = _selectedTags[bookmarkId]?.contains(tagName) ?? false;
                              return FilterChip(
                                label: Text(tagName),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedTags[bookmarkId] = [...?_selectedTags[bookmarkId], tagName];
                                    } else {
                                      _selectedTags[bookmarkId]?.remove(tagName);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),

          // Apply Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _applyChanges,
                  icon: const Icon(Icons.check),
                  label: const Text('選択したタグを適用'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}



