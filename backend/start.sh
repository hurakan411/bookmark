#!/bin/bash

# Bookmark Tag Suggestion API 起動スクリプト

echo "🚀 Bookmark Tag Suggestion API を起動します..."

# 仮想環境のチェック
if [ ! -d "venv" ]; then
    echo "⚠️  仮想環境が見つかりません。セットアップを実行します..."
    python3 -m venv venv
    echo "✅ 仮想環境を作成しました"
fi

# 仮想環境を有効化
source venv/bin/activate

# 依存関係のインストール
echo "📦 依存関係をインストール中..."
pip install -r requirements.txt

# .envファイルのチェック
if [ ! -f ".env" ]; then
    echo "⚠️  .envファイルが見つかりません"
    echo "💡 .env.exampleをコピーして.envを作成し、OpenAI API キーを設定してください"
    cp .env.example .env
    echo "📝 .envファイルを編集してください"
    exit 1
fi

# サーバー起動
echo "🌐 サーバーを起動中..."
echo "📍 http://localhost:8000"
echo "📚 API ドキュメント: http://localhost:8000/docs"
echo ""
python main.py
