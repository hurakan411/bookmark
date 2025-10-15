import 'package:flutter/material.dart';
import 'models/folder_model.dart';


class AccordionFolderSelector extends StatefulWidget {
  final List<FolderModel> folders; // ルートフォルダ群
  final String? selectedId;        // 現在選択中の親フォルダID（null=トップ）
  final String? excludeId;         // 自分自身のID（親にできない）
  final ValueChanged<String?> onSelect;

  const AccordionFolderSelector({
    required this.folders,
    required this.selectedId,
    required this.excludeId,
    required this.onSelect,
    Key? key,
  }) : super(key: key);

  @override
  State<AccordionFolderSelector> createState() => _DrillDownFolderSelectorState();
}

// Drill-down型: 一度に一階層だけ表示し、フォルダタップでその直下へ潜る
class _DrillDownFolderSelectorState extends State<AccordionFolderSelector> {
  final List<FolderModel> _path = []; // 現在潜っている階層パス

  List<FolderModel> get _currentList => _path.isEmpty ? widget.folders : _path.last.children;

  @override
  void initState() {
    super.initState();
    // 初期選択されているフォルダがあれば、その階層まで自動で潜る
    if (widget.selectedId != null) {
      final path = _findPathToId(widget.folders, widget.selectedId!);
      if (path.isNotEmpty) {
        // 選択対象自身は親候補として表示するので、最後（=選択フォルダ）以外を潜る
        _path.addAll(path.take(path.length - 1));
      }
    }
  }

  @override
  void didUpdateWidget(covariant AccordionFolderSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // フォルダ構造の更新でパスに存在しないノードがあれば巻き戻す
    _shrinkPathIfInvalid();
  }

  List<FolderModel> _findPathToId(List<FolderModel> roots, String id) {
    for (final f in roots) {
      if (f.id == id) return [f];
      final sub = _findPathToId(f.children, id);
      if (sub.isNotEmpty) return [f, ...sub];
    }
    return [];
  }

  void _shrinkPathIfInvalid() {
    bool validPath = true;
    List<FolderModel> level = widget.folders;
    for (int i = 0; i < _path.length; i++) {
      final match = level.where((f) => f.id == _path[i].id).toList();
      if (match.isEmpty) {
        validPath = false;
        _path.removeRange(i, _path.length);
        break;
      } else {
        level = match.first.children;
      }
    }
    if (!validPath) setState(() {});
  }

  bool _isExcluded(FolderModel f) => f.id == widget.excludeId;

  @override
  Widget build(BuildContext context) {
    final candidates = _currentList.where((f) => !_isExcluded(f)).toList();
    final depth = _path.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // パンくず/戻る
        if (depth > 0)
          ListTile(
            leading: const Icon(Icons.arrow_back),
            title: Text(_path.map((f) => f.name).join(' / ')),
            onTap: () => setState(() { if (_path.isNotEmpty) _path.removeLast(); }),
          ),
        if (depth == 0)
          ListTile(
            title: Text('トップ階層', style: TextStyle(
              fontWeight: widget.selectedId == null ? FontWeight.bold : FontWeight.normal,
              color: widget.selectedId == null ? Theme.of(context).colorScheme.primary : null,
            )),
            leading: Radio<String?>(value: null, groupValue: widget.selectedId, onChanged: widget.onSelect),
            onTap: () => widget.onSelect(null),
          ),
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('サブフォルダはありません', style: TextStyle(color: Colors.grey)),
          )
        else
          ...candidates.map((f) {
            final isSelected = widget.selectedId == f.id;
            final hasChildren = f.children.any((c) => !_isExcluded(c));
            return ListTile(
              key: ValueKey('sel_${f.id}'),
              leading: Radio<String?>(value: f.id, groupValue: widget.selectedId, onChanged: widget.onSelect),
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
                  widget.onSelect(f.id);
                }
              },
              // 長押しで選択だけ（ナビゲーションせず）も可
              onLongPress: () => widget.onSelect(f.id),
            );
          }),
      ],
    );
  }
}