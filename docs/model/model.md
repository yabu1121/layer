# Layer データモデル定義

> `docs/require.md`（要件定義）から分離したデータモデルの単一ソース。
> テーブル DDL を変更したら、このファイルを必ず更新すること。

関連: [要件定義](../require.md) / [画面設計](../design/screens.md)

---

## 1. ER 概要

```
users        ─ 1:N ─ pins ─ 1:N ─ reactions
  │                    │
  │                    └ 1:N ─ pin_discoveries
  │
  ├─ M:N ─ friendships ─ M:N ─ users
  │
  └─ 1:N ─ notifications
```

---

## 2. テーブル定義

### users

```sql
create table users (
  id            uuid primary key default gen_random_uuid(),
  user_id       text unique not null,       -- 表示・検索用ハンドル
  display_name  text not null,
  icon          text,                        -- 絵文字 or 画像 URL
  auth_provider text not null,               -- 'google'
  auth_uid      text unique not null,        -- Google の sub
  created_at    timestamptz not null default now()
);
```

### friendships

```sql
create table friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references users(id),
  receiver_id  uuid not null references users(id),
  status       text not null check (status in ('pending','accepted','rejected')),
  created_at   timestamptz not null default now(),
  accepted_at  timestamptz,
  unique (requester_id, receiver_id)
);

create index on friendships (receiver_id, status);
create index on friendships (requester_id, status);
```

> **既知の制約（要件 D3 / MVP では許容）**
> - `unique (requester_id, receiver_id)` は **方向付き**。A→B と B→A の2行が同時に存在しうる（双方向の重複申請）。MVP では検索 UI で「既に友達／申請中」を表示して実質的に防ぐ。
> - `rejected` 後の再申請は同じ行の `status` を `pending` に更新して再利用する（新規 INSERT は unique 制約で失敗するため）。
> - 公開リリース時には「ユーザーペアを正規化した1行で持つ」設計への変更を検討する。

### pins

```sql
create extension if not exists postgis;

create table pins (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users(id),
  body       text not null,                              -- 200 文字制限はクライアント側
  location   geography(point, 4326) not null,            -- 緯度経度
  created_at timestamptz not null default now()
);

create index on pins (user_id);
create index on pins using gist (location);              -- 地理空間インデックス
```

> **将来拡張の予約（要件 §9）**: 感情ラベル（US-B4）や写真添付（US-B3）は MVP 対象外のためカラムを持たない。
> 導入時は `emotion text` / `image_url text` を追加する想定。

### reactions

```sql
create table reactions (
  id         uuid primary key default gen_random_uuid(),
  pin_id     uuid not null references pins(id) on delete cascade,
  user_id    uuid not null references users(id),
  kind       text not null default 'wakaru',
  created_at timestamptz not null default now(),
  unique (pin_id, user_id, kind)
);

create index on reactions (pin_id);
create index on reactions (user_id);
```

### pin_discoveries（発見ログ）

```sql
create table pin_discoveries (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users(id),      -- 発見した側
  pin_id       uuid not null references pins(id),       -- 発見された Pin
  triggered_by uuid not null references pins(id),       -- きっかけになった Pin
  created_at   timestamptz not null default now(),
  unique (user_id, pin_id, triggered_by)
);

create index on pin_discoveries (user_id);
```

### notifications

```sql
create table notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users(id),
  kind       text not null check (kind in (
               'friend_request',
               'friend_accepted',
               'reaction',
               'discovery'
             )),
  payload    jsonb not null,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

create index on notifications (user_id, created_at desc);
create index on notifications (user_id) where read_at is null;
```

---

## 3. RPC・主要クエリ

### 3.1 `get_visible_pins` — 自分＋友達の Pin 取得（RPC）

地図（MapScreen）が呼び出す RPC。要件 FR-4.2 に対応。

