プロジェクト経緯まとめ（2026-02-02）
===================================

目的
----

- 生成AIサービスを複数並べて比較しながら使う
- 手動入力前提で、Bot判定リスクを避ける
- 2画面（27インチ x 2）運用を楽にする

初期案と課題
------------

初期は埋め込みブラウザ型（Electron WebView）で実装したが、以下の問題が発生:

- ChatGPT / Gemini / Claude / Perplexity が Passkey認証で停止
- Grokのみログイン可能
- 認証フローで外部遷移やWebView制約が強く、安定運用が難しい

結論として、埋め込み表示は採用しない方針に変更した。

検討した方式（Plan）
--------------------

1. Electron WebView継続
   - Pros: 既存資産活用
   - Cons: Passkey認証が不安定
   - 判定: 不採用

2. Tauri/WKWebView移行
   - Pros: 軽量化
   - Cons: WebView系制約は残る
   - 判定: 不採用

3. SafariオーケストレーターGUI
   - Pros: Safari認証をそのまま利用
   - Cons: GUI実装コスト
   - 判定: 将来候補

4. Chromeオーケストレーター
   - Pros: 認証安定性は確保しやすい
   - Cons: Safari運用から外れる
   - 判定: 代替候補

5. スクリプト運用（AppleScript + 任意Hammerspoon）
   - Pros: 最短・安定・実用的
   - Cons: 専用UIは薄い
   - 判定: 今回採用

今回の最終成果物
----------------

- `scripts/ai_window_tool.sh`
  - `start`: 不足しているAIウィンドウだけ開いて再整列
  - `relayout`: 既存AIウィンドウだけ再整列
  - `close`: AIウィンドウだけ閉じる
  - グループ追加対応（`GROUP_NAMES` + `GROUP_<NAME>_*`）
  - ウィンドウ種別追加対応（`PROVIDER_IDS/URLS/MATCHES`）

- `hammerspoon/ai_window_lock.lua`（任意）
  - メニューバー `AI` から実行
  - ホットキーはデフォルト無効（競合回避）
  - `AUTO_LOCK=true` で自動再整列

現在の既定設定
--------------

ファイル: `scripts/ai_window_tool.sh`

- モニター想定: 3008x1692 x 2（横並び）
- 配置:
  - Group A: `chatgpt`, `gemini`, `claude`
  - Group B: `grok`, `perplexity`
- 位置:
  - `LEFT_BOUNDS=0,30,3008,1662`
  - `RIGHT_BOUNDS=3008,30,6016,1662`
- 幅倍率:
  - `GROUP_A_WINDOW_SCALE=1.0`
  - `GROUP_B_WINDOW_SCALE=1.0`
- 高さ倍率:
  - `GROUP_A_HEIGHT_SCALE=0.8`
  - `GROUP_B_HEIGHT_SCALE=0.8`

運用コマンド
------------

```bash
cd /Users/maedahideki/projects/aibrowser

# 不足分だけ開く + 再整列
bash ./scripts/ai_window_tool.sh start

# 既存AI窓だけ再整列
bash ./scripts/ai_window_tool.sh relayout

# AI窓だけ閉じる
bash ./scripts/ai_window_tool.sh close
```

今回の要望反映履歴
------------------

- `start` を複数回実行しても毎回増殖しないよう修正（不足分のみ追加）
- AIウィンドウだけを閉じる `close` を追加
- 2画面前提の座標を 3008x1692 に合わせた
- 幅は最終的に +0%（等倍）へ戻した
- 高さは最終的に 0.8倍に設定
- キーバインドは複雑さ回避のためデフォルト無効化

旧実装の保管場所
----------------

埋め込みブラウザ版（旧Electron実装）は以下に退避済み:

- `/Users/maedahideki/projects/aibrowser_electron_legacy_20260202_115858`

補足
----

- この方式は「Safariでログイン・表示」を前提にしているため、Passkey運用と相性が良い
- 専用GUIが必要になったら、将来は「SafariオーケストレーターGUI（方式3）」へ拡張可能
