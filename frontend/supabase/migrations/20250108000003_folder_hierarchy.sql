-- フォルダ階層構造対応
-- parent_idカラムを追加して自己参照可能にする

ALTER TABLE folders 
ADD COLUMN parent_id UUID REFERENCES folders(id) ON DELETE CASCADE;

-- インデックスを追加
CREATE INDEX idx_folders_parent ON folders(parent_id);

-- 表示順序用のカラムも追加（オプション）
ALTER TABLE folders 
ADD COLUMN sort_order INTEGER DEFAULT 0;

COMMENT ON COLUMN folders.parent_id IS '親フォルダのID。NULLの場合はルートフォルダ';
COMMENT ON COLUMN folders.sort_order IS 'フォルダの表示順序';
