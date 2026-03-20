# TCA (The Composable Architecture) 最新ベストプラクティス調査レポート

**調査日**: 2026-03-21
**対象バージョン**: TCA 1.17+ (最新 1.25.2, 2025-03-16 リリース)
**調査ソース**: pointfreeco 公式ドキュメント、GitHub リリースノート、コミュニティ記事

---

## 目次

1. [@Reducer マクロの正しい使い方](#1-reducer-マクロの正しい使い方)
2. [@ObservableState vs ViewState の移行パターン](#2-observablestate-vs-viewstate-の移行パターン)
3. [Effect のベストプラクティス](#3-effect-のベストプラクティス)
4. [DependencyKey / DependencyValues の設計パターン](#4-dependencykey--dependencyvalues-の設計パターン)
5. [Navigation（StackState/StackAction）](#5-navigationstackstatestackaction)
6. [テスト: TestStore の使い方](#6-テスト-teststore-の使い方)
7. [パフォーマンス最適化](#7-パフォーマンス最適化)
8. [共通のアンチパターン](#8-共通のアンチパターン)
9. [Swift 6 Concurrency との互換性](#9-swift-6-concurrency-との互換性)
10. [子Reducer合成: Scope, ifLet, forEach](#10-子reducer合成-scope-iflet-foreach)
11. [SharedState / @Shared の使い方](#11-sharedstate--shared-の使い方)
12. [DelegateAction パターン](#12-delegateaction-パターン)

---

## 重要: TCA v2.0 への移行準備

TCA 1.24 / 1.25 では v2.0 に向けた大規模な非推奨化が行われている。以下の API は**既に deprecated**であり、新規コードでは使用しないこと:

| 非推奨 API | 代替 |
|:-----------|:-----|
| `ViewStore` / `WithViewStore` | `@ObservableState` + Store 直接アクセス |
| `@BindingState` / `BindingViewState` | `@Bindable var store` |
| `IfLetStore` / `ForEachStore` / `SwitchStore` | Swift 標準の `if let` / `ForEach` / `switch` |
| `NavigationStackStore` | `NavigationStack(path: $store.scope(...))` |
| `Effect.concatenate` / `Effect.map` | `Effect.run` + async/await |
| `StorePublisher` | Observation framework |
| `TaskResult` | Swift native `Result` |
| closure-scoped views | `store.scope` |

---

## 1. @Reducer マクロの正しい使い方

### 基本構造（TCA 1.17+）

```swift
@Reducer
struct CounterFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
        var isLoading = false
    }

    enum Action {
        case incrementButtonTapped
        case decrementButtonTapped
        case fetchCompleted(Result<Int, Error>)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .incrementButtonTapped:
                state.count += 1
                return .none
            case .decrementButtonTapped:
                state.count -= 1
                return .none
            case let .fetchCompleted(.success(value)):
                state.count = value
                state.isLoading = false
                return .none
            case .fetchCompleted(.failure):
                state.isLoading = false
                return .none
            }
        }
    }
}
```

### @Reducer マクロが自動で行うこと

- `Reducer` プロトコルへの準拠を自動生成
- `Action` enum に `@CasePathable` を自動適用（case key paths が使える）
- ネストされた `@Reducer` 型も再帰的に処理

### 推奨ルール

- **Feature 命名**: `xxxFeature` とし、`xxxReducer` サフィックスは不要
- **State は常に `@ObservableState` をつける**（v2.0 では必須になる）
- **Action は `Equatable` にしない**（TCA が内部で処理する）
- **body で型推論が効かない場合**: `Reduce<State, Action> { state, action in ... }` と明示する

---

## 2. @ObservableState vs ViewState の移行パターン

### Before（旧パターン: ViewStore ベース）

```swift
struct CounterView: View {
    let store: StoreOf<CounterFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            Text("\(viewStore.count)")
            Button("+") { viewStore.send(.incrementButtonTapped) }
        }
    }
}
```

### After（現行パターン: @ObservableState）

```swift
struct CounterView: View {
    let store: StoreOf<CounterFeature>

    var body: some View {
        Text("\(store.count)")
        Button("+") { store.send(.incrementButtonTapped) }
    }
}
```

### バインディングの移行

```swift
// Before
@BindingState var text: String = ""
// View: TextField("Name", text: viewStore.$text)

// After（TCA 1.17+）
var text: String = ""
// View: @Bindable var store = store
//       TextField("Name", text: $store.text)
```

### 移行のポイント

1. `@ObservableState` を State に付与すると、SwiftUI が**実際にアクセスされたプロパティだけ**を追跡する
2. `WithViewStore` のラッパーが不要になり、ネストが浅くなる
3. `ViewState` でスコープを絞る必要がなくなる（Observation が自動追跡する）
4. iOS 16 以前をサポートする場合は `WithPerceptionTracking` でラップする

### コレクション・オプショナル・enum の書き換え

```swift
// Optional: IfLetStore → if let
if let childStore = store.scope(state: \.child, action: \.child) {
    ChildView(store: childStore)
}

// Collection: ForEachStore → ForEach
ForEach(store.scope(state: \.rows, action: \.rows)) { childStore in
    RowView(store: childStore)
}

// Enum: SwitchStore → switch
switch store.state {
case .activity:
    if let store = store.scope(state: \.activity, action: \.activity) {
        ActivityView(store: store)
    }
case .settings:
    if let store = store.scope(state: \.settings, action: \.settings) {
        SettingsView(store: store)
    }
}
```

---

## 3. Effect のベストプラクティス

### Effect.run（推奨）

```swift
case .fetchButtonTapped:
    state.isLoading = true
    return .run { send in
        let result = await apiClient.fetch()
        await send(.fetchCompleted(result))
    }
```

### Effect キャンセル

```swift
// CancelID は enum case で定義（型ベースは非推奨）
enum CancelID { case search }

case .searchQueryChanged(let query):
    return .run { send in
        let results = try await searchClient.search(query)
        await send(.searchResults(results))
    }
    .cancellable(id: CancelID.search, cancelInFlight: true)

case .viewDisappeared:
    return .cancel(id: CancelID.search)
```

### cancelInFlight の活用

`cancelInFlight: true` を指定すると、同じ ID の前回の Effect を自動キャンセルしてから新しい Effect を実行する。検索やデバウンスに最適。

### Effect.merge と Effect.concatenate

```swift
// 並列実行（推奨）
return .merge(
    .run { send in await send(.fetchUser) },
    .run { send in await send(.fetchPosts) }
)

// 逐次実行（Effect.concatenate は 1.25 で deprecated）
// 代わりに .run 内で sequential に呼ぶ
return .run { send in
    let user = await fetchUser()
    await send(.userLoaded(user))
    let posts = await fetchPosts(userId: user.id)
    await send(.postsLoaded(posts))
}
```

### Effect のルール

- **`.run` を優先**: async/await ベースで Swift Concurrency と自然に統合
- **`.publisher` は非推奨化の方向**: Combine 依存を減らす流れ
- **Reducer 内で重い処理をしない**: Reducer はメインスレッドで実行されるため、重い計算は `.run` で逃がす
- **タスク名を付ける**: `Effect.run(taskName: "FetchData") { ... }` でデバッグしやすくする（1.23+）

---

## 4. DependencyKey / DependencyValues の設計パターン

### Client Struct パターン（推奨）

プロトコルではなく、**クロージャを持つ struct** で依存を定義する。

```swift
// 依存クライアントの定義
@DependencyClient
struct AudioPlayerClient {
    var play: (_ url: URL) async throws -> Void
    var stop: () async -> Void
    var setVolume: (_ volume: Float) async -> Void
}

// DependencyKey 準拠
extension AudioPlayerClient: DependencyKey {
    static let liveValue = AudioPlayerClient(
        play: { url in /* AVAudioPlayer implementation */ },
        stop: { /* stop implementation */ },
        setVolume: { volume in /* set volume */ }
    )

    // テスト用: 省略時は自動で unimplemented になる
    // static let testValue = AudioPlayerClient(...)

    // Preview用
    static let previewValue = AudioPlayerClient(
        play: { _ in },
        stop: { },
        setVolume: { _ in }
    )
}

// DependencyValues に登録
extension DependencyValues {
    var audioPlayer: AudioPlayerClient {
        get { self[AudioPlayerClient.self] }
        set { self[AudioPlayerClient.self] = newValue }
    }
}

// Reducer で使用
@Reducer
struct PlayerFeature {
    @Dependency(\.audioPlayer) var audioPlayer

    // ...
}
```

### @DependencyClient マクロ（TCA 1.x 最新）

`@DependencyClient` マクロを使うと、`unimplemented` スタブの自動生成、テスト時の部分オーバーライドが容易になる。

### 設計原則

1. **プロトコルではなく struct を使う**: テスト時に特定のエンドポイントだけ差し替え可能
2. **liveValue は必須、testValue / previewValue はオプション**
3. **testValue を省略すると自動で failing stub になる**: テストで使われていない依存を検出できる
4. **`prepareDependencies` でテスト初期化**: State の初期化子が依存を使う場合に必要

---

## 5. Navigation（StackState/StackAction）

### 2つのナビゲーションパラダイム

| 方式 | 適用場面 | 特徴 |
|:-----|:---------|:-----|
| **Tree-based** | Sheet, Popover, Alert, ConfirmationDialog | 親が子の状態を Optional で保持 |
| **Stack-based** | NavigationStack | `StackState` で画面のスタックを管理 |

### Tree-based（Optional ベース）

```swift
@Reducer
struct ParentFeature {
    @ObservableState
    struct State {
        @Presents var detail: DetailFeature.State?
    }

    enum Action {
        case detail(PresentationAction<DetailFeature.Action>)
        case showDetailTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showDetailTapped:
                state.detail = DetailFeature.State()
                return .none
            case .detail:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            DetailFeature()
        }
    }
}

// View
struct ParentView: View {
    @Bindable var store: StoreOf<ParentFeature>

    var body: some View {
        Button("Show Detail") { store.send(.showDetailTapped) }
            .sheet(item: $store.scope(state: \.detail, action: \.detail)) { store in
                DetailView(store: store)
            }
    }
}
```

### Stack-based（NavigationStack）

```swift
@Reducer
struct AppFeature {
    @ObservableState
    struct State {
        var path = StackState<Path.State>()
    }

    enum Action {
        case path(StackActionOf<Path>)
        case goToDetailTapped
    }

    @Reducer
    enum Path {
        case detail(DetailFeature)
        case settings(SettingsFeature)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .goToDetailTapped:
                state.path.append(.detail(DetailFeature.State()))
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

// View
struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            RootView()
        } destination: { store in
            switch store.case {
            case let .detail(store):
                DetailView(store: store)
            case let .settings(store):
                SettingsView(store: store)
            }
        }
    }
}
```

### 使い分けガイド

- **Sheet / Alert / ConfirmationDialog** → Tree-based (`@Presents` + `.ifLet`)
- **画面遷移スタック（push/pop）** → Stack-based (`StackState` + `.forEach`)
- **Tab 切り替え** → 単純な enum State で管理
- **ディープリンク** → Stack-based が有利（パスを直接操作可能）

---

## 6. テスト: TestStore の使い方

### 基本的な exhaustive テスト

```swift
@Test
func incrementDecrement() async {
    let store = TestStore(initialState: CounterFeature.State()) {
        CounterFeature()
    }

    await store.send(.incrementButtonTapped) {
        $0.count = 1  // 全ての state 変更を assert する
    }
    await store.send(.decrementButtonTapped) {
        $0.count = 0
    }
}
```

### Effect を伴うテスト

```swift
@Test
func fetchData() async {
    let store = TestStore(initialState: Feature.State()) {
        Feature()
    } withDependencies: {
        $0.apiClient.fetch = { .mock }
    }

    await store.send(.fetchButtonTapped) {
        $0.isLoading = true
    }
    await store.receive(\.fetchCompleted.success) {
        $0.isLoading = false
        $0.data = .mock
    }
}
```

### Non-exhaustive テスト（統合テスト向け）

```swift
@Test
func loginFlow_integration() async {
    let store = TestStore(initialState: App.State()) {
        App()
    } withDependencies: {
        $0.authClient.login = { _, _ in .mockUser }
    }

    store.exhaustivity = .off  // non-exhaustive モード

    await store.send(.login(.submitButtonTapped))
    await store.receive(\.login(.delegate(.didLogin))) {
        $0.selectedTab = .activity  // 気にする state だけ assert
    }
}
```

### exhaustivity の使い分け

| モード | 用途 | 特徴 |
|:-------|:-----|:-----|
| `.on`（デフォルト） | 単体テスト | 全 state 変更・全 effect を assert |
| `.off` | 統合テスト | 必要な state だけ assert |
| `.off(showSkippedAssertions: true)` | デバッグ | スキップした assertion を表示 |

### テストのベストプラクティス

1. **`XCTAssertNoDifference` を使う**（`XCTAssertEqual` より差分が見やすい）
2. **`prepareDependencies` で初期状態を設定**: State の init 内で依存を使う場合
3. **Action 名でテストストーリーを語る**: `.refreshButtonTapped` → `.apiResponse` → `.deleteButtonTapped`
4. **テスト用依存は明示的にオーバーライド**: `testValue` は failing stub がデフォルト
5. **`store.finish()` で未消費の effect がないことを確認**

---

## 7. パフォーマンス最適化

### @ObservableState による自動最適化（最重要）

TCA 1.7+ の `@ObservableState` は、ビューが**実際にアクセスした state プロパティだけ**を追跡する。これにより:

- `ViewStore` + `observe:` での手動スコーピングが不要になった
- 不要な再描画が大幅に減少
- `WithViewStore` のオーバーヘッドが解消

### 旧 ViewStore 時代のパフォーマンス問題（参考）

- `WithViewStore` は内部で `@ObservedObject` を使用し、state の任意の変更で再計算が走っていた
- `observe:` のプロジェクション関数は**全ての state 更新で実行**されていた
- 大規模アプリで 5 行のテキスト処理に 9 秒かかるケースが報告されていた

### 現行の最適化ルール

1. **`@ObservableState` を全 State に付与**: Observation framework の恩恵を最大化
2. **Reducer 内で O(n) 計算をしない**: scope 関数内のコードは全 action で実行される
3. **高頻度 Action を避ける**: タイマー、スクロール中の action は debounce する
4. **Optional State + `.ifLet`**: 表示されていない画面の reducer 処理をスキップ
5. **計算プロパティを避ける**: State の computed property はホットパスで毎回実行される。事前計算した feature state を使う
6. **UI 専用の一時的な状態は View 層に置く**: ホバー状態など永続化不要な状態は Store に入れない

---

## 8. 共通のアンチパターン

### 1. Action をメソッド呼び出しの代替として使う

```swift
// BAD: Action を共有ロジックの呼び出し手段にする
case .buttonTapped:
    return .send(.sharedLogic)

// GOOD: 共通ロジックは State の mutating func にする
case .buttonTapped:
    state.applySharedLogic()
    return .none
```

Action 送信はメソッド呼び出しより**はるかに高コスト**（rescoping + equality check が走る）。

### 2. Action 名を「何をするか」で命名する

```swift
// BAD
enum Action { case incrementCount }

// GOOD（「何が起きたか」で命名）
enum Action { case incrementButtonTapped }
```

### 3. Reducer で重い処理を実行する

```swift
// BAD: Reducer はメインスレッドで実行される
case .processData:
    state.result = expensiveComputation(state.rawData)  // UI フリーズ
    return .none

// GOOD: Effect に逃がす
case .processData:
    state.isProcessing = true
    return .run { [rawData = state.rawData] send in
        let result = await expensiveComputation(rawData)
        await send(.processingCompleted(result))
    }
```

### 4. scope 関数内で外部参照する

```swift
// BAD: scope 関数は全 action で実行される
store.scope(state: { appState in
    ViewState(
        items: appState.items,
        setting: UserDefaults.standard.bool(forKey: "key")  // 外部参照
    )
})

// GOOD: State のみ参照
store.scope(state: { appState in
    ViewState(items: appState.items, setting: appState.cachedSetting)
})
```

### 5. State に property observer を使う

```swift
// BAD: willSet/didSet はテスト困難
@ObservableState
struct State {
    var count: Int = 0 {
        didSet { /* side effect */ }  // テスト不可能
    }
}

// GOOD: Reducer で state 変更時の副作用を管理
```

### 6. 過剰な親子間双方向通信

子 feature の内部 Action を親が catch して別の Action を送り返すループは、コードの理解とデバッグを困難にする。代わりに DelegateAction パターンを使う。

### 7. `Effect.concatenate` の誤用（1.25 で deprecated）

```swift
// BAD（deprecated）
return .concatenate(effectA, effectB)

// GOOD
return .run { send in
    await send(effectA())
    await send(effectB())
}
```

---

## 9. Swift 6 Concurrency との互換性

### 移行戦略

1. **モジュール単位で段階的に有効化**:
   ```swift
   .enableExperimentalFeature("StrictConcurrency")
   ```
2. 警告をすべて解消してから Swift 6 ツールチェーンに切り替え

### Sendable 準拠

| 型 | Sendable 必須? | 備考 |
|:---|:--------------|:-----|
| State | はい | Value type なので通常は自動準拠 |
| Action | 基本不要 | `AlertState` / `ConfirmationDialogState` で使う場合は必要 |
| Reducer | はい | `@Dependency` を `.run` で使う場合に必要 |
| Dependency Client | はい | `DependencyKey` プロトコルが要求 |

### @MainActor の扱い

- **Reducer 自体は `@MainActor` を付けない**（TCA が内部で管理）
- **View 層のカスタムバインディング**: `@MainActor` アノテーションが必要な場合がある
- **Store extensions**: `@Sendable @MainActor` でクロージャをアノテート

### Effect 内での注意

```swift
// GOOD: Effect.run は自動で MainActor から外れる
return .run { send in
    let data = await fetchData()  // バックグラウンドで実行
    await send(.dataLoaded(data)) // MainActor に戻る
}

// 注意: キャプチャする値は Sendable であること
return .run { [id = state.itemId] send in  // 明示的キャプチャ
    let item = await fetchItem(id)
    await send(.itemLoaded(item))
}
```

### サードパーティ依存

Swift 6 未対応のフレームワークには `@preconcurrency import` を使う（最終手段）。

### Swift 6.2 の恩恵

- `@Sendable` が自動推論される場面が増加
- メソッド参照やキーパスリテラルが安全な場合に自動 Sendable
- TCA での明示的アノテーションが減少

---

## 10. 子Reducer合成: Scope, ifLet, forEach

### Scope（子 Feature の埋め込み）

```swift
@Reducer
struct ParentFeature {
    @ObservableState
    struct State {
        var child = ChildFeature.State()
    }

    enum Action {
        case child(ChildFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.child, action: \.child) {
            ChildFeature()
        }
        Reduce { state, action in
            // 親の追加ロジック
            switch action {
            case .child(.delegate(.didComplete)):
                // 子からの delegate action をハンドル
                return .none
            case .child:
                return .none
            }
        }
    }
}
```

### ifLet（Optional な子 Feature）

```swift
@Reducer
struct ParentFeature {
    @ObservableState
    struct State {
        @Presents var detail: DetailFeature.State?
    }

    enum Action {
        case detail(PresentationAction<DetailFeature.Action>)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            // 親のロジック
        }
        .ifLet(\.$detail, action: \.detail) {
            DetailFeature()
        }
    }
}
```

### forEach（コレクションの子 Feature）

```swift
@Reducer
struct ListFeature {
    @ObservableState
    struct State {
        var items: IdentifiedArrayOf<ItemFeature.State> = []
    }

    enum Action {
        case items(IdentifiedActionOf<ItemFeature>)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            // 親のロジック
        }
        .forEach(\.items, action: \.items) {
            ItemFeature()
        }
    }
}
```

### NavigationStack 用 forEach

```swift
var body: some ReducerOf<Self> {
    Reduce { state, action in /* ... */ }
        .forEach(\.path, action: \.path)  // StackState に対する forEach
}
```

### 合成の順序ルール

```swift
var body: some ReducerOf<Self> {
    // 1. 子 Reducer（Scope）を先に配置
    Scope(state: \.child, action: \.child) {
        ChildFeature()
    }
    // 2. 親の Reduce を後に配置（子の action を受け取るため）
    Reduce { state, action in
        switch action {
        case .child(.delegate(.didSave)):
            // 子が先に処理 → 親がここで受け取る
            return .none
        default:
            return .none
        }
    }
    // 3. ifLet / forEach は Reduce の後
    .ifLet(\.$sheet, action: \.sheet) { SheetFeature() }
    .forEach(\.path, action: \.path)
}
```

---

## 11. SharedState / @Shared の使い方

### 基本的な @Shared

```swift
@Reducer
struct FeatureA {
    @ObservableState
    struct State {
        @Shared var userData: UserData  // 他の feature と共有
    }
}

@Reducer
struct FeatureB {
    @ObservableState
    struct State {
        @Shared var userData: UserData  // 同じ参照
    }
}
```

### 永続化戦略

#### AppStorage（UserDefaults）

```swift
@ObservableState
struct State {
    @Shared(.appStorage("hasSeenOnboarding"))
    var hasSeenOnboarding = false

    @Shared(.appStorage("preferredTheme"))
    var theme: Theme = .system
}
```

#### FileStorage（ファイル永続化）

```swift
@ObservableState
struct State {
    @Shared(.fileStorage(.currentUserURL))
    var currentUser: User?
}

extension URL {
    static let currentUserURL = URL
        .documentsDirectory
        .appendingPathComponent("current-user.json")
}
```

### カスタム永続化戦略

リモート設定、Feature Flag、その他の外部ソースとの統合用に独自戦略を定義可能。

### @Shared の特徴

- **値型ベース**: 参照型のように振る舞うが、値型のテスタビリティを維持
- **自動同期**: 一方の feature で変更すると、他の feature でも即座に反映
- **テスト可能**: exhaustive テストで @Shared の変更も assert 可能
- **親からの注入**: `@Shared` は親が初期化時に渡す

### 注意点

- DelegateAction と組み合わせると、テスト時に state 変更のタイミングが直感と異なる場合がある（send 時に mutation が起きる）
- 過度な共有は避け、本当に複数 feature で同期が必要な state にのみ使用する

---

## 12. DelegateAction パターン

### 概要

子 feature が親に「何かが起きた」ことを通知するためのパターン。子が親の振る舞いを知る必要がなく、疎結合を実現する。

### Action のカテゴリ分け

```swift
@Reducer
struct ChildFeature {
    enum Action {
        // View から発火される action
        case view(ViewAction)
        // 内部処理用（effect の結果など）
        case `internal`(InternalAction)
        // 親への通知（delegate）
        case delegate(DelegateAction)

        enum ViewAction {
            case saveButtonTapped
            case cancelButtonTapped
        }

        enum InternalAction {
            case saveCompleted(Result<Void, Error>)
        }

        enum DelegateAction {
            case didSave(Item)
            case didCancel
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.saveButtonTapped):
                return .run { [item = state.item] send in
                    try await saveClient.save(item)
                    await send(.internal(.saveCompleted(.success(()))))
                }

            case .internal(.saveCompleted(.success)):
                // 保存成功を親に通知
                return .send(.delegate(.didSave(state.item)))

            case .view(.cancelButtonTapped):
                return .send(.delegate(.didCancel))

            case .delegate:
                return .none  // 子は delegate を処理しない
            }
        }
    }
}
```

### 親での受け取り

```swift
@Reducer
struct ParentFeature {
    var body: some ReducerOf<Self> {
        Scope(state: \.child, action: \.child) {
            ChildFeature()
        }
        Reduce { state, action in
            switch action {
            case let .child(.delegate(.didSave(item))):
                state.items.append(item)
                state.child = nil  // 子を閉じる
                return .none

            case .child(.delegate(.didCancel)):
                state.child = nil
                return .none

            case .child:
                return .none  // 子の内部 action は無視
            }
        }
    }
}
```

### DelegateAction のルール

1. **子は `.delegate` action を処理しない**: `case .delegate: return .none`
2. **DelegateAction は Effect を返さない**: 純粋な通知のみ。副作用は親が判断する
3. **DelegateAction 名は「何が起きたか」**: `.didSave`, `.didCancel`, `.didSelectItem`
4. **必要なデータを associated value で渡す**: 親が子の state にアクセスする必要をなくす
5. **Scope を Reduce の前に配置**: 子が先に処理し、親がその結果を受け取る構成にする

---

## MurMurNote プロジェクトへの適用推奨事項

現在のプロジェクト（TCA 1.17+, Swift 6.2, iOS 17+）に対する具体的な推奨:

1. **全 Feature の State に `@ObservableState` を付与**（v2.0 準備）
2. **`WithViewStore` / `ViewStore` が残っていれば Store 直接アクセスに移行**
3. **`@BindingState` → `@Bindable var store` パターンに移行**
4. **Effect は `.run` + async/await に統一、`.publisher` は使わない**
5. **CancelID は enum case で定義**（型ベースは Swift のバグで release ビルドで壊れる）
6. **依存クライアントは `@DependencyClient` マクロ + struct パターン**
7. **Navigation は Tree-based（Sheet/Alert）と Stack-based（画面遷移）を併用**
8. **テストは単体テスト = exhaustive、統合テスト = non-exhaustive**
9. **DelegateAction パターンで親子間通信を疎結合に**
10. **`Effect.concatenate`, `Effect.map`, `StorePublisher` は使わない**（1.25 で deprecated）

---

## 参照ソース

- [pointfreeco/swift-composable-architecture - GitHub](https://github.com/pointfreeco/swift-composable-architecture)
- [TCA Releases](https://github.com/pointfreeco/swift-composable-architecture/releases)
- [Observation comes to the Composable Architecture - Point-Free Blog](https://www.pointfree.co/blog/posts/130-observation-comes-to-the-composable-architecture)
- [Shared state in the Composable Architecture - Point-Free Blog](https://www.pointfree.co/blog/posts/135-shared-state-in-the-composable-architecture)
- [Non-exhaustive testing in TCA - Point-Free Blog](https://www.pointfree.co/blog/posts/83-non-exhaustive-testing-in-the-composable-architecture)
- [The Composable Architecture - Best Practices - Krzysztof Zablocki](https://www.merowing.info/the-composable-architecture-best-practices/)
- [RFC: General tips and tricks - GitHub Discussion #1666](https://github.com/pointfreeco/swift-composable-architecture/discussions/1666)
- [Converting a TCA app to Swift 6 - Luke Redpath](https://gist.github.com/lukeredpath/a04051224bedffad3fdac3aeb1c6a124)
- [TCA Performance Analysis - SwiftyPlace](https://www.swiftyplace.com/blog/the-composable-architecture-performance)
- [Master Swift Composable Architecture: 5 Steps for 2025](https://junkangworld.com/blog/master-swift-composable-architecture-5-steps-for-2025)
- [Shared state beta - GitHub Discussion #2857](https://github.com/pointfreeco/swift-composable-architecture/discussions/2857)
- [Delegate mechanism in TCA - GitHub Discussion #2521](https://github.com/pointfreeco/swift-composable-architecture/discussions/2521)
