-- Remove estimated_minutes, content_type, due_at from bookmarks
ALTER TABLE bookmarks DROP COLUMN IF EXISTS estimated_minutes;
ALTER TABLE bookmarks DROP COLUMN IF EXISTS content_type;
ALTER TABLE bookmarks DROP COLUMN IF EXISTS due_at;
-- Remove related index if exists
DROP INDEX IF EXISTS idx_bookmarks_due_at;