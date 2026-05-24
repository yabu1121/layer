-- blocks（US-A7）の外部キー。ユーザー削除時はブロック行も消える（on delete cascade）。
-- 005/006 と同様、AutoMigrate は FK を生成しないため SQL で補う（冪等）。

-- 孤児行のクリーンアップ（新規 DB では 0 件）。
delete from blocks b
 where not exists (select 1 from users u where u.id = b.blocker_id)
    or not exists (select 1 from users u where u.id = b.blocked_id);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'fk_blocks_blocker') then
    alter table blocks add constraint fk_blocks_blocker
      foreign key (blocker_id) references users(id) on delete cascade;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_blocks_blocked') then
    alter table blocks add constraint fk_blocks_blocked
      foreign key (blocked_id) references users(id) on delete cascade;
  end if;
end $$;
