-- 発見検知トリガー（docs/model/model.md §4 / 要件 FR-6.3・コア体験）。
-- pins への INSERT 後に発火し、新規 Pin の半径 20m 以内にある「友達（accepted）の Pin」を
-- 検出して pin_discoveries を記録し、双方向の discovery 通知を作る。
--
-- 友達以外への露出ゼロ（非機能要件 6.2）のため「自分以外」ではなく「友達」限定で抽出する。
-- friendships / users を横断参照するため security definer で動かす。冪等に書く。

create or replace function detect_discoveries()
returns trigger
language plpgsql
security definer
as $$
declare
  new_user  users%rowtype;
  owner_rec record;
begin
  select * into new_user from users where id = new.user_id;

  -- 1+2: 20m 以内の友達の Pin ごとに発見ログを記録する（既存 Pin の件数ぶん）。
  insert into pin_discoveries (user_id, pin_id, triggered_by)
  select new.user_id, p.id, new.id
  from pins p
  where p.user_id <> new.user_id
    and st_dwithin(p.location, new.location, 20)
    and exists (
      select 1 from friendships f
      where f.status = 'accepted'
        and ((f.requester_id = new.user_id and f.receiver_id = p.user_id)
          or (f.requester_id = p.user_id  and f.receiver_id = new.user_id))
    );

  -- 3: 既存 Pin の持ち主ごとに集約し、通知を 2 通（持ち主宛 / 新規投稿者宛）作る。
  for owner_rec in
    select p.user_id as owner_id,
           (array_agg(p.id   order by p.created_at desc))[1] as rep_pin_id,
           (array_agg(p.body order by p.created_at desc))[1] as rep_body
    from pins p
    where p.user_id <> new.user_id
      and st_dwithin(p.location, new.location, 20)
      and exists (
        select 1 from friendships f
        where f.status = 'accepted'
          and ((f.requester_id = new.user_id and f.receiver_id = p.user_id)
            or (f.requester_id = p.user_id  and f.receiver_id = new.user_id))
      )
    group by p.user_id
  loop
    -- 既存 Pin の持ち主宛: 「<新規投稿者> が同じ場所に Pin を立てた」
    insert into notifications (user_id, kind, payload)
    values (
      owner_rec.owner_id,
      'discovery',
      jsonb_build_object(
        'userId',      new_user.id,
        'displayName', new_user.display_name,
        'icon',        new_user.icon,
        'pinId',       new.id,
        'body',        left(new.body, 50)
      )
    );

    -- 新規投稿者宛: 「あなたは <持ち主> と同じ場所で重なった」
    insert into notifications (user_id, kind, payload)
    select
      new.user_id,
      'discovery',
      jsonb_build_object(
        'userId',      u.id,
        'displayName', u.display_name,
        'icon',        u.icon,
        'pinId',       owner_rec.rep_pin_id,
        'body',        left(owner_rec.rep_body, 50)
      )
    from users u
    where u.id = owner_rec.owner_id;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_detect_discoveries on pins;
create trigger trg_detect_discoveries
after insert on pins
for each row execute function detect_discoveries();
