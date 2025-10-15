-- ===== Tags Table =====
CREATE TABLE IF NOT EXISTS tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== Folders Table =====
CREATE TABLE IF NOT EXISTS folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== Bookmarks Table =====
CREATE TABLE IF NOT EXISTS bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  excerpt TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  is_pinned BOOLEAN DEFAULT FALSE,
  is_archived BOOLEAN DEFAULT FALSE,
  estimated_minutes INTEGER NOT NULL DEFAULT 5,
  content_type TEXT NOT NULL DEFAULT 'article',
  due_at TIMESTAMPTZ,
  folder_id UUID REFERENCES folders(id) ON DELETE SET NULL,
  open_count INTEGER DEFAULT 0,
  last_opened_at TIMESTAMPTZ
);

-- ===== Bookmark-Tag Junction Table (Many-to-Many) =====
CREATE TABLE IF NOT EXISTS bookmark_tags (
  bookmark_id UUID REFERENCES bookmarks(id) ON DELETE CASCADE,
  tag_id UUID REFERENCES tags(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (bookmark_id, tag_id)
);

-- ===== Indexes =====
CREATE INDEX IF NOT EXISTS idx_bookmarks_folder ON bookmarks(folder_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_due_at ON bookmarks(due_at);
CREATE INDEX IF NOT EXISTS idx_bookmarks_created_at ON bookmarks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookmarks_open_count ON bookmarks(open_count DESC);
CREATE INDEX IF NOT EXISTS idx_bookmark_tags_bookmark ON bookmark_tags(bookmark_id);
CREATE INDEX IF NOT EXISTS idx_bookmark_tags_tag ON bookmark_tags(tag_id);

-- ===== Row Level Security (RLS) =====
-- 注意: 本番環境では認証を実装してください
-- 開発中は全てのデータにアクセス可能にする設定

ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookmark_tags ENABLE ROW LEVEL SECURITY;

-- 開発用: 全てのユーザーがアクセス可能（本番環境では削除してください）
CREATE POLICY "Enable all access for tags" ON tags FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Enable all access for folders" ON folders FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Enable all access for bookmarks" ON bookmarks FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Enable all access for bookmark_tags" ON bookmark_tags FOR ALL USING (true) WITH CHECK (true);
