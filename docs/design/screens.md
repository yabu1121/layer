# Layer 画面設計・状態遷移ドキュメント

> `docs/require.md`（要件定義）から分離した画面設計の単一ソース。
> 全 9 画面のレイアウト・State 実装と、状態遷移を記述する。

関連: [要件定義](../require.md) / [データモデル](../model/model.md)

---

## 1. 画面一覧

全 9 画面。各画面について「役割 / レイアウト / State / 操作 / 遷移 / エラー」の順で記述。

1. SplashScreen
2. SignInScreen
3. OnboardingScreen
4. MapScreen（メイン）
5. PinComposeScreen
6. PinDetailScreen（発見の核）
7. NotificationsScreen
8. FriendsScreen
9. ProfileScreen

---

## 2. 画面詳細

### 2.1 SplashScreen

**役割**: 起動時に認証状態をチェックし、適切な画面に振り分ける。

**レイアウト**: 中央にロゴ、下に小さなローディングインジケータ。

**State**:

```dart
@riverpod
class SplashController extends _$SplashController {
  @override
  Future<AuthCheckResult> build() async {
    final session = supabase.auth.currentSession;
    if (session == null) return AuthCheckResult.unauthenticated;

    final hasProfile = await _checkProfileExists(session.user.id);
    return hasProfile
      ? AuthCheckResult.ready
      : AuthCheckResult.needsOnboarding;
  }
}
```

**操作**: 自動。認証状態をチェックして 1 秒以内に遷移。

**遷移先**:
- 未認証 → SignInScreen
- 認証済 / プロフィール無 → OnboardingScreen
- 認証済 / プロフィール有 → MapScreen

**エラー・空状態**: ネットワークエラー → 「再試行」ボタン。

---

### 2.2 SignInScreen

**役割**: Google アカウントでサインインする。

**レイアウト**:

```
┌────────────────────────┐
│                          │
│         Layer            │
│                          │
│  舞台はタイムラインから、 │
│      世界へ。            │
│                          │
│  [G  Google でサインイン] │
│                          │
│  利用規約とプライバシー   │
│  ポリシーに同意します     │
└────────────────────────┘
```

**State**:

```dart
@riverpod
class SignInController extends _$SignInController {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await supabase.auth.signInWithOAuth(OAuthProvider.google);
    });
  }
}
```

**操作**: Google サインインボタンタップ → OAuth フロー → 成功 → SplashScreen に戻り再判定。

**遷移先**: SplashScreen 経由で Onboarding or Map。

**エラー・空状態**: サインイン失敗 → スナックバーで再試行を促す。

---

### 2.3 OnboardingScreen

**役割**: 初回プロフィール（ユーザー名・アイコン）設定。1 画面で完結する。

**レイアウト**:

```
┌────────────────────────┐
│  プロフィール設定        │
├────────────────────────┤
│                          │
│  あなたのことを          │
│  教えてください          │
│                          │
│  名前                    │
│  [リョウ              ]  │
│                          │
│  アイコン                │
│  [😎 😊 🌸 🍀 ⭐ 🎵 ...]│
│                          │
│  ユーザー ID             │
│  @ [riyo_1234        ]  │
│                          │
│  [はじめる]              │
└────────────────────────┘
```

**State**:

```dart
@riverpod
class OnboardingController extends _$OnboardingController {
  @override
  OnboardingFormState build() => OnboardingFormState(
    displayName: '',
    icon: '😊',
    userId: _generateRandomUserId(),
  );

  void updateDisplayName(String name) { ... }
  void updateIcon(String icon) { ... }
  void updateUserId(String userId) { ... }

  Future<void> submit() async {
    if (!_validate()) return;
    await supabase.from('users').insert({...});
    // → MapScreen へ
  }
}
```

**操作**: 各フィールド入力 → 「はじめる」 → バリデーション → DB 登録 → MapScreen。

**バリデーション**:
- 名前: 1〜20 文字
- ユーザー ID: 3〜20 文字、英数字とアンダースコア、重複チェック（送信時）
- アイコン: 1 つ選択必須

**遷移先**: 成功 → MapScreen。重複 → エラー表示。

