-- users.created_at を docs/model/model.md に合わせて not null default now() にする。
-- gorm AutoMigrate は default/not null を付けないため SQL マイグレーションで補う。
-- 冪等に書く（再適用しても安全）。

alter table users alter column created_at set default now();
update users set created_at = now() where created_at is null;
alter table users alter column created_at set not null;
