import 'package:flutter/material.dart';

class BulkFolderAssignmentResultSheet extends StatefulWidget {
  final List<Map<String, dynamic>> suggestions;
  final Function(Map<String, String>) onApply;

  const BulkFolderAssignmentResultSheet({
    Key? key,
    required this.suggestions,
    required this.onApply,
  }) : super(key: key);

  @override
  State<BulkFolderAssignmentResultSheet> createState() =>
      _BulkFolderAssignmentResultSheetState();
}

class _BulkFolderAssignmentResultSheetState
    extends State<BulkFolderAssignmentResultSheet> {
  Map<String, String> _selectedFolders = {};

  @override
  void initState() {
    super.initState();
    // デフォルトで全て選択
    _selectedFolders = {
      for (var suggestion in widget.suggestions)
        suggestion['bookmark_id'] as String:
            suggestion['suggested_folder'] as String
    };
  }

  void _applyAssignments() {
    if (_selectedFolders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('適用するブックマークがありません')),
      );
      return;
    }

    widget.onApply(_selectedFolders);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
                const Icon(Icons.folder, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'AI 一括フォルダ割り当て結果',
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

          // 結果表示
          if (widget.suggestions.isNotEmpty)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Overall Info
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
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.suggestions.length}件のブックマークに変更を提案',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '適用予定: ${_selectedFolders.length}件',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Suggestions
                  ...(widget.suggestions.map((suggestion) {
                    final bookmarkId = suggestion['bookmark_id'] as String;
                    final suggestedFolder =
                        suggestion['suggested_folder'] as String;
                    final reasoning = suggestion['reasoning'] as String;
                    final bookmarkTitle = suggestion['bookmark_title'] as String? ?? 'No title';
                    final currentFolder = suggestion['current_folder'] as String? ?? '未分類';

                    final isDifferent = currentFolder != suggestedFolder;
                    final isSelected = _selectedFolders.containsKey(bookmarkId);

                    return Card(
                      elevation: isDifferent ? 2 : 1,
                      color: isDifferent ? Colors.yellow[50] : null,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title with Checkbox
                            Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedFolders[bookmarkId] =
                                            suggestedFolder;
                                      } else {
                                        _selectedFolders.remove(bookmarkId);
                                      }
                                    });
                                  },
                                ),
                                Expanded(
                                  child: Text(
                                    bookmarkTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // Current → Suggested
                            Row(
                              children: [
                                const SizedBox(width: 48),
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      // Current Folder
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          currentFolder,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),

                                      // Arrow
                                      const Icon(
                                        Icons.arrow_forward,
                                        size: 16,
                                        color: Colors.blue,
                                      ),

                                      // Suggested Folder
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[100],
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.blue[300]!,
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          suggestedFolder,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // Reasoning
                            if (reasoning.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.only(left: 48),
                                child: Text(
                                  reasoning,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList()),
                ],
              ),
            ),

          // エラーまたは結果なし
          if (widget.suggestions.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: Colors.green[300],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '全てのブックマークが適切なフォルダに\n割り当てられています',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '変更が必要なブックマークはありません',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Apply Button
          if (widget.suggestions.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: ElevatedButton.icon(
                  onPressed: _applyAssignments,
                  icon: const Icon(Icons.check),
                  label: Text(
                    '${_selectedFolders.length}件のフォルダを適用',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
