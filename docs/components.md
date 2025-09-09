## 画面（コンポーネント）定義

### Chat Workspace（LWC: `chatWorkspace`）
- 目的: スレッド一覧 + メッセージパネルを 2 カラムで表示するワークスペース。
- 構成:
  - ページヘッダ: タイトル「チャット ワークスペース」、選択中スレッド名を表示。
  - 左カラム: `chatThreadList`
  - 右カラム: `chatMessagePanel`（`thread-id` を受け取って表示）
- 公開先: `lightning__AppPage`, `lightning__HomePage`, `lightning__Tab`

### Thread List（LWC: `chatThreadList`）
- 目的: 直近のスレッドの表示と新規作成。
- 主なUI/文言（日本語化済み）:
  - カードタイトル: 「スレッド」
  - 新規作成: 入力ラベル「スレッドのタイトル」/ ボタン「作成」
  - 一覧: 行末の「開く」ボタンで選択
- イベント: `threadselect` を発火
  - `detail = { threadId, threadName }`

### Message Panel（LWC: `chatMessagePanel`）
- 目的: スレッドのメッセージ一覧、送信（投稿）
- 主なUI/文言（日本語化済み）:
  - カードタイトル: 「メッセージ」
  - メッセージの状態: 同期済み/保留/失敗 のアイコン表示
  - コンポーザ: テキストエリア「メッセージ」（送信ボタン「送信」）
  - ガイダンス: スレッド未選択時は「スレッドを選択するか作成してください。」

---

### タブ
- `Chat Workspace`（CustomTab）: LWC `chatWorkspace` をタブとして公開
- 権限セット `Custom_Chat_User` でタブを可視化

