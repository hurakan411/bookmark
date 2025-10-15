-- usersテーブルを作成
create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  created_at timestamp with time zone default now(),
  last_active_at timestamp with time zone default now(),
  device_info text
);

-- インデックス
create index if not exists idx_users_created_at on users(created_at);

-- 既存テーブルにuser_idカラムを追加
alter table bookmarks add column if not exists user_id uuid references users(id) on delete cascade;
alter table folders add column if not exists user_id uuid references users(id) on delete cascade;
alter table tags add column if not exists user_id uuid references users(id) on delete cascade;

-- インデックスを追加
create index if not exists idx_bookmarks_user_id on bookmarks(user_id);
create index if not exists idx_folders_user_id on folders(user_id);
create index if not exists idx_tags_user_id on tags(user_id);
