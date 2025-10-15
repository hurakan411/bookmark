#!/usr/bin/env python3
"""
タグ自動提案APIのテストスクリプト
"""
import requests
import json

BASE_URL = "http://localhost:8000"

def test_health_check():
    """ヘルスチェック"""
    print("🏥 ヘルスチェック...")
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=5)
        data = response.json()
        print(f"✅ ステータス: {data['status']}")
        print(f"🔑 OpenAI API設定: {'✅' if data['openai_api_configured'] else '❌'}")
        return data['openai_api_configured']
    except Exception as e:
        print(f"❌ エラー: {e}")
        return False

def test_suggest_tags():
    """タグ提案のテスト"""
    print("\n🏷️  タグ提案テスト...")
    
    test_data = {
        "title": "Pythonの非同期プログラミング入門",
        "url": "https://example.com/python-async",
        "excerpt": "asyncioを使った非同期処理の基礎を学ぶ",
        "existing_tags": [
            "Python",
            "プログラミング",
            "AI",
            "Web開発",
            "データ分析",
            "JavaScript",
            "デザイン"
        ]
    }
    
    try:
        print(f"📝 入力:")
        print(f"  タイトル: {test_data['title']}")
        print(f"  既存タグ: {', '.join(test_data['existing_tags'])}")
        
        response = requests.post(
            f"{BASE_URL}/suggest-tags",
            json=test_data,
            headers={"Content-Type": "application/json"},
            timeout=30
        )
        
        if response.status_code == 200:
            data = response.json()
            print(f"\n✅ 提案成功:")
            print(f"  提案タグ: {', '.join(data['suggested_tags'])}")
            print(f"  理由: {data.get('reasoning', 'なし')}")
        else:
            print(f"\n❌ エラー: {response.status_code}")
            print(f"  詳細: {response.text}")
            
    except Exception as e:
        print(f"❌ エラー: {e}")

def main():
    print("=" * 60)
    print("🧪 タグ自動提案API テストスクリプト")
    print("=" * 60)
    
    # ヘルスチェック
    api_ready = test_health_check()
    
    if not api_ready:
        print("\n⚠️  OpenAI API キーが設定されていません")
        print("💡 .envファイルにOPENAI_API_KEYを設定してください")
        return
    
    # タグ提案テスト
    test_suggest_tags()
    
    print("\n" + "=" * 60)
    print("✅ テスト完了")
    print("=" * 60)

if __name__ == "__main__":
    main()
