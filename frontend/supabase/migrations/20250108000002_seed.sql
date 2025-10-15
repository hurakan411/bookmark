-- ===== Sample Seed Data =====
-- このファイルは開発用のサンプルデータです

-- Tags
INSERT INTO tags (id, name) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Swift'),
  ('22222222-2222-2222-2222-222222222222', 'AI'),
  ('33333333-3333-3333-3333-333333333333', 'Design')
ON CONFLICT (name) DO NOTHING;

-- Folders
INSERT INTO folders (id, name) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'あとで読む'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '技術'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'デザイン')
ON CONFLICT DO NOTHING;

-- Bookmarks
INSERT INTO bookmarks (id, url, title, excerpt, estimated_minutes, content_type, folder_id, due_at, open_count, is_pinned) VALUES
  (
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'https://example.com/swiftdata',
    'SwiftData入門',
    'SwiftDataの基本的な使い方を解説。Core Dataの後継として注目されています。',
    8,
    'article',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    NOW() + INTERVAL '1 day',
    5,
    true
  ),
  (
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    'https://example.com/prompt',
    'LLMプロンプト設計',
    'ChatGPTやClaude等のLLMを使った効果的なプロンプト設計のベストプラクティス。',
    12,
    'article',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    NOW() + INTERVAL '3 days',
    3,
    false
  ),
  (
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
    'https://example.com/colors',
    '配色の基本',
    'デザイナー必見！色彩理論とUI/UXデザインにおける配色のポイント。',
    6,
    'article',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    NOW(),
    7,
    true
  ),
  (
    '10101010-1010-1010-1010-101010101010',
    'https://example.com/visionos',
    'VisionOSガイド',
    'AppleのVision Proで動くアプリ開発の完全ガイド。SwiftUIとRealityKitを使った3D UI実装。',
    18,
    'video',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    NULL,
    0,
    false
  )
ON CONFLICT DO NOTHING;

-- Bookmark-Tag relationships
INSERT INTO bookmark_tags (bookmark_id, tag_id) VALUES
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '11111111-1111-1111-1111-111111111111'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222'),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', '33333333-3333-3333-3333-333333333333'),
  ('10101010-1010-1010-1010-101010101010', '11111111-1111-1111-1111-111111111111'),
  ('10101010-1010-1010-1010-101010101010', '33333333-3333-3333-3333-333333333333')
ON CONFLICT DO NOTHING;