---

### 2.4 MapScreen（メイン）

**役割**: 地図と Pin を表示するアプリの中心画面。

**レイアウト**:

```
┌────────────────────────┐
│ Layer                🔔3│  ← 通知バッジ
├────────────────────────┤
│                          │
│   ┌─地図エリア──┐        │
│   │  📍リョウ     │        │
│   │  📍📍アヤ     │        │
│   │  ❹            │  ← クラスタ表示
│   │       [現在地] │        │
│   └──────────────┘        │
│                    ( + )│  ← FAB
├────────────────────────┤
│ 🗺️地図  🔔通知  👤自分  │
└────────────────────────┘
```

**State**:

```dart
@riverpod
class MapController extends _$MapController {
  @override
  Future<MapState> build() async {
    final pins = await _fetchVisiblePins();
    final currentLocation = await _getCurrentLocation();
    return MapState(
      pins: pins,
      currentLocation: currentLocation,
      selectedPinId: null,
    );
  }

  Future<List<Pin>> _fetchVisiblePins() async {
    final myId = supabase.auth.currentUser!.id;
    // RPC 定義は model.md §3.1 を参照
    return await supabase.rpc('get_visible_pins', params: {'me': myId});
  }

  void selectPin(String pinId) { ... }
  Future<void> refreshPins() async { ... }
}
```

**操作**:
- パン・ズーム（Google Maps のジェスチャ）
- Pin タップ → PinDetailScreen をボトムシートで表示
- FAB タップ → PinComposeScreen へモーダル遷移
- 現在地ボタン → 自分の現在地へカメラ移動
- 通知バッジタップ → NotificationsScreen
- ボトムタブ切り替え

**表示ロジック**:
- 自分の Pin: 青いピン、自分のアイコン
- 友達の Pin: オレンジ、相手のアイコン
- 同じ場所（半径 20m）に複数: クラスタ表示、数字バッジ
- 通知バッジ: 未読数、0 件なら非表示

**遷移先**: PinDetail / PinCompose / Notifications / Profile。

**エラー・空状態**:
- 位置情報拒否 → 「位置情報を許可すると地図が表示されます」+ 設定アプリへのリンク
- Pin がまだ無い → 「最初の Pin を立ててみよう！」と FAB を強調
- ネットワークエラー → リトライボタン

---

### 2.5 PinComposeScreen

**役割**: 新しい Pin を投稿する。

**レイアウト**:

```
┌────────────────────────┐
│ [×]  Pin を立てる  [投稿]│
├────────────────────────┤
│                          │
│  ┌─ミニ地図──────┐       │
│  │   📍           │       │
│  └──────────────┘       │
│  📍 新宿御苑              │
│  [位置を調整]             │
│                          │
│  ┌──────────────────────┐│
│  │ ここで感じたこと...    ││
│  └──────────────────────┘│
│  あと 195 文字            │
└────────────────────────┘
```

**State**:

```dart
@riverpod
class PinComposeController extends _$PinComposeController {
  @override
  PinComposeState build() => PinComposeState(
    location: null,
    locationLabel: null,
    body: '',
    isSubmitting: false,
  );

  Future<void> initializeLocation() async {
    final pos = await Geolocator.getCurrentPosition();
    final label = await _reverseGeocode(pos);
    state = state.copyWith(
      location: pos,
      locationLabel: label,
    );
  }

  void updateBody(String body) {
    state = state.copyWith(body: body);
  }

  void updateLocation(LatLng newLocation) async {
    state = state.copyWith(location: newLocation);
    final label = await _reverseGeocode(newLocation);
    state = state.copyWith(locationLabel: label);
  }

  Future<bool> submit() async {
    if (!_validate()) return false;
    state = state.copyWith(isSubmitting: true);
    try {
      await supabase.from('pins').insert({
        'body': state.body,
        'location': 'POINT(${state.location.lng} ${state.location.lat})',
      });
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false);
      return false;
    }
  }
}
```

> `_reverseGeocode` は `geocoding` パッケージ（または Google Geocoding API）で実装する。`google_maps_flutter` 単体では逆ジオコーディングできない（要件 §7.1 / 付録B 参照）。

