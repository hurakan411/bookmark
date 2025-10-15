class FolderModel {
  final String id;
  String name;
  String? parentId;
  int sortOrder;
  
  // UI用（取得時に計算）
  int level = 0;
  List<FolderModel> children = [];

  FolderModel({
    required this.id,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
  });

  factory FolderModel.fromJson(Map<String, dynamic> json) {
    return FolderModel(
      id: json['id'],
      name: json['name'],
      parentId: json['parent_id'],
      sortOrder: json['sort_order'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'parent_id': parentId,
      'sort_order': sortOrder,
    };
  }

  /// ルートフォルダかどうか
  bool get isRoot => parentId == null;

  /// パスを取得（階層を辿って表示用）
  String getPath(List<FolderModel> allFolders) {
    if (isRoot) return name;
    
    final parent = allFolders.where((f) => f.id == parentId).firstOrNull;
    if (parent == null) return name;
    
    return '${parent.getPath(allFolders)} / $name';
  }
}
