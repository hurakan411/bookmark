from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import os
from dotenv import load_dotenv
from openai import OpenAI
import logging
import time

# 環境変数の読み込み
load_dotenv()

app = FastAPI(title="Bookmark Tag Suggestion API")

# ログ設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("tag_suggestion_api")

# reasoning_effortの環境変数（デフォルト値: "low"）
REASONING_EFFORT_SUGGEST_TAGS = os.getenv("REASONING_EFFORT_SUGGEST_TAGS", "low")
REASONING_EFFORT_ANALYZE_TAG_STRUCTURE = os.getenv("REASONING_EFFORT_ANALYZE_TAG_STRUCTURE", "low")
REASONING_EFFORT_BULK_ASSIGN_TAGS = os.getenv("REASONING_EFFORT_BULK_ASSIGN_TAGS", "low")
REASONING_EFFORT_ANALYZE_FOLDER_STRUCTURE = os.getenv("REASONING_EFFORT_ANALYZE_FOLDER_STRUCTURE", "low")
REASONING_EFFORT_BULK_ASSIGN_FOLDERS = os.getenv("REASONING_EFFORT_BULK_ASSIGN_FOLDERS", "low")

# CORS設定（Flutterアプリからのアクセスを許可）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 本番環境では適切なオリジンを指定
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# OpenAI クライアントの初期化
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


# リクエスト/レスポンスモデル
class TagSuggestionRequest(BaseModel):
    title: str
    url: str
    excerpt: Optional[str] = ""
    existing_tags: List[str]  # 既存のタグリスト


class TagSuggestionResponse(BaseModel):
    suggested_tags: List[str]
    reasoning: Optional[str] = None


class OptimalTagStructureRequest(BaseModel):
    bookmarks: List[dict]  # {title, url, excerpt, current_tags}
    current_tags: List[str]  # 現在存在する全タグ


class OptimalTagStructureResponse(BaseModel):
    suggested_tags: List[dict]  # {name, description, reasoning, merge_from}
    tags_to_remove: List[str]  # 削除を推奨するタグ
    overall_reasoning: str


class BulkTagAssignmentRequest(BaseModel):
    bookmarks: List[dict]  # {id, title, url, excerpt, current_tags}
    available_tags: List[str]  # 利用可能な全タグリスト


class BookmarkTagSuggestion(BaseModel):
    bookmark_id: str
    suggested_tags: List[str]
    reasoning: Optional[str] = None


class BulkTagAssignmentResponse(BaseModel):
    suggestions: List[BookmarkTagSuggestion]
    total_processed: int
    overall_reasoning: str


class OptimalFolderStructureRequest(BaseModel):
    bookmarks: List[dict]  # {title, url, excerpt, current_folder}
    current_folders: List[str]  # 現在存在する全フォルダ（フラットリスト）
    instruction: Optional[str] = None  # ユーザーからの追加指示


class OptimalFolderStructureResponse(BaseModel):
    suggested_folders: List[dict]  # {name, description, reasoning, merge_from, parent}
    folders_to_remove: List[str]  # 削除を推奨するフォルダ
    overall_reasoning: str


class BulkFolderAssignmentRequest(BaseModel):
    bookmarks: List[dict]  # {id, title, url, excerpt, current_folder}
    available_folders: List[str]  # 利用可能な全フォルダリスト
    instruction: Optional[str] = None  # ユーザーからの追加指示


class BookmarkFolderSuggestion(BaseModel):
    bookmark_id: str
    suggested_folder: str
    reasoning: Optional[str] = None


class BulkFolderAssignmentResponse(BaseModel):
    suggestions: List[BookmarkFolderSuggestion]
    total_processed: int
    overall_reasoning: str


@app.get("/")
async def root():
    return {
        "message": "Bookmark Tag Suggestion API",
        "version": "1.0.0",
        "endpoints": {
            "/suggest-tags": "POST - ブックマークに適切なタグを提案"
        }
    }