```sql
create or replace function get_visible_pins(me uuid)
returns setof pins
language sql stable
as $$
  with my_friends as (
    select case
      when requester_id = me then receiver_id
      else requester_id
    end as friend_id
    from friendships
    where status = 'accepted'
      and (requester_id = me or receiver_id = me)
  )
  select p.*
  from pins p
  where p.user_id = me
     or p.user_id in (select friend_id from my_friends);
$$;
```

> クライアントは `users` を別途 join するか、戻り値型を投稿者情報込みのビューに拡張する。

### 3.2 同じ場所の Pin を取得（PinDetailScreen 用）

要件 FR-5.2「同じ場所（半径 20m 以内）の他の Pin」に対応。

```sql
select p.*, u.display_name, u.icon
from pins p
join users u on u.id = p.user_id
where ST_DWithin(
  p.location,
  ST_MakePoint($lng, $lat)::geography,
  20
)
order by p.created_at desc;
```

---

## 4. 発見検知トリガー

要件 FR-6.3 / コア体験。`pins` への INSERT 後に発火する PL/pgSQL トリガー関数として実装する。

**ロジック概要**:

1. 新しい Pin の半径 **20m 以内**にある Pin のうち、**投稿者が自分の友達**（`friendships.status = 'accepted'`）であるものを抽出する。
   - ⚠️ 「自分以外」ではなく **「友達」限定**。非機能要件 6.2「友達以外への露出ゼロ」に従う。
2. 該当 Pin ごとに `pin_discoveries` を INSERT する（`user_id` = 新規投稿者、`pin_id` = 既存 Pin、`triggered_by` = 新規 Pin）。
3. `notifications` を **2通** INSERT する（要件 A4 の宛先定義）:

   | 宛先 | `kind` | payload の文意 | 対応要件 |
   |---|---|---|---|
   | 既存 Pin の持ち主 | `discovery` | 「<新規投稿者> があなたと同じ場所に Pin を立てました」 | FR-6.3 |
   | 新規投稿者 | `discovery` | 「あなたは <既存 Pin の持ち主> と同じ場所で重なりました」 | コア体験（発見の可視化） |

> 既存 Pin が複数あれば、その件数ぶん `pin_discoveries` を INSERT し、通知は「持ち主ごと」に集約してよい。

---

## 5. RLS（Row Level Security）方針

要件 6.2「友達以外への露出ゼロ（DB レベルで保証）」に対応。**付録の「最低限設定」だけでは不十分**で、友達関係を引く関数が必要。

### 5.1 friendship 判定関数

```sql
create or replace function is_friend(viewer uuid, owner uuid)
returns boolean
language sql stable security definer
as $$
  select exists (
    select 1 from friendships
    where status = 'accepted'
      and ((requester_id = viewer and receiver_id = owner)
        or (requester_id = owner  and receiver_id = viewer))
  );
$$;
```

### 5.2 各テーブルのポリシー方針

| テーブル | SELECT | INSERT / UPDATE / DELETE |
|---|---|---|
| `users` | 認証ユーザーは閲覧可（検索のため） | 自分の行のみ |
| `pins` | `user_id = auth.uid()` **または** `is_friend(auth.uid(), user_id)` | 自分の行のみ INSERT |
| `reactions` | 対象 Pin が SELECT 可能なら閲覧可 | 自分の行のみ |
| `friendships` | 自分が当事者の行のみ | requester は INSERT、receiver は status 更新 |
| `notifications` | `user_id = auth.uid()` のみ | クライアントからの INSERT は不可（トリガー経由のみ） |

> 発見検知トリガーは `security definer` で動かし、RLS を越えて他ユーザーの `notifications` / `pin_discoveries` に INSERT できるようにする。

---

## 6. 変更履歴

- 2026-05-19: 要件定義ドキュメント（require.md §8）から分離して新規作成。`get_visible_pins` RPC・RLS 方針・friendships のエッジケース注記を追加。
