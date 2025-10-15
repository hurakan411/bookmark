import 'tag_model.dart';

class BookmarkModel {
  final String id;
  String url;
  String title;
  String excerpt;
  DateTime createdAt;
  DateTime? readAt;
  bool isPinned;
  bool isArchived;
  List<TagModel> tags;
  String? folderId;
  int openCount;
  DateTime? lastOpenedAt;
  String? thumbnailUrl;

  int sortOrder;

  BookmarkModel({
    required this.id,
    required this.url,
    required this.title,
    required this.excerpt,
    required this.createdAt,
    this.readAt,
    this.isPinned = false,
    this.isArchived = false,
    required this.tags,
    this.folderId,
    this.openCount = 0,
    this.lastOpenedAt,
    this.thumbnailUrl,
    this.sortOrder = 0,
  });

  bool get isRead => readAt != null;

  factory BookmarkModel.fromJson(Map<String, dynamic> json, List<TagModel> tags) {
    return BookmarkModel(
      id: json['id'],
      url: json['url'],
      title: json['title'],
      excerpt: json['excerpt'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      isPinned: (json['is_pinned'] is int) ? json['is_pinned'] == 1 : (json['is_pinned'] ?? false),
      isArchived: (json['is_archived'] is int) ? json['is_archived'] == 1 : (json['is_archived'] ?? false),
      tags: tags,
      folderId: json['folder_id'],
      openCount: json['open_count'] ?? 0,
      lastOpenedAt: json['last_opened_at'] != null
          ? DateTime.parse(json['last_opened_at'])
          : null,
      thumbnailUrl: json['thumbnail_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'title': title,
      'excerpt': excerpt,
      'read_at': readAt?.toIso8601String(),
      'is_pinned': isPinned,
      'is_archived': isArchived,
      'folder_id': folderId,
      'open_count': openCount,
      'last_opened_at': lastOpenedAt?.toIso8601String(),
      'thumbnail_url': thumbnailUrl,
    };
  }
}