@app.post("/suggest-tags", response_model=TagSuggestionResponse)
async def suggest_tags(request: TagSuggestionRequest):
    """
    ブックマークの情報から既存のタグリストの中から適切なタグを自動提案する
    """
    start_time = time.time()
    
    try:
        # OpenAI API キーのチェック
        if not os.getenv("OPENAI_API_KEY"):
            raise HTTPException(
                status_code=500,
                detail="OpenAI API key is not configured"
            )

        # 既存タグがない場合
        if not request.existing_tags:
            return TagSuggestionResponse(
                suggested_tags=[],
                reasoning="既存のタグがないため、タグを提案できません。"
            )

        # プロンプトの作成
        prompt = f"""あなたはブックマーク管理アシスタントです。
以下のブックマーク情報を分析し、既存のタグリストから最も適切なタグを選んでください。

【重要】タグとフォルダの使い分け
- **フォルダ**: カテゴリや分類（例: 仕事、趣味、プロジェクト名など）
- **タグ**: コンテンツの特徴や属性を表すキーワード
  - そのブックマークの特徴・属性（技術スタック、テーマ、形式など）
  - 検索・フィルタリングで使うキーワード
  - 横断的な分類（複数のフォルダにまたがる特徴）

【ブックマーク情報】
タイトル: {request.title}
URL: {request.url}
メモ: {request.excerpt}

【既存のタグリスト】
{', '.join(request.existing_tags)}

【指示】
1. このブックマークの**特徴・属性**を表すタグを既存リストから1〜3個選んでください
2. 検索やフィルタリングで使いやすいキーワードを優先してください
3. 既存のタグリストに適切なものがない場合は、空のリストを返してください
4. タグ名のみをカンマ区切りで返してください（説明は不要）

良い例: 
- 技術記事 → タグ: Python, AI, チュートリアル
- デザイン参考 → タグ: UI/UX, レスポンシブ, モダン
- ニュース記事 → タグ: テクノロジー, 最新動向, 2024年

回答例: プログラミング, Python, AI"""

        # OpenAI APIを呼び出し
        response = client.chat.completions.create(
            model="gpt-5-mini",  # コスト効率の良いモデルを使用
            messages=[
                {
                    "role": "system",
                    "content": "あなたは正確で簡潔なタグ提案を行うアシスタントです。必ず既存のタグリストの中からのみ選択してください。"
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            # reasoning_effort="medium",  # Render.comの古いopenaiライブラリではサポートされていないためコメントアウト
            max_completion_tokens=2000,
            reasoning_effort=REASONING_EFFORT_SUGGEST_TAGS,
        )

        # レスポンスからタグを抽出
        suggested_text = response.choices[0].message.content.strip()
        
        # カンマ区切りのタグを分割
        suggested_tags = [
            tag.strip() 
            for tag in suggested_text.split(',') 
            if tag.strip()
        ]
        
        # 既存のタグリストに存在するもののみをフィルタリング
        valid_tags = [
            tag for tag in suggested_tags 
            if tag in request.existing_tags
        ]

        # 処理時間とトークン数をログ
        elapsed_time = time.time() - start_time
        usage = response.usage
        logger.info(f"📊 [suggest-tags] 処理完了")
        logger.info(f"  ⏱️  処理時間: {elapsed_time:.2f}秒")
        logger.info(f"  🔢 入力トークン: {usage.prompt_tokens}")
        logger.info(f"  🔢 出力トークン: {usage.completion_tokens}")
        logger.info(f"  🔢 合計トークン: {usage.total_tokens}")
        logger.info(f"  ✅ 提案タグ数: {len(valid_tags)}")

        return TagSuggestionResponse(
            suggested_tags=valid_tags,
            reasoning=f"AIが分析した結果、{len(valid_tags)}個のタグを提案しました。"
        )

    except Exception as e:
        elapsed_time = time.time() - start_time
        logger.error(f"❌ [suggest-tags] エラー (処理時間: {elapsed_time:.2f}秒)")
        logger.error(f"タグAI自動提案エラー: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"タグ提案の生成中にエラーが発生しました: {str(e)}"
        )


@app.get("/health")
async def health_check():
    """ヘルスチェック用エンドポイント"""
    api_key_configured = bool(os.getenv("OPENAI_API_KEY"))
    return {
        "status": "healthy" if api_key_configured else "warning",
        "openai_api_configured": api_key_configured
    }


@app.post("/analyze-tag-structure", response_model=OptimalTagStructureResponse)
async def analyze_tag_structure(request: OptimalTagStructureRequest):
    """
    全ブックマークを分析して最適なタグ構成を提案する
    - 新しいタグの提案
    - 類似タグの統合提案
    - 使われていない/不適切なタグの削除提案
    """
    start_time = time.time()
    
    try:
        # OpenAI API キーのチェック
        if not os.getenv("OPENAI_API_KEY"):
            raise HTTPException(
                status_code=500,
                detail="OpenAI API key is not configured"
            )

        # ブックマーク情報の要約
        bookmark_summary = []
        for i, bm in enumerate(request.bookmarks[:50]):  # 最初の50件を分析
            bookmark_summary.append(
                f"{i+1}. {bm.get('title', 'No title')} - タグ: {', '.join(bm.get('current_tags', []))}"
            )

        # プロンプトの作成
        prompt = f"""あなたは熟練したブックマーク管理・情報整理の専門家です。
以下のブックマーク一覧と現在のタグ構成を分析し、最適なタグ構成を提案してください。

【重要】タグとフォルダの使い分け
- **フォルダ**: 大分類・カテゴリ（例: 仕事、趣味、プロジェクト名）
- **タグ**: コンテンツの特徴・属性を表すキーワード
  - そのコンテンツの具体的な特徴（技術、テーマ、形式など）
  - 検索・フィルタリング用のキーワード
  - 横断的な分類（複数フォルダにまたがる特徴）

【現在のタグ一覧】（全{len(request.current_tags)}個）
{', '.join(request.current_tags) if request.current_tags else 'タグがありません'}

【ブックマーク一覧】（全{len(request.bookmarks)}件、表示は最初の50件）
{chr(10).join(bookmark_summary)}

【分析と提案】
以下の観点で分析し、改善案を提案してください：

1. **新規タグの提案**
   - コンテンツの**特徴・属性**を表すタグ
   - **検索・フィルタリングで使いやすい**キーワード
   - 各タグの説明と、なぜ必要かの理由（簡潔に）
   - **重要：１つのブックマークにしか適用されないタグは提案しないでください**
   - **重要：タグ名は基本的に日本語で提案してください。アルファベットは必要最小限にしてください**
   - **重要：英語の固有名詞や専門用語を除き、できるだけ日本語表記を使用してください**
   - **重要：タグは概念的・抽象的な単語に限定してください。詳細すぎる・具体的すぎるタグは避けてください**
   - **良い例：「開発」「デザイン」「学習」「リファレンス」「チュートリアル」「ツール」**
   - **悪い例：「React Hooks の使い方」「VSCode 拡張機能開発」「Python データ分析入門」（詳細すぎる）**
   - **タグは2-5文字程度の簡潔な単語を推奨します**

2. **タグの統合提案**
   - 意味が重複している類似タグの統合案
   - **統合元のタグが2個以上ある場合のみ提案**（1個だけの場合は統合不要）
   - 例：「プログラミング」と「コーディング」→「プログラミング」に統合
   - **統合後のタグ名も日本語を優先し、より概念的な単語を選んでください**

3. **削除推奨タグ**
   - ほとんど使われていないタグ
   - 曖昧すぎるタグ、または大分類的なタグ（フォルダで管理すべきもの）
   - 検索・フィルタリングに役立たないタグ
   - **詳細すぎる・具体的すぎるタグ（「○○の使い方」「××入門」など）**
   - **重要：１つのブックマークにしか使われていないタグは削除候補にしてください**

【回答形式】
JSON形式で以下の構造で返してください。overall_reasoningは100字以内で簡潔に：

{{
  "suggested_tags": [
    {{
      "name": "提案するタグ名（日本語優先）",
      "description": "このタグの用途説明（30字以内）",
      "reasoning": "なぜこのタグが必要か（50字以内）",
      "merge_from": ["統合元のタグ1", "統合元のタグ2"]
    }}
  ],
  "tags_to_remove": ["削除推奨タグ1", "削除推奨タグ2"],
  "overall_reasoning": "全体的な分析結果と改善方針の説明（100字以内）"
}}

注意：
- merge_fromは既存タグの統合時のみ使用（新規タグの場合は空配列）
- **merge_fromには必ず2個以上のタグを含めること**（1個だけの場合は統合提案しない）
- suggested_tagsには新規タグと統合後のタグの両方を含める
- タグはコンテンツの**特徴・属性**や**検索キーワード**であることを意識
- フォルダで管理すべき大分類的なタグは提案しない
- **タグ名は日本語を基本とし、英語の固有名詞や広く使われている専門用語以外はアルファベットを避けてください**
- **タグは概念的・抽象的な単語（2-5文字程度）に限定し、詳細すぎる・具体的すぎるタグは避けてください**
- **複数の単語を組み合わせた長いタグや、文章のようなタグは作成しないでください**
- 日本語で分かりやすく説明してください
- 実用的で具体的な提案をしてください"""

        # OpenAI APIを呼び出し
        response = client.chat.completions.create(
            model="gpt-5-mini",
            messages=[
                {
                    "role": "system",
                    "content": "あなたは情報整理とタグ分類の専門家です。実用的で分かりやすいタグ構成を提案してください。必ずJSON形式で回答してください。"
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            # reasoning_effort="medium",  # Render.comの古いopenaiライブラリではサポートされていないためコメントアウト
            max_completion_tokens=10000,
            reasoning_effort=REASONING_EFFORT_ANALYZE_TAG_STRUCTURE,
            response_format={"type": "json_object"}
        )

        # レスポンスを解析
        import json
        
        response_content = response.choices[0].message.content
        
        # 空の応答チェック
        if not response_content or response_content.strip() == "":
            logger.error(f"OpenAI returned empty content. Finish reason: {response.choices[0].finish_reason}")
            logger.error(f"Usage: {response.usage}")
            raise HTTPException(
                status_code=500,
                detail="AIからの応答が空でした。トークン数が不足している可能性があります。"
            )
        
        result = json.loads(response_content)

        # 処理時間とトークン数をログ
        elapsed_time = time.time() - start_time
        usage = response.usage
        logger.info(f"📊 [analyze-tag-structure] 処理完了")
        logger.info(f"  ⏱️  処理時間: {elapsed_time:.2f}秒")
        logger.info(f"  🔢 入力トークン: {usage.prompt_tokens}")
        logger.info(f"  🔢 出力トークン: {usage.completion_tokens}")
        logger.info(f"  🔢 合計トークン: {usage.total_tokens}")
        logger.info(f"  ✅ 提案タグ数: {len(result.get('suggested_tags', []))}")
        logger.info(f"  🗑️  削除推奨数: {len(result.get('tags_to_remove', []))}")

        return OptimalTagStructureResponse(
            suggested_tags=result.get("suggested_tags", []),
            tags_to_remove=result.get("tags_to_remove", []),
            overall_reasoning=result.get("overall_reasoning", "")
        )

    except json.JSONDecodeError as e:
        elapsed_time = time.time() - start_time
        logger.error(f"❌ [analyze-tag-structure] JSON解析エラー (処理時間: {elapsed_time:.2f}秒)")
        logger.error(f"JSON解析エラー: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail="AIからの応答をJSON形式で解析できませんでした"
        )
    except Exception as e:
        elapsed_time = time.time() - start_time
        logger.error(f"❌ [analyze-tag-structure] エラー (処理時間: {elapsed_time:.2f}秒)")
        logger.error(f"タグ構成分析エラー: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"タグ構成分析中にエラーが発生しました: {str(e)}"
        )


@app.post("/bulk-assign-tags", response_model=BulkTagAssignmentResponse)
async def bulk_assign_tags(request: BulkTagAssignmentRequest):
    """
    全ブックマークに対してAIが適切なタグを一括で提案する
    既存の/suggest-tagsエンドポイントの機能を活用
    """
    start_time = time.time()
    total_prompt_tokens = 0
    total_completion_tokens = 0
    total_tokens_sum = 0
    
    try:
        # OpenAI API キーのチェック
        if not os.getenv("OPENAI_API_KEY"):
            raise HTTPException(
                status_code=500,
                detail="OpenAI API key is not configured"
            )

        if not request.available_tags:
            return BulkTagAssignmentResponse(
                suggestions=[],
                total_processed=0,
                overall_reasoning="利用可能なタグがないため、提案できません。"
            )

        suggestions = []
        
        # 各ブックマークに対してタグを提案
        for bookmark in request.bookmarks[:100]:  # 最大100件まで処理
            bookmark_id = bookmark.get('id', '')
            title = bookmark.get('title', 'No title')
            url = bookmark.get('url', '')
            excerpt = bookmark.get('excerpt', '')
            current_tags = bookmark.get('current_tags', [])

            # プロンプトの作成（既存の/suggest-tagsと同じロジック）
            prompt = f"""あなたはブックマーク管理アシスタントです。
以下のブックマーク情報を分析し、既存のタグリストから最も適切なタグを選んでください。

【重要】タグとフォルダの使い分け
- **フォルダ**: カテゴリや分類（例: 仕事、趣味、プロジェクト名など）
- **タグ**: コンテンツの特徴や属性を表すキーワード
  - そのブックマークの特徴・属性（技術スタック、テーマ、形式など）
  - 検索・フィルタリングで使うキーワード
  - 横断的な分類（複数のフォルダにまたがる特徴）

【ブックマーク情報】
タイトル: {title}
URL: {url}
メモ: {excerpt}

【既存のタグリスト】
{', '.join(request.available_tags)}

【現在のタグ】
{', '.join(current_tags) if current_tags else 'なし'}

【指示】
1. このブックマークの**特徴・属性**を表すタグを既存リストから1〜3個選んでください
2. 検索やフィルタリングで使いやすいキーワードを優先してください
3. 既存のタグリストに適切なものがない場合は、空のリストを返してください
4. タグ名のみをカンマ区切りで返してください（説明は不要）

良い例: 
- 技術記事 → タグ: Python, AI, チュートリアル
- デザイン参考 → タグ: UI/UX, レスポンシブ, モダン
- ニュース記事 → タグ: テクノロジー, 最新動向, 2024年

回答例: プログラミング, Python, AI"""

            try:
                # OpenAI APIを呼び出し
                response = client.chat.completions.create(
                    model="gpt-5-mini",
                    messages=[
                        {
                            "role": "system",
                            "content": "あなたは正確で簡潔なタグ提案を行うアシスタントです。必ず既存のタグリストの中からのみ選択してください。"
                        },
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ],
                    max_completion_tokens=2000,
                    reasoning_effort=REASONING_EFFORT_BULK_ASSIGN_TAGS,
                )

                # レスポンスからタグを抽出
                suggested_text = response.choices[0].message.content.strip()
                
                # トークン数を集計
                total_prompt_tokens += response.usage.prompt_tokens
                total_completion_tokens += response.usage.completion_tokens
                total_tokens_sum += response.usage.total_tokens
                
                # カンマ区切りのタグを分割
                suggested_tags = [
                    tag.strip() 
                    for tag in suggested_text.split(',') 
                    if tag.strip()
                ]
                
                # 既存のタグリストに存在するもののみをフィルタリング
                valid_tags = [
                    tag for tag in suggested_tags 
                    if tag in request.available_tags
                ]

                suggestions.append(BookmarkTagSuggestion(
                    bookmark_id=bookmark_id,
                    suggested_tags=valid_tags,
                    reasoning=f"{len(valid_tags)}個のタグを提案"
                ))

            except Exception as e:
                logger.error(f"ブックマーク {bookmark_id} のタグ提案エラー: {e}")
                suggestions.append(BookmarkTagSuggestion(
                    bookmark_id=bookmark_id,
                    suggested_tags=[],
                    reasoning=f"エラー: {str(e)}"
                ))

        # 処理時間とトークン数をログ
        elapsed_time = time.time() - start_time
        logger.info(f"📊 [bulk-assign-tags] 処理完了")
        logger.info(f"  ⏱️  処理時間: {elapsed_time:.2f}秒")
        logger.info(f"  🔢 入力トークン合計: {total_prompt_tokens}")
        logger.info(f"  🔢 出力トークン合計: {total_completion_tokens}")
        logger.info(f"  🔢 合計トークン: {total_tokens_sum}")
        logger.info(f"  📝 処理ブックマーク数: {len(suggestions)}")

        return BulkTagAssignmentResponse(
            suggestions=suggestions,
            total_processed=len(suggestions),
            overall_reasoning=f"{len(suggestions)}件のブックマークに対してタグを提案しました。"
        )

    except Exception as e:
        elapsed_time = time.time() - start_time
        logger.error(f"❌ [bulk-assign-tags] エラー (処理時間: {elapsed_time:.2f}秒)")
        logger.error(f"一括タグ割り当てエラー: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"一括タグ割り当て中にエラーが発生しました: {str(e)}"
        )


@app.post("/analyze-folder-structure", response_model=OptimalFolderStructureResponse)
async def analyze_folder_structure(request: OptimalFolderStructureRequest):
    """
    全ブックマークを分析して最適なフォルダ構成を提案する
    - 新しいフォルダの提案
    - 類似フォルダの統合提案
    - 使われていない/不適切なフォルダの削除提案
    """
    start_time = time.time()
    
    logger.info("=== フォルダ構成分析API呼び出し ===")
    logger.info(f"ブックマーク数: {len(request.bookmarks)}")
    logger.info(f"現在のフォルダ数: {len(request.current_folders)}")
    logger.info(f"現在のフォルダ: {request.current_folders}")
    
    try:
        # OpenAI API キーのチェック
        if not os.getenv("OPENAI_API_KEY"):
            logger.error("OpenAI API key is not configured")
            raise HTTPException(
                status_code=500,
                detail="OpenAI API key is not configured"
            )

        # ブックマーク情報の要約
        bookmark_summary = []
        for i, bm in enumerate(request.bookmarks[:50]):  # 最初の50件を分析
            bookmark_summary.append(
                f"{i+1}. {bm.get('title', 'No title')} - フォルダ: {bm.get('current_folder', '未分類')}"
            )

        # プロンプトの作成
        prompt = f"""あなたは熟練したブックマーク管理・情報整理の専門家です。
以下のブックマーク一覧と現在のフォルダ構成を分析し、最適なフォルダ構成を提案してください。

【フォルダ数の上限ルール】
- 作成するフォルダの最大数は、以下の数式で決定してください：
  - 最大フォルダ数 = min(15, max(3, floor(1.5 * sqrt(ブックマーク数))))
  - 現在のブックマーク数: {len(request.bookmarks)}件
- 例: 9件 → 4個, 100件 → 15個, 400件 → 15個（上限）
- この上限を超えてフォルダを提案しないこと

【フォルダ名の命名規則】
- **フォルダ名は原則として日本語で付けてください**
- アルファベットや英単語の使用は最低限にしてください
- 例: ❌「Programming」「Web Design」 → ⭕「プログラミング」「ウェブデザイン」
- 例: ❌「Python」「JavaScript」 → ⭕「Python学習」「JavaScript開発」（技術名は許容）

【重要】フォルダとタグの使い分け
- **フォルダ**: 大分類・カテゴリ（例: 仕事、趣味、プロジェクト名、テーマ別）
  - 主要な分類軸となるカテゴリ
  - ブックマークの所属先（1つのフォルダに所属）
  - **階層構造で整理可能**（親フォルダ/子フォルダの関係）
- **タグ**: コンテンツの特徴・属性を表すキーワード
  - 横断的な分類（複数のフォルダにまたがる特徴）
  - 検索・フィルタリング用

【現在のフォルダ一覧】（全{len(request.current_folders)}個）
{', '.join(request.current_folders) if request.current_folders else 'フォルダがありません'}

【ブックマーク一覧】（全{len(request.bookmarks)}件、表示は最初の50件）
{chr(10).join(bookmark_summary)}

【最重要原則：MECE（Mutually Exclusive, Collectively Exhaustive）】
- **Mutually Exclusive（相互排他的）**: フォルダ間に重複・ダブりがないこと
  - 同じブックマークが複数のフォルダに該当するような曖昧な分類は避ける
  - 各フォルダの定義が明確で、境界が重ならないこと
  - 類似した意味のフォルダは統合すること
- **Collectively Exhaustive（網羅的）**: 全てのブックマークが適切なフォルダに分類できること
  - 抜け漏れがなく、全てのブックマークがどこかのフォルダに所属できる
  - 「その他」「未分類」を最小限に抑える

【適切な粒度の原則】
**ブックマーク数に対してフォルダを細分化しすぎないこと**
- ブックマーク総数が**{len(request.bookmarks)}件**であることを常に意識する
- **1フォルダあたり最低5〜10件のブックマーク**が入る粒度を目安にする
- 目安：
  * ブックマーク50件未満 → フォルダは5〜8個程度（第1階層のみ、または浅い階層）
  * ブックマーク50〜200件 → フォルダは10〜15個程度（第2階層まで）
  * ブックマーク200件以上 → フォルダは15〜25個程度（第3階層まで可）
- **細かすぎる分類は避ける**：1〜2個のブックマークしか入らないフォルダは作らない
- **粒度を揃える**：同じ階層のフォルダは同程度の粒度・規模にする

【分析指示】
現在のフォルダ一覧を見て、必ず以下の3つを提案してください：

1. **新規・階層構造の提案（必須）**
   - **ブックマーク総数{len(request.bookmarks)}件に対して適切な粒度で提案**
   - フォルダを細分化しすぎないこと（1フォルダあたり最低5〜10件を目安）
   - 第1階層だけでなく、**第2階層、第3階層のフォルダも積極的に提案**してください
     * ただし、ブックマーク数が少ない場合は階層を浅くする
   - 親子関係を活用した階層構造を作成してください
   - 例: 親「プログラミング」→子「Python」「JavaScript」「Web開発」
   - **重要：フォルダ名には親フォルダ名を含めないこと**
     * 良い例: 親「プログラミング」、子「Python」
     * 悪い例: 親「プログラミング」、子「プログラミング/Python」
   - **MECE原則を遵守**：各フォルダの定義が明確で、重複しないこと
   - **1〜2個のブックマークしか入らないフォルダは提案しない**

2. **フォルダ統合（必須：類似・重複フォルダを必ず探して提案）**
   - **MECEの「相互排他的」を実現するため、重複・ダブりを徹底排除**
   - **現在のフォルダ一覧を注意深く見て、類似・重複しているフォルダを必ず見つけ出す**
   - 第1階層だけでなく、**第2階層以降の子フォルダも必ずチェック**
   - 統合すべきパターン（MECE違反）：
     * 同じ意味のフォルダ（例: 「開発」「Development」「プログラミング」）
     * 異なる親の下に同じ子フォルダ（例: 「A/Web」「B/Web」→「開発/Web」に統合）
     * 表記違い（例: 「AI」「人工知能」）
     * 範囲重複（例: 「Web開発」「フロントエンド」「React」）
     * 包含関係が不明確（例: 「技術」と「プログラミング」が同階層）
   - **【重要】「未分類」フォルダは統合対象から除外してください**
   - **統合提案は2個以上のフォルダをまとめる場合のみ**
   - **類似フォルダが見つからない場合でも、最低1〜2件は統合案を出してください**

3. **削除推奨（必須：不要フォルダを必ず探して提案）**
   - **全階層（第1層、第2層、第3層以降）で不要なフォルダを必ず見つけ出す**
   - **細分化しすぎているフォルダを積極的に削除**（ブックマーク数に対して粒度が細かすぎる）
   - 削除すべきパターン：
     * 1〜2個のブックマークにしか使われていないフォルダ（必ず削除）
     * ほとんど使われていないフォルダ（3〜4個以下）
     * 曖昧すぎるフォルダ（例: 「その他」「メモ」「資料」）→MECE違反
     * 統合後に不要になるフォルダ
     * 定義が不明確で分類しづらいフォルダ
     * 他のフォルダと統合できる細かすぎるフォルダ
   - **【重要】「未分類」フォルダは削除対象から除外してください**
   - **不要フォルダが見つからない場合でも、最低1〜2件は削除候補を出してください**

【回答形式】
JSON形式で以下の構造で返してください。overall_reasoningは100字以内で簡潔に：

{{
  "suggested_folders": [
    {{
      "name": "フォルダ名（親フォルダ名を含めない！）",
      "description": "このフォルダの用途説明（30字以内）",
      "reasoning": "なぜこのフォルダが必要か（50字以内）",
      "parent": "親フォルダ名（トップレベルの場合は空文字\"\"）",
      "merge_from": ["統合元のフォルダ1", "統合元のフォルダ2"]
    }}
  ],
  "folders_to_remove": ["削除推奨フォルダ1", "削除推奨フォルダ2"],
  "overall_reasoning": "全体的な分析結果と改善方針の説明（100字以内）"
}}

【重要な注意事項】
- **【粒度】ブックマーク総数{len(request.bookmarks)}件に対して適切な数・粒度のフォルダを提案**
  - フォルダを細分化しすぎない（1フォルダあたり最低5〜10件を目安）
  - 1〜2個のブックマークしか入らないフォルダは提案しない
- **【最重要】nameには親フォルダ名を含めないこと**
  - 良い例: {{"name": "Python", "parent": "プログラミング"}}
  - 悪い例: {{"name": "プログラミング/Python", "parent": "プログラミング"}}
- **MECE原則を徹底**
  - Mutually Exclusive: フォルダ間に重複・ダブりがないこと
  - Collectively Exhaustive: 全てのブックマークが適切に分類できること
- **suggested_foldersには必ず5件以上提案してください**（新規フォルダ＋統合フォルダの合計）
  - **第2階層、第3階層のフォルダも積極的に含める**（第1階層だけでなく）
  - ただし、ブックマーク数が少ない場合は階層を浅く、数を減らす
- **folders_to_removeには必ず2件以上提案してください**（不要・重複フォルダ）
  - 特に細分化しすぎているフォルダを削除対象にする
- parentで親フォルダを指定（階層構造）。**トップレベルの場合は空文字""**
- **【超重要】nameには親フォルダ名を絶対に含めないこと**（例: ❌"プログラミング/Python" → ⭕"Python"）
- merge_fromは統合時のみ使用（新規は空配列[]）。**2個以上のフォルダを含めること**
- MECE原則を徹底し、重複のない明確なフォルダ構成を提案"""

        logger.info("OpenAI APIにリクエスト送信中...")
        logger.info(f"使用モデル: gpt-5-mini")
        
        # OpenAI APIを呼び出し
        response = client.chat.completions.create(
            model="gpt-5-mini",
            messages=[
                {
                    "role": "system",
                    "content": f"あなたは情報整理とフォルダ分類の専門家です。ブックマーク総数{len(request.bookmarks)}件に対して適切な粒度でフォルダを提案してください。MECE原則（相互排他的かつ網羅的）を徹底してください。必ず以下を守ってください：1) フォルダを細分化しすぎない（1フォルダあたり最低5〜10件、1〜2件しか入らないフォルダは提案しない）、2) suggested_foldersに5件以上提案（第2階層、第3階層のフォルダも含める。ただしブックマーク数が少ない場合は階層を浅く）、3) folders_to_removeに2件以上提案（特に細分化しすぎているフォルダ）、4) 類似・重複フォルダを必ず検出して統合提案、5) 【超重要】nameには親フォルダ名を含めない（例: ❌\"プログラミング/Python\" → ⭕\"Python\"でparent=\"プログラミング\"）、6) 【重要】「未分類」フォルダは統合・削除の対象外とする。必ずJSON形式で回答してください。"
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            max_completion_tokens=10000,
            reasoning_effort=REASONING_EFFORT_ANALYZE_FOLDER_STRUCTURE,
            response_format={"type": "json_object"}
        )

        logger.info("OpenAI APIからレスポンス受信")
        logger.info(f"Finish reason: {response.choices[0].finish_reason}")
        logger.info(f"Usage: {response.usage}")
        
        # レスポンスを解析
        import json
        
        response_content = response.choices[0].message.content
        
        logger.info(f"レスポンス内容の長さ: {len(response_content) if response_content else 0} 文字")
        logger.info(f"レスポンス内容（最初の500文字）: {response_content[:500] if response_content else 'None'}")
        
        # 空の応答チェック
        if not response_content or response_content.strip() == "":
            logger.error(f"OpenAI returned empty content. Finish reason: {response.choices[0].finish_reason}")
            logger.error(f"Usage: {response.usage}")
            raise HTTPException(
                status_code=500,
                detail="AIからの応答が空でした。トークン数が不足している可能性があります。"
            )
        
        logger.info("JSON解析中...")
        result = json.loads(response_content)
        logger.info(f"解析結果: 提案フォルダ数={len(result.get('suggested_folders', []))}, 削除推奨数={len(result.get('folders_to_remove', []))}")

        # 処理時間とトークン数をログ
        elapsed_time = time.time() - start_time
        usage = response.usage
        logger.info(f"📊 [analyze-folder-structure] 処理完了")
        logger.info(f"  ⏱️  処理時間: {elapsed_time:.2f}秒")
        logger.info(f"  🔢 入力トークン: {usage.prompt_tokens}")
        logger.info(f"  🔢 出力トークン: {usage.completion_tokens}")
        logger.info(f"  🔢 合計トークン: {usage.total_tokens}")
        logger.info(f"  ✅ 提案フォルダ数: {len(result.get('suggested_folders', []))}")
        logger.info(f"  🗑️  削除推奨数: {len(result.get('folders_to_remove', []))}")

        response_data = OptimalFolderStructureResponse(
            suggested_folders=result.get("suggested_folders", []),
            folders_to_remove=result.get("folders_to_remove", []),
            overall_reasoning=result.get("overall_reasoning", "")
        )
        
        logger.info("=== フォルダ構成分析API完了 ===")
        return response_data

    except json.JSONDecodeError as e:
        elapsed_time = time.time() - start_time
        logger.error(f"❌ [analyze-folder-structure] JSON解析エラー (処理時間: {elapsed_time:.2f}秒)")
        logger.error(f"JSON解析エラー: {e}", exc_info=True)
        logger.error(f"解析しようとした内容: {response_content if 'response_content' in locals() else 'N/A'}")
        raise HTTPException(
            status_code=500,
            detail="AIからの応答をJSON形式で解析できませんでした"
        )
    except HTTPException:
        # HTTPExceptionはそのまま再送出
        raise
    except Exception as e:
        elapsed_time = time.time() - start_time
        logger.error(f"❌ [analyze-folder-structure] エラー (処理時間: {elapsed_time:.2f}秒)")
        logger.error(f"フォルダ構成分析エラー: {e}", exc_info=True)
        logger.error(f"エラータイプ: {type(e).__name__}")
        raise HTTPException(
            status_code=500,
            detail=f"フォルダ構成分析中にエラーが発生しました: {str(e)}"
        )


@app.post("/bulk-assign-folders", response_model=BulkFolderAssignmentResponse)
async def bulk_assign_folders(request: BulkFolderAssignmentRequest):
    """
    全ブックマークに対してAIが適切なフォルダを一括で提案する
    """
    start_time = time.time()
    
    logger.info("=== フォルダ一括割り当てAPI呼び出し ===")
    logger.info(f"ブックマーク数: {len(request.bookmarks)}")
    logger.info(f"利用可能なフォルダ数: {len(request.available_folders)}")
    
    try:
        # OpenAI API キーのチェック
        if not os.getenv("OPENAI_API_KEY"):
            raise HTTPException(
                status_code=500,
                detail="OpenAI API key is not configured"
            )

        if not request.available_folders:
            return BulkFolderAssignmentResponse(
                suggestions=[],
                total_processed=0,
                overall_reasoning="利用可能なフォルダがないため、提案できません。"
            )

        suggestions = []
        
        # ブックマーク情報を整形（最大100件まで処理）
        bookmarks_summary = []
        for i, bm in enumerate(request.bookmarks[:100]):
            bookmarks_summary.append({
                "id": bm.get('id', ''),
                "title": bm.get('title', 'No title'),
                "url": bm.get('url', ''),
                "excerpt": bm.get('excerpt', ''),
                "current_folder": bm.get('current_folder', '未分類')
            })

        # プロンプトの作成（一括処理）
        prompt = f"""あなたはブックマーク管理アシスタントです。
以下の各ブックマークを分析し、既存のフォルダリストから最も適切なフォルダを1つずつ選んでください。

【重要】フォルダとタグの使い分け
- **フォルダ**: 大分類・カテゴリ（例: 仕事、趣味、プロジェクト名、テーマ別）
  - ブックマークの主要な分類軸
  - 1つのブックマークは1つのフォルダに所属
  - **階層構造を持つフォルダが利用可能**（例: 「プログラミング / Python」「開発 / Web開発」）
- **タグ**: コンテンツの特徴・属性を表すキーワード
  - 横断的な分類（複数のフォルダにまたがる特徴）

【利用可能なフォルダリスト】（階層構造を含む）
{chr(10).join([f"- {folder}" for folder in request.available_folders])}

【ブックマーク一覧】（全{len(bookmarks_summary)}件）
{chr(10).join([f"{i+1}. ID:{bm['id']} | タイトル:{bm['title']} | 現在のフォルダ:{bm['current_folder']}" for i, bm in enumerate(bookmarks_summary)])}

【重要な選択ルール】
1. **最も深い階層のフォルダを優先的に選択してください**
   - ❌ 悪い例: 「プログラミング」（浅すぎる）
   - ✅ 良い例: 「プログラミング / Python / Django」（具体的）
   - ✅ 良い例: 「開発 / Web開発 / フロントエンド」（具体的）

2. **階層が深いフォルダが複数ある場合は、最も適切なものを選ぶ**
   - 利用可能なフォルダをよく見て、「/」が含まれる深い階層のフォルダを積極的に使用

3. **第1階層（親フォルダのみ）は極力避ける**
   - 第2階層、第3階層がある場合は、そちらを優先

【指示】
1. 各ブックマークの内容を詳しく分析してください
2. 利用可能なフォルダリストから、**最も深い階層で最も具体的なフォルダ**を選んでください
3. ブックマークの**主要なテーマ・カテゴリ**に基づいて判断してください
4. **【超重要】「未分類」は極力避けてください**
   - 必ず利用可能なフォルダの中から最も近い・関連するものを選んでください
   - 完全一致でなくても、少しでも関連性があればそのフォルダに割り当ててください
   - どうしても全く関連性がない場合のみ「未分類」を選んでください（最終手段）
5. **フォルダ名は利用可能なフォルダリストから完全一致で選ぶこと**（階層構造も含めて）
6. **全てのブックマークに対して提案してください**（現在のフォルダと同じでも構いません）
7. 以下のJSON形式で回答してください（他の説明は不要）：

{{
  "assignments": [
    {{
      "bookmark_id": "ブックマークID",
      "suggested_folder": "提案するフォルダ名",
      "reasoning": "選択理由（20字以内）"
    }}
  ]
}}

注意：
- **全てのブックマークに対して提案すること**
- **suggested_folderは階層構造を含む完全なパスで指定**（例: 「プログラミング / Python」）
- suggested_folderは必ず利用可能なフォルダリストから完全一致で選ぶこと
- **【超重要】「未分類」は極力避けること**。少しでも関連性があればそのフォルダを選ぶこと
- **第2階層、第3階層のフォルダを積極的に使用すること**（より詳細な分類）
- reasoningは簡潔に（例: 「Python学習コンテンツ」「Webデザイン参考」）
- 日本語で回答してください"""

        logger.info("OpenAI APIにリクエスト送信中...")
        
        # OpenAI APIを呼び出し
        response = client.chat.completions.create(
            model="gpt-5-mini",
            messages=[
                {
                    "role": "system",
                    "content": "あなたはブックマーク整理の専門家です。各ブックマークの内容を分析し、最も適切なフォルダに分類してください。階層の深いフォルダ（第2階層、第3階層）を積極的に使用して、より詳細で整理された分類を行ってください。【超重要】「未分類」は極力避け、少しでも関連性があればそのフォルダに割り当ててください。どうしても全く関連性がない場合のみ「未分類」を選んでください。必ずJSON形式で回答してください。"
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            # reasoning_effort="medium",  # Render.comの古いopenaiライブラリではサポートされていないためコメントアウト
            max_completion_tokens=15000,  # トークン数上限を増やして全件対応
            reasoning_effort=REASONING_EFFORT_BULK_ASSIGN_FOLDERS,
            response_format={"type": "json_object"}
        )

        logger.info("OpenAI APIからレスポンス受信")
        logger.info(f"Finish reason: {response.choices[0].finish_reason}")
        
        # finish_reasonチェック
        if response.choices[0].finish_reason == "length":
            logger.warning("⚠️ トークン数制限により応答が途中で切れました")
            logger.warning(f"処理ブックマーク数: {len(bookmarks_summary)}件")
            logger.warning("ブックマーク数を減らして再試行することを推奨します")
        
        # レスポンスを解析
        import json
        
        response_content = response.choices[0].message.content
        
        if not response_content or response_content.strip() == "":
            logger.error("OpenAI returned empty content")
            logger.error(f"Finish reason: {response.choices[0].finish_reason}")
            logger.error(f"Usage: {response.usage}")
            raise HTTPException(
                status_code=500,
                detail="AIからの応答が空でした。"
            )
        
        logger.info(f"レスポンス内容の長さ: {len(response_content)} 文字")
        
        try:
            result = json.loads(response_content)
            assignments = result.get("assignments", [])
        except json.JSONDecodeError as e:
            logger.error(f"JSON解析エラー: {e}")
            logger.error(f"レスポンス内容（最初の1000文字）: {response_content[:1000]}")
            logger.error(f"レスポンス内容（最後の500文字）: {response_content[-500:]}")
            
            # JSON修復を試みる
            try:
                # 不完全なJSONの場合、最後の配列要素を補完
                if response_content.strip().endswith('"'):
                    # 最後のカンマやブラケットが欠けている可能性
                    fixed_content = response_content.strip()
                    if not fixed_content.endswith(']}'):
                        # 配列の閉じ括弧を追加
                        if not fixed_content.endswith(']'):
                            fixed_content += ']'
                        if not fixed_content.endswith('}'):
                            fixed_content += '}'
                    
                    logger.info("JSON修復を試みます...")
                    result = json.loads(fixed_content)
                    assignments = result.get("assignments", [])
                    logger.info(f"✅ JSON修復成功: {len(assignments)}件の割り当てを取得")
                else:
                    raise e
            except Exception as repair_error:
                logger.error(f"JSON修復失敗: {repair_error}")
                raise HTTPException(
                    status_code=500,
                    detail=f"AIからの応答をJSON形式で解析できませんでした: {str(e)}"
                )
        
        logger.info(f"割り当て結果: {len(assignments)}件")
        
        if len(assignments) == 0:
            logger.warning("⚠️ 割り当て結果が0件でした")
            logger.warning(f"応答内容: {response_content[:500]}")
        
        if len(assignments) < len(bookmarks_summary):
            logger.warning(f"⚠️ 一部のブックマークに対する割り当てが欠けています")
            logger.warning(f"期待: {len(bookmarks_summary)}件、実際: {len(assignments)}件")
        
        # レスポンスを整形
        for assignment in assignments:
            suggestions.append(BookmarkFolderSuggestion(
                bookmark_id=assignment.get("bookmark_id", ""),
                suggested_folder=assignment.get("suggested_folder", "未分類"),
                reasoning=assignment.get("reasoning", "")
            ))

        # 処理時間とトークン数をログ
        elapsed_time = time.time() - start_time
        usage = response.usage
        logger.info(f"📊 [bulk-assign-folders] 処理完了")
        logger.info(f"  ⏱️  処理時間: {elapsed_time:.2f}秒")
        logger.info(f"  🔢 入力トークン: {usage.prompt_tokens}")
        logger.info(f"  🔢 出力トークン: {usage.completion_tokens}")
        logger.info(f"  🔢 合計トークン: {usage.total_tokens}")
        logger.info(f"  📝 処理ブックマーク数: {len(suggestions)}")

        return BulkFolderAssignmentResponse(
            suggestions=suggestions,
            total_processed=len(suggestions),
            overall_reasoning=f"{len(suggestions)}件のブックマークに対してフォルダを提案しました。"
        )

    except json.JSONDecodeError as e:
        elapsed_time = time.time() - start_time
        logger.error(f"❌ [bulk-assign-folders] JSON解析エラー (処理時間: {elapsed_time:.2f}秒)")
        logger.error(f"JSON解析エラー: {e}")
        logger.error(f"エラー位置: line {e.lineno}, column {e.colno}")
        logger.error(f"レスポンス全体の長さ: {len(response_content if 'response_content' in locals() else '')} 文字")
        if 'response_content' in locals():
            logger.error(f"レスポンス内容（最初の1000文字）: {response_content[:1000]}")
            logger.error(f"レスポンス内容（最後の1000文字）: {response_content[-1000:]}")
        if 'response' in locals():
            logger.error(f"Finish reason: {response.choices[0].finish_reason}")
            logger.error(f"Usage: {response.usage}")
        raise HTTPException(
            status_code=500,
            detail=f"AIからの応答をJSON形式で解析できませんでした。トークン制限により応答が不完全な可能性があります。ブックマーク数: {len(request.bookmarks)}件"
        )
    except Exception as e:
        elapsed_time = time.time() - start_time
        logger.error(f"❌ [bulk-assign-folders] エラー (処理時間: {elapsed_time:.2f}秒)")
        logger.error(f"一括フォルダ割り当てエラー: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"一括フォルダ割り当て中にエラーが発生しました: {str(e)}"
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

