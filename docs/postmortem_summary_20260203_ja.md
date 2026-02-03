# 反省会 要約（チェックリスト）

- [x] 最大の失敗: `start` で `close every window` を実行し、extra要件を壊した。
- [x] URL設定の失敗: `make new document` → `set URL` の2段で競合を起こした。
- [x] `open location` の誤用: 新規タブ吸収で窓/タブ構造が崩れた。
- [x] STATE管理不足: 復元後に `STATE_FILE` を消さず増殖を招いた。
- [x] 修正連打: 1変更1検証を守らず、原因切り分けを難化させた。

## 今回の正解（採用）
- `close every window` を廃止し、managedのみ閉じる。
- `make new document with properties {URL:...}` を使用。
- 起動後に目的外タブを掃除する。
- extra復元後に `STATE_FILE` をクリアする。
- `reassert_managed_urls` を外し、副作用を減らす。

## 今後のルール
- 1コミット1論点（保存/起動/整列を混ぜない）。
- 変更前に必ず `.bak` を作る。
- 安定版は固定し、実験は別ファイルで行う。