**操作**:
- 起動時に自動で現在地取得
- ミニ地図のピンをドラッグで微調整
- テキスト入力
- 投稿ボタン → DB 登録 → 成功 → MapScreen に戻る

**バリデーション**:
- 本文: 1〜200 文字
- 位置: 必須

**遷移先**: 成功 → MapScreen。キャンセル → 確認ダイアログ。

**エラー・空状態**:
- 位置取得失敗 → オーバーレイで許可を促す
- 投稿失敗 → スナックバー

---

### 2.6 PinDetailScreen（発見の核）

**役割**: 地図ピンタップで開くボトムシート。「自分の Pin の下に同じ場所の他の Pin が並ぶ」ことで発見が成立する。**MVP で最も重要な画面**。

**レイアウト**:

```
┌──────────────────────────┐
│         ━━━━━              │
│ 📍 新宿御苑                 │
│ Pin 4 件                   │
├──────────────────────────┤
│                            │
│ 😎 リョウ      2 時間前      │
│ @riyo_1234                 │
│                            │
│ ここの芝生で本読むの最高     │
│                            │
│ [💛 わかる]  3              │
│                            │
├──────────────────────────┤
│ ─── 同じ場所の Pin ───      │
│                            │
│ 🌸 アヤ        1 週間前      │
│ 桜の季節また来たい           │
│ [💛 わかる]  5              │
│                            │
│ 🍀 ケン        1 ヶ月前      │
│ 散歩コースに最高             │
│ [✓ わかる済み]  2           │
└──────────────────────────┘
```

**State**:

```dart
@riverpod
class PinDetailController extends _$PinDetailController {
  @override
  Future<PinDetailState> build(String pinId) async {
    final pin = await _fetchPin(pinId);
    final nearbyPins = await _fetchNearbyPins(pin.location, excludeId: pinId);
    final reactions = await _fetchReactions(pinId);
    return PinDetailState(
      pin: pin,
      nearbyPins: nearbyPins,
      reactions: reactions,
      isMyReactionSent: reactions.any((r) => r.userId == _myId),
    );
  }

  Future<void> toggleReaction(String targetPinId) async {
    // 楽観的更新
    state = AsyncValue.data(state.value!.toggleReaction(targetPinId, _myId));
    try {
      if (_alreadyReacted(targetPinId)) {
        await supabase.from('reactions')
          .delete()
          .match({'pin_id': targetPinId, 'user_id': _myId});
      } else {
        await supabase.from('reactions').insert({
          'pin_id': targetPinId,
          'user_id': _myId,
          'kind': 'wakaru',
        });
      }
    } catch (e) {
      state = AsyncValue.data(state.value!.toggleReaction(targetPinId, _myId));
      _showError();
    }
  }
}
```

**操作**:
- ドラッグで全画面化・折りたたみ・閉じる
- 「わかる」ボタンタップ → トグル（押す/取り消し）
- 他の Pin タップ → そのピンを中心に詳細を再表示

**表示ロジック**:
- メイン Pin を上部に大きく
- その下に `nearbyPins`（半径 20m 以内、メイン以外）を新しい順
- 「わかる」ボタンの状態:
  - 未押下: `[💛 わかる] 3`（他の人の数）
  - 押下済: `[✓ わかる済み] 4`（自分も含む数、色変化）
- 場所ラベルは逆ジオコーディング（`geocoding` パッケージ / Google Geocoding API）

**遷移先**: 閉じる → MapScreen / 別の Pin → 同画面で内容差し替え。

**エラー・空状態**:
- 同じ場所に他の Pin が無い → 「ここではまだあなただけです」
- 共感送信失敗 → スナックバー + ロールバック

---

### 2.7 NotificationsScreen

**役割**: 3 種類の通知（発見・共感・友達申請）を時系列で表示。発見通知を最も目立たせる。

**レイアウト**:

