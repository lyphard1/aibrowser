Safari AI Window Orchestrator
=============================

このプロジェクトは、Safari上の生成AIウィンドウだけを対象に、
起動・再整列・固定運用を行うためのツールです。

目的
----

- 埋め込みWebViewを使わず、Safariでそのままログイン運用する
- 生成AIウィンドウだけを再整列する（他のSafariウィンドウは触らない）
- 3+2 のようなグループ構成を崩しても、すぐ元に戻せる

構成
----

- `scripts/ai_window_tool.sh`
  - `start`: 不足している管理対象ウィンドウを開き、保存済み追加ウィンドウを復元してから再整列
  - `relayout`: 既存の管理対象ウィンドウだけ再整列
  - `close`: 追加ウィンドウ（位置・サイズ・タブ）を保存してから、管理対象+追加ウィンドウを閉じる
- `hammerspoon/ai_window_lock.lua`
  - ホットキー実行
  - 任意で自動固定モード（AUTO_LOCK）

クイックスタート
----------------

1. 手動再整列（まずはこれ）

   ```bash
   cd /Users/maedahideki/projects/aibrowser
   ./scripts/ai_window_tool.sh relayout
   ```

2. 一括起動 + 再整列

   ```bash
   cd /Users/maedahideki/projects/aibrowser
   ./scripts/ai_window_tool.sh start
   ```

3. 管理対象ウィンドウだけ閉じる

   ```bash
   cd /Users/maedahideki/projects/aibrowser
   ./scripts/ai_window_tool.sh close
   ```

   - 保存先: `~/.ai_window_tool_extra_windows.state`
   - 次回 `start` で追加ウィンドウを自動復元

設定変更
--------

`scripts/ai_window_tool.sh` の先頭を編集します。

- ウィンドウ種別（追加可能）
  - `PROVIDER_IDS`
  - `PROVIDER_URLS`
  - `PROVIDER_MATCHES`
- グループ（追加可能）
  - `GROUP_NAMES`
  - `GROUP_<NAME>_IDS`
  - `GROUP_<NAME>_BOUNDS`
  - `GROUP_<NAME>_WINDOW_SCALE`
  - `GROUP_<NAME>_HEIGHT_SCALE`

例: Group C を追加（3グループ運用）
- `GROUP_NAMES=("A" "B" "C")`
- `GROUP_C_IDS=("chatgpt" "perplexity")`
- `GROUP_C_BOUNDS="0,30,1504,1662"`
- `GROUP_C_WINDOW_SCALE="1.0"`
- `GROUP_C_HEIGHT_SCALE="0.8"`

例: 新しい窓種別 `gmail` を追加
- `PROVIDER_IDS` に `gmail` 追加
- `PROVIDER_URLS` に `https://mail.google.com/` 追加
- `PROVIDER_MATCHES` に `mail.google.com` 追加
- その後 `GROUP_<NAME>_IDS` に `gmail` を入れる

Hammerspoon連携（任意）
----------------------

1. `hammerspoon/ai_window_lock.lua` を `~/.hammerspoon/` にコピー
2. `~/.hammerspoon/init.lua` に `require("ai_window_lock")` を追加
3. HammerspoonをReload

- デフォルトはホットキー無効（競合回避）
- メニューバーに `AI` が出るので、そこから実行可能
- `alt` は macOS では `option` キーのこと
- ホットキーを使いたい場合は `~/.hammerspoon/ai_window_lock.lua` で
  `ENABLE_HOTKEYS = true` に変更し、キー定義を編集

注意点
------

- この方式は「Safari表示前提」で、ログイン/パスキーはSafariに任せます
- 完全ロックではなく「再整列で戻す」方式です
- 自動固定は `AUTO_LOCK = true` で有効化できます（`ai_window_lock.lua`）
- `start` は毎回全開きせず、不足分だけ追加します
- `relayout` は管理対象グループにのみ適用されます（追加ウィンドウは位置変更しない）

関連ドキュメント
----------------

- 1ページ運用手順: `docs/onepage_operations_ja.md`
- 全経緯まとめ: `docs/project_summary_20260202.md`
- 方式比較Plan: `docs/plan_safari_orchestrator.md`
- トラブルシュート: `docs/troubleshooting_ja.md`
- 修正記録（2026-02-03）: `docs/fix_history_20260203.md`

更新履歴
--------

### 2026-02-03: Safari URL問題 & extra増殖問題の修正

**修正された問題:**

1. **report.html 問題**: `start` 実行時に全ウィンドウが `report.html` になってしまう
2. **extra 増殖問題**: `close` → `start` を繰り返すと extra ウィンドウが増殖する
3. **複数タブ保存漏れ**: 複数タブを持つ extra ウィンドウの一部が保存されない

**主な変更点:**

- `close every window` を廃止 → managed ウィンドウのみ個別に閉じる
- `make new document` + `set URL` → `make new document with properties {URL:...}` に変更
- Safari が自動挿入する余分タブを除去するロジック追加
- extra 保存時にデータ収集と閉じる処理を分離（ループ中に閉じない）
- `managed_ids` が空でも extra を正しく保存するよう修正
- 復元後に STATE_FILE をクリアして増殖防止

詳細は `docs/fix_history_20260203.md` を参照。
