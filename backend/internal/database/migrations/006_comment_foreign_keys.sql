-- comments テーブル（US-C3）に外部キー制約を追加する。
-- 005 と同様、AutoMigrate は FK を生成しないため SQL マイグレーションで補う。
-- 再適用しても安全なよう、孤児行を掃除してから pg_constraint を見て未作成のみ張る。
--
-- comments.pin_id は on delete cascade（Pin 削除時にコメントも消える。pin.Delete が
-- 依存）。comments.user_id は reactions.user_id と同様 cascade なし。

-- 1. 孤児行のクリーンアップ（親が無いコメントは不整合データ。新規 DB では 0 件）。
delete from comments c
 where not exists (select 1 from pins  p where p.id = c.pin_id)
    or not exists (select 1 from users u where u.id = c.user_id);

-- 2. 外部キー制約の追加（pg_constraint に無いものだけ張る）。
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'fk_comments_pin') then
    alter table comments add constraint fk_comments_pin
      foreign key (pin_id) references pins(id) on delete cascade;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_comments_user') then
    alter table comments add constraint fk_comments_user
      foreign key (user_id) references users(id);
  end if;
end $$;
