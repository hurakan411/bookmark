# AI フォルダ自動割り当て機能

## 概要
ブックマークを適切なフォルダへ自動で割り当てる新しいAIツール機能を実装しました。

## 機能説明

### バックエンド (Python/FastAPI)

#### 新しいエンドポイント
- **POST `/bulk-assign-folders`**
  - 全ブックマークに対してAIが適切なフォルダを一括で提案
  - OpenAI gpt-5-miniモデルを使用
  - 各ブックマークの内容を分析し、最適なフォルダを選択

#### リクエスト形式
```json
{
  "bookmarks": [
    {
      "id": "bookmark_id",
      "title": "タイトル",
      "url": "URL",
      "excerpt": "メモ",
      "current_folder": "現在のフォルダ名"
    }
  ],
  "available_folders": ["フォルダ1", "フォルダ2", ...]
}
```

#### レスポンス形式
```json
{
  "suggestions": [
    {
      "bookmark_id": "bookmark_id",
      "suggested_folder": "提案するフォルダ名",
      "reasoning": "選択理由"
    }
  ],
  "total_processed": 件数,
  "overall_reasoning": "全体的な説明"
}
```

### フロントエンド (Flutter/Dart)

#### 新しいUI
- **BulkFolderAssignmentSheet** (`lib/bulk_folder_assignment_sheet.dart`)
  - モーダルボトムシートで表示
  - AIの提案結果をリスト表示
  - 各ブックマークの現在のフォルダ → 提案フォルダを視覚的に表示
  - チェックボックスで適用するブックマークを選択可能
  - 一括選択/解除機能

#### 統合箇所
- **AIツール画面** (`SmartFolderScreen`)
  - 「AI 一括フォルダ割り当て」カードを追加
  - タグ一括割り当てとフォルダ構成分析の間に配置

## 使い方

1. **AIツール画面**を開く
2. **「AI 一括フォルダ割り当て」**をタップ
3. AIが自動で分析（数秒かかります）
4. 提案結果が表示されます
   - 🟡 黄色背景：現在のフォルダと異なる提案
   - 緑色ラベル：AIが提案する新しいフォルダ
5. 適用したいブックマークにチェック
6. **「選択した○件を適用」**ボタンをタップ

## 特徴

### AI分析の特徴
- ブックマークのタイトル、URL、メモを総合的に分析
- 既存のフォルダリストから最適なものを選択
- フォルダとタグの違いを理解した上で判断
- 各提案に理由を付与（20字以内）

### UI/UXの特徴
- 変更がある項目を視覚的に強調表示
- 現在のフォルダ → 提案フォルダの流れが分かりやすい
- 一括選択/解除で効率的な操作
- 適用前に内容を確認・編集可能

## 技術スタック

- **バックエンド**: FastAPI, OpenAI API (gpt-5-mini)
- **フロントエンド**: Flutter, Material Design 3
- **通信**: HTTP (localhost:8000)

## ファイル構成

### 新規作成
- `backend/main.py` - `/bulk-assign-folders` エンドポイント追加
- `frontend/lib/bulk_folder_assignment_sheet.dart` - 新規UIコンポーネント

### 変更
- `frontend/lib/main.dart`
  - `BulkFolderAssignmentSheet` のimport追加
  - `_SmartFolderScreenState` に `_isBulkAssigningFolders` 状態追加
  - `_bulkAssignFolders()` メソッド追加
  - AIツール画面に新しいカード追加

## 今後の拡張可能性

- [ ] 複数フォルダの候補を表示
- [ ] AIの提案精度の向上（学習データ追加）
- [ ] バッチ処理の最適化（100件以上の対応）
- [ ] フォルダ自動作成の提案
- [ ] 履歴機能（過去の割り当て結果を記録）

## 関連機能

この機能は以下の既存AI機能と連携します：

1. **AI タグ構成分析** - タグの整理・統合
2. **AI 一括タグ割り当て** - タグの自動割り当て
3. **AI フォルダ構成分析** - フォルダの整理・統合
4. **AI 一括フォルダ割り当て** - フォルダの自動割り当て（新機能）

これらを組み合わせることで、ブックマークの完全自動整理が可能になります。