```
┌──────────────────────────┐
│ [←]  お知らせ             │
├──────────────────────────┤
│ ┌──────────────────────┐  │
│ │ 🎯 発見                │  │ ← 強調カラー
│ │ アヤがあなたと同じ場所に│  │
│ │ Pin を立てました        │  │
│ │ 📍 新宿御苑  3 時間前   │  │
│ └──────────────────────┘  │
│ ┌──────────────────────┐  │
│ │ 💛 共感                │  │
│ │ ケンがあなたの Pin に  │  │
│ │ 「わかる」を押しました │  │
│ └──────────────────────┘  │
│ ┌──────────────────────┐  │
│ │ 👋 友達申請            │  │
│ │ サキから申請が届きました│  │
│ │ [承認] [拒否]          │  │
│ └──────────────────────┘  │
└──────────────────────────┘
```

**State**:

```dart
@riverpod
class NotificationsController extends _$NotificationsController {
  @override
  Future<List<NotificationItem>> build() async {
    final items = await supabase
      .from('notifications')
      .select()
      .order('created_at', ascending: false)
      .limit(50);

    _markAllAsRead();

    return items.map(NotificationItem.fromJson).toList();
  }

  Future<void> _markAllAsRead() async {
    await supabase
      .from('notifications')
      .update({'read_at': DateTime.now().toIso8601String()})
      .filter('read_at', 'is', null);
  }

  Future<void> acceptFriendRequest(String friendshipId) async { ... }
  Future<void> rejectFriendRequest(String friendshipId) async { ... }
  Future<void> openNotification(NotificationItem item) async {
    // 種類に応じて遷移
  }
}
```

**操作**:
- 画面開いた瞬間に未読 → 既読化
- 通知タップ:
  - 発見通知 → 関連 Pin の PinDetailScreen を自動展開
  - 共感通知 → 自分の Pin の PinDetailScreen
  - 友達申請 → 承認/拒否ボタンで操作
- インラインで承認/拒否

**表示ロジック**:
- 種別ごとにアイコン・カラーを切り替え
- 既読/未読の視覚的区別（未読は背景色淡）
- 24 時間以内: 「3 時間前」 / それ以降: 「7/15」

**遷移先**: MapScreen + PinDetail / 通知から該当画面へ。

**エラー・空状態**:
- 通知ゼロ → 「まだお知らせはありません」+ イラスト
- 取得失敗 → リトライ

---

### 2.8 FriendsScreen

**役割**: 友達検索・申請・承認・一覧管理。

**レイアウト**:

```
┌──────────────────────────┐
│ [←]  友達                  │
├──────────────────────────┤
│ [🔍 @ユーザーID を入力]    │
│                            │
│  ┌─検索結果────────────┐  │
│  │ 🌸 アヤ              │  │
│  │ @aya_9999            │  │
│  │ [友達申請]            │  │
│  └────────────────────┘  │
│                            │
│ ─── 申請中（2）───        │
│ 👤 サキ  [承認] [拒否]     │
│                            │
│ ─── 友達（5）───          │
│ 🌸 アヤ  @aya_9999         │
│ 🍀 ケン  @ken_2222         │
│                            │
│  [友達を招待]              │
└──────────────────────────┘
```

**State**:

```dart
@riverpod
class FriendsController extends _$FriendsController {
  @override
  Future<FriendsState> build() async {
    return FriendsState(
      pendingRequests: await _fetchPendingRequests(),
      friends: await _fetchFriends(),
      searchQuery: '',
      searchResult: null,
    );
  }

  Future<void> search(String userId) async {
    if (userId.isEmpty) {
      state = AsyncValue.data(state.value!.copyWith(searchResult: null));
      return;
    }
    final user = await supabase
      .from('users')
      .select()
      .eq('user_id', userId)
      .maybeSingle();
    state = AsyncValue.data(state.value!.copyWith(searchResult: user));
  }

  Future<void> sendRequest(String userId) async { ... }
  Future<void> accept(String friendshipId) async { ... }
  Future<void> reject(String friendshipId) async { ... }
  Future<void> shareInviteLink() async {
    final myUserId = await _getMyUserId();
    final url = 'https://layer.app/invite?from=$myUserId';
    Share.share('Layer で繋がろう！ $url');
  }
}
```

