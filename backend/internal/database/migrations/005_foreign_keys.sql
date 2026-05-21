-- 全テーブルに docs/model/model.md §2 が定義する外部キー制約を追加する（issue #47）。
-- gorm の AutoMigrate は association 未定義のため FK を 1 つも生成しない。PostGIS や
-- 発見検知トリガーと同様、AutoMigrate で表現できないものは SQL マイグレーションで補う。
-- 再適用しても安全なよう、pg_constraint を見て未作成のものだけ追加する（冪等）。
--
-- ⚠️ 破壊的: 既存 dev DB に「親が存在しない孤児行」があると FK 追加が失敗するため、
-- 各制約を付ける前に孤児行を DELETE する。孤児行は参照先を失った不整合データであり
-- 本来存在してはならない。新規 DB では DELETE 対象は 0 件。
-- pins を先に掃除すると、それに紐づく reactions / pin_discoveries も孤児になりうるため
-- pins → その子（reactions, pin_discoveries）の順で削除する。

-- 1. 孤児行のクリーンアップ（削除順に注意: 親側 pins を先に掃除する）。
delete from pins p
 where not exists (select 1 from users u where u.id = p.user_id);

delete from reactions r
 where not exists (select 1 from pins  p where p.id = r.pin_id)
    or not exists (select 1 from users u where u.id = r.user_id);

delete from pin_discoveries d
 where not exists (select 1 from users u where u.id = d.user_id)
    or not exists (select 1 from pins  p where p.id = d.pin_id)
    or not exists (select 1 from pins  p where p.id = d.triggered_by);

delete from friendships f
 where not exists (select 1 from users u where u.id = f.requester_id)
    or not exists (select 1 from users u where u.id = f.receiver_id);

delete from notifications n
 where not exists (select 1 from users u where u.id = n.user_id);

-- 2. 外部キー制約の追加（pg_constraint に無いものだけ張る）。
--    on delete cascade は model.md §2 が明記する reactions.pin_id のみ。
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'fk_pins_user') then
    alter table pins add constraint fk_pins_user
      foreign key (user_id) references users(id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_reactions_pin') then
    alter table reactions add constraint fk_reactions_pin
      foreign key (pin_id) references pins(id) on delete cascade;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_reactions_user') then
    alter table reactions add constraint fk_reactions_user
      foreign key (user_id) references users(id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_pin_discoveries_user') then
    alter table pin_discoveries add constraint fk_pin_discoveries_user
      foreign key (user_id) references users(id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_pin_discoveries_pin') then
    alter table pin_discoveries add constraint fk_pin_discoveries_pin
      foreign key (pin_id) references pins(id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_pin_discoveries_triggered_by') then
    alter table pin_discoveries add constraint fk_pin_discoveries_triggered_by
      foreign key (triggered_by) references pins(id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_friendships_requester') then
    alter table friendships add constraint fk_friendships_requester
      foreign key (requester_id) references users(id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_friendships_receiver') then
    alter table friendships add constraint fk_friendships_receiver
      foreign key (receiver_id) references users(id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'fk_notifications_user') then
    alter table notifications add constraint fk_notifications_user
      foreign key (user_id) references users(id);
  end if;
end $$;
