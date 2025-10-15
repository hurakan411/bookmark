# Bookmark Manager with AI Tag Suggestion

Flutter製のブックマーク管理アプリ + OpenAI API を使用したタグ自動提案機能

## 📁 プロジェクト構成

```
bookmark/
├── backend/              # FastAPI バックエンド（Python）
│   ├── main.py          # FastAPIアプリケーション
│   ├── requirements.txt # Python依存関係
│   ├── start.sh        # 起動スクリプト
│   ├── test_api.py     # テストスクリプト
│   ├── .env.example    # 環境変数テンプレート
│   └── README.md       # バックエンドのドキュメント
│
├── frontend/            # Flutter フロントエンド
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/
│   │   ├── repositories/
│   │   └── services/
│   │       ├── thumbnail_service.dart
│   │       └── tag_suggestion_service.dart  # タグ提案サービス
│   ├── pubspec.yaml
│   └── ...
│
└── USAGE_TAG_SUGGESTION.md  # 使用方法ドキュメント
```

## 🚀 クイックスタート

### 1. バックエンドのセットアップと起動

```bash
cd backend

# 仮想環境の作成
python3 -m venv venv
source venv/bin/activate

# 依存関係のインストール
pip install -r requirements.txt

# 環境変数の設定
cp .env.example .env
# .envファイルを編集してOpenAI API キーを設定

# サーバー起動
./start.sh
# または
python main.py
```

サーバーは http://localhost:8000 で起動します。

### 2. フロントエンドの起動

別のターミナルで：

```bash
cd frontend
flutter run
```

## ✨ 主な機能

### 基本機能
- 📚 ブックマークの追加・編集・削除
- 🏷️ タグ管理
- 📁 フォルダ階層管理
- 🔍 検索・フィルタリング
- 📌 ピン留め機能
- 🖼️ サムネイル表示

### AI機能（新機能）
- 🤖 **AI タグ自動提案**
  - OpenAI GPT-4o-mini を使用
  - ブックマークのタイトル、URL、メモから適切なタグを自動選択
  - 既存のタグリストの中から最適なものを提案

## 🎯 使い方

詳細な使用方法は [USAGE_TAG_SUGGESTION.md](./USAGE_TAG_SUGGESTION.md) を参照してください。

### 基本的な流れ

1. **バックエンドを起動**
2. **Flutterアプリを起動**
3. **ブックマーク追加画面でタイトルとURLを入力**
4. **「AI自動提案」ボタンをタップ**
5. **提案されたタグを確認・保存**

## 🔧 技術スタック

### バックエンド
- **FastAPI** - 高速なPython Webフレームワーク
- **OpenAI API** - GPT-4o-miniモデルを使用
- **Pydantic** - データバリデーション
- **Uvicorn** - ASGIサーバー

### フロントエンド
- **Flutter** - クロスプラットフォームUIフレームワーク
- **SQLite** - ローカルデータベース
- **http** - HTTP通信

## 💰 コスト

OpenAI API (gpt-4o-mini) 使用:
- 1リクエストあたり: 約0.001〜0.003円
- 月100回使用: 約0.1〜0.3円

非常に低コストで運用可能です。

## 🧪 テスト

バックエンドAPIのテスト:

```bash
cd backend
python test_api.py
```

## 📝 API ドキュメント

バックエンド起動後、以下のURLでアクセス可能:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## 🔐 セキュリティ

- `.env` ファイルは **絶対にGitにコミットしない**
- OpenAI API キーは安全に管理
- 本番環境ではCORS設定を適切に制限
- 機密情報を含むブックマークには使用を控える

## 📄 ライセンス

Private project

## 🤝 貢献

プライベートプロジェクトです。

## 📞 サポート

問題が発生した場合は、[USAGE_TAG_SUGGESTION.md](./USAGE_TAG_SUGGESTION.md) のトラブルシューティングセクションを参照してください。
