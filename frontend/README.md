# Flutter Bookmark Manager - Supabase版

Supabase PostgreSQLと連携したブックマーク管理アプリです。

## 📁 プロジェクト構造

```
lib/
├── main.dart                    # メインアプリ・UI
├── models/                      # データモデル
│   ├── bookmark_model.dart
│   ├── content_type.dart
│   ├── folder_model.dart
│   └── tag_model.dart
└── repositories/                # DB操作（Supabase連携）
    ├── bookmark_repository.dart
    ├── folder_repository.dart
    └── tag_repository.dart
```

## 🚀 セットアップ手順

### 1. Supabaseプロジェクトを作成

1. [Supabase](https://supabase.com) にアクセス
2. 新規プロジェクトを作成
3. 「Settings」→「API」から以下をコピー：
   - Project URL
   - anon public key

### 2. データベースマイグレーション

Supabaseダッシュボードの「SQL Editor」で以下のSQLを実行：

```sql
-- tags テーブル
CREATE TABLE tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- folders テーブル
CREATE TABLE folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- bookmarks テーブル
CREATE TABLE bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  excerpt TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  is_pinned BOOLEAN DEFAULT FALSE,
  is_archived BOOLEAN DEFAULT FALSE,
  estimated_minutes INTEGER NOT NULL,
  content_type TEXT NOT NULL,
  due_at TIMESTAMPTZ,
  folder_id UUID REFERENCES folders(id) ON DELETE SET NULL,
  open_count INTEGER DEFAULT 0,
  last_opened_at TIMESTAMPTZ
);

-- bookmark_tags 中間テーブル
CREATE TABLE bookmark_tags (
  bookmark_id UUID REFERENCES bookmarks(id) ON DELETE CASCADE,
  tag_id UUID REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (bookmark_id, tag_id)
);

-- インデックス
CREATE INDEX idx_bookmarks_folder ON bookmarks(folder_id);
CREATE INDEX idx_bookmarks_due_at ON bookmarks(due_at);
CREATE INDEX idx_bookmark_tags_bookmark ON bookmark_tags(bookmark_id);
CREATE INDEX idx_bookmark_tags_tag ON bookmark_tags(tag_id);
```

### 3. 環境変数を設定

プロジェクトルートに `.env` ファイルを作成：

```bash
SUPABASE_URL=あなたのProjectURL
SUPABASE_ANON_KEY=あなたのanonpublickey
```

### 4. 依存パッケージをインストール

```bash
flutter pub get
```

### 5. アプリを起動

```bash
flutter run
```

## 🏗️ アーキテクチャ

### リポジトリパターン

DB操作は全て`repositories/`配下に分離されています：

- **TagRepository**: タグのCRUD操作
- **FolderRepository**: フォルダのCRUD操作
- **BookmarkRepository**: ブックマークのCRUD操作（タグ関連付け含む）

### AppStore (ChangeNotifier)

- リポジトリを通じてDB操作を実行
- UIの状態管理
- データのキャッシュ

## ✨ 主な機能

- ✅ ブックマークの追加・編集・削除
- ✅ タグによる分類
- ✅ フォルダによる整理
- ✅ 検索機能
- ✅ クイックフィルタ（短時間、今週期限、未読）
- ✅ よく使うブックマーク表示
- ✅ ピン留め機能
- ✅ 既読/未読管理

## 📦 使用技術

- Flutter 3.x
- Supabase (PostgreSQL)
- flutter_dotenv (環境変数管理)

## 📝 ライセンス

MIT