**操作**:
- 検索バー入力 → デバウンス（500ms） → 検索
- 検索結果の「友達申請」ボタン → 申請送信
- 「承認」「拒否」 → 即時実行 + スナックバー
- 「友達を招待」 → OS の共有シート

**表示ロジック**:
- 完全一致検索のみ
- 既に友達 → 「友達」表示、ボタン無し
- 申請中 → 「申請中」表示、ボタン無し
- 自分自身 → 「あなた自身です」

**遷移先**: 招待リンク受信側 → アプリ起動 → サインイン後、自動で申請送信フローへ。

**エラー・空状態**:
- 検索結果なし → 「ユーザーが見つかりませんでした」
- 友達ゼロ → 「友達を招待して、Layer をはじめましょう」

---

### 2.9 ProfileScreen

**役割**: 自分のプロフィール、活動の簡易振り返り、設定への入り口。

**レイアウト**:

```
┌──────────────────────────┐
│  プロフィール             │
├──────────────────────────┤
│           😎              │
│         リョウ             │
│       @riyo_1234           │
│                            │
│   Pin: 12         友達: 5  │
│                            │
│   ┌──────────────────┐   │
│   │ 👥 友達を管理      │   │
│   └──────────────────┘   │
│   ┌──────────────────┐   │
│   │ ✏️ プロフィール編集 │   │
│   └──────────────────┘   │
│   ┌──────────────────┐   │
│   │ 🚪 ログアウト       │   │
│   └──────────────────┘   │
└──────────────────────────┘
```

**State**:

```dart
@riverpod
class ProfileController extends _$ProfileController {
  @override
  Future<ProfileState> build() async {
    final user = await _fetchMyUser();
    final pinCount = await _fetchMyPinCount();
    final friendCount = await _fetchMyFriendCount();
    return ProfileState(
      user: user,
      pinCount: pinCount,
      friendCount: friendCount,
    );
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }
}
```

**操作**:
- 「友達を管理」 → FriendsScreen
- 「プロフィール編集」 → 編集モーダル（アイコン・名前。要件 FR-1.4 / US-A8）
- 「ログアウト」 → 確認ダイアログ → サインアウト（要件 FR-1.5 / US-A9）

**表示ロジック**:
- Pin 数: 自分の Pin 総数
- 友達数: `accepted` の関係数
- リスト遷移は MVP では無し

**エラー・空状態**: ネットワークエラー → リトライ。

---

## 3. 状態遷移図

### 3.1 起動 〜 認証フロー

```
[アプリ起動]
    ↓
[SplashScreen]
    ↓
 セッション有？ ── No ──→ [SignInScreen]
    ↓ Yes                     ↓
                           Google サインイン
                              ↓
 プロフィール有？ ←─────────┘
    ↓ No                  ↓ Yes
[OnboardingScreen]    [MapScreen]
    ↓
プロフィール作成
    ↓
[MapScreen]
```

### 3.2 Pin 投稿 〜 発見フロー（MVP のコアロジック）

```
[MapScreen]
    ↓ FAB タップ
[PinComposeScreen]
    ↓ 投稿
[Supabase: pins INSERT]
    ↓
[DB Trigger 発火]
    ↓
半径 20m に「友達」の過去の Pin が存在？   ← 自分以外ではなく友達限定
    ↓ Yes
[pin_discoveries INSERT × 該当 Pin 数]
[notifications INSERT × 2]
  ・既存 Pin の持ち主へ：「発見されました」通知
  ・新規投稿者へ：「重なりました」通知
  （宛先・文面の定義は model.md §4 を参照）
    ↓
[MapScreen に戻る]
    ↓
[Realtime 更新で通知バッジが増える]
```

> 通知バッジは Supabase Realtime の購読で起動中もライブ更新される。アプリ起動時のバナー（要件 FR-6.1）は、起動以降に蓄積した未読をまとめて見せる導線。

---

## 4. 変更履歴

- 2026-05-19: 要件定義ドキュメント（require.md §9・§10）から分離して新規作成。発見対象を「友達限定」に修正（A1）、OnboardingScreen の「1/2」表記を削除（A3）、発見通知 ×2 の宛先を明記（A4）。
