1ページ運用手順（Safari AI Window Orchestrator）
=============================================

対象
----

- Safariで管理対象ウィンドウ（生成AIなど）を複数並べて使う
- 認証はSafari側で行う（Passkey対応）
- AIウィンドウだけ再整列・終了したい

基本コマンド
------------

```bash
cd /Users/maedahideki/projects/aibrowser

# 不足分だけ開く + 保存済み追加ウィンドウ復元 + 再整列
bash ./scripts/ai_window_tool.sh start

# 既存AI窓だけ再整列
bash ./scripts/ai_window_tool.sh relayout

# 追加窓を保存してから、管理対象+追加窓を閉じる
bash ./scripts/ai_window_tool.sh close
```

使い方（最短）
-------------

1. 作業開始時に `start`
2. 配置が崩れたら `relayout`
3. 終了時に `close`（追加窓を保存して終了）

重要ポイント
------------

- `start` は毎回増殖しない（不足分だけ追加）
- `close` で追加窓（位置・サイズ・タブ）を保存し、次回 `start` で復元
- 対象は `PROVIDER_MATCHES` に定義したウィンドウのみ（通常Webは触らない）
- ログイン問題が出たらSafari側でログインしてから `relayout`

よく使う設定（`scripts/ai_window_tool.sh`）
-----------------------------------------

- 画面範囲:
  - `LEFT_BOUNDS`
  - `RIGHT_BOUNDS`
- 管理対象の種類:
  - `PROVIDER_IDS`, `PROVIDER_URLS`, `PROVIDER_MATCHES`
- グループ構成:
  - `GROUP_NAMES`
  - `GROUP_<NAME>_IDS`
  - `GROUP_<NAME>_BOUNDS`
  - `GROUP_<NAME>_WINDOW_SCALE`
  - `GROUP_<NAME>_HEIGHT_SCALE`

現在の既定値（このプロジェクト）
------------------------------

- 画面: 3008x1692 x 2想定
- 配置: A=chatgpt, gemini, claude / B=grok, perplexity
- 幅: 1.0（等倍）
- 高さ: 0.8

トラブル時
---------

- 位置がズレる: `LEFT_BOUNDS` / `RIGHT_BOUNDS` を実画面に合わせる
- 意図しない窓が動く: URLがAIドメインか確認
- 反応しない: Safari/Terminal の自動操作権限を確認
