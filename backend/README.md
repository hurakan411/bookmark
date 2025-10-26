# Bookmark Tag Suggestion API

ブックマークのタイトル、URL、メモから既存のタグリストの中で適切なタグを自動提案するFastAPI バックエンド。

## セットアップ

### 1. 依存関係のインストール

```bash
cd backend
python -m venv venv
source venv/bin/activate  # macOS/Linux
# または
venv\Scripts\activate  # Windows

pip install -r requirements.txt
```

### 2. 環境変数の設定

`.env.example` を `.env` にコピーして、OpenAI API キーを設定：

```bash
cp .env.example .env
```

`.env` ファイルを編集：
```
OPENAI_API_KEY=sk-your-actual-api-key-here

# Reasoning Effort Settings (low, medium, high)
REASONING_EFFORT_SUGGEST_TAGS=low
REASONING_EFFORT_ANALYZE_TAG_STRUCTURE=low
REASONING_EFFORT_BULK_ASSIGN_TAGS=low
REASONING_EFFORT_ANALYZE_FOLDER_STRUCTURE=low
REASONING_EFFORT_BULK_ASSIGN_FOLDERS=low
```

**Reasoning Effortの設定値：**
- `low`: 高速・低コスト（デフォルト推奨）
- `medium`: バランス型
- `high`: 高精度・高コスト

各APIエンドポイントごとに推論レベルを個別に調整できます。

### 3. サーバーの起動

```bash
python main.py
```

または

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

サーバーは `http://localhost:8000` で起動します。

## API ドキュメント

起動後、以下のURLでSwagger UIにアクセス可能：
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## エンドポイント

### POST /suggest-tags

ブックマーク情報から適切なタグを提案

**リクエスト例：**
```json
{
  "title": "Pythonの非同期プログラミング入門",
  "url": "https://example.com/python-async",
  "excerpt": "asyncioを使った非同期処理の基礎を学ぶ",
  "existing_tags": ["Python", "プログラミング", "AI", "Web開発", "データ分析"]
}
```

**レスポンス例：**
```json
{
  "suggested_tags": ["Python", "プログラミング"],
  "reasoning": "AIが分析した結果、2個のタグを提案しました。"
}
```

### GET /health

ヘルスチェック用エンドポイント

**レスポンス例：**
```json
{
  "status": "healthy",
  "openai_api_configured": true
}
```

## 使用モデル

- **gpt-4o-mini**: コスト効率が良く、タグ提案タスクに十分な性能を持つモデル

## セキュリティ注意事項

- 本番環境では CORS 設定を適切に制限してください
- API キーは `.env` ファイルで管理し、リポジトリにコミットしないでください
- 必要に応じて認証機構を追加してください
