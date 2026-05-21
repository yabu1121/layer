-- pins テーブルを docs/model/model.md §2 に整合させる。
--   * 位置を緯度経度の数値カラムから PostGIS の geography(point,4326) へ移行（⚠️破壊的: lat/lng 削除）
--   * created_at を not null default now() に揃える
--
-- AutoMigrate（database.Migrate）→ MigrateSQL の順で走るため、既存 dev DB
-- （lat/lng あり）と新規 DB（lat/lng なし）の双方で安全に動くよう if (not) exists で
-- 冪等に書く。既存データは破棄せず lat/lng から location へ保全移送する。

alter table pins add column if not exists location geography(point, 4326);

-- 旧スキーマ（lat/lng カラムあり）の行のみ location へ保全移送する。
-- 新規 DB には lat/lng が無いため DO ブロックの分岐で参照を回避する
-- （plpgsql は到達した文だけを遅延パースするので未到達なら列不在でもエラーにならない）。
do $$
begin
  if exists (
        select 1 from information_schema.columns
        where table_name = 'pins' and column_name = 'lat'
      ) and exists (
        select 1 from information_schema.columns
        where table_name = 'pins' and column_name = 'lng'
      ) then
    update pins
       set location = st_setsrid(st_makepoint(lng, lat), 4326)::geography
     where location is null;
  end if;
end $$;

alter table pins alter column location set not null;

alter table pins drop column if exists lat;
alter table pins drop column if exists lng;

-- created_at を model.md §2 に合わせる（gorm AutoMigrate は default/not null を付けない）。
alter table pins alter column created_at set default now();
update pins set created_at = now() where created_at is null;
alter table pins alter column created_at set not null;

create index if not exists pins_location_gist on pins using gist (location);
