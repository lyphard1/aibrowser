Plan: Safari中心の生成AIマルチウィンドウ運用
======================================

作成日: 2026-02-02

背景
----

埋め込みWebView型のアプリでは、複数サービスでPasskey認証が安定しない。
そのため、表示と認証はSafariに任せ、制御だけを外部ツールで行う。

方式比較（5案）
--------------

1) Electron内蔵WebView継続
- Pros: 既存流用しやすい
- Cons: Passkey/認証フローが不安定
- 判定: 採用しない

2) Tauri/WKWebViewへ移行
- Pros: 軽量化しやすい
- Cons: WebView系の認証問題が残る
- 判定: 採用しない

3) Safariオーケストレーター（GUIアプリ）
- Pros: Safari認証をそのまま利用できる
- Cons: UI実装コストが増える
- 判定: 将来候補

4) Chromeオーケストレーター
- Pros: Safari同様に埋め込み回避
- Cons: 主運用ブラウザの切替コスト
- 判定: 代替候補

5) スクリプト運用（AppleScript + Hammerspoon）
- Pros: 最速導入、実運用の安定性が高い
- Cons: プロダクトUIは薄い
- 判定: まず採用（今回）

採用方式の要件
--------------

- 生成AIウィンドウだけを再整列（一般Webウィンドウは除外）
- ウィンドウ数は可変（group A / group B の配列で制御）
- 3+2, 4+1, 2+2 などを簡単に変更
- 崩れてもワンアクションで元配置へ戻せる
- 必要なら自動固定（AUTO_LOCK）を追加できる

今回の成果物
------------

- `scripts/ai_window_tool.sh`
  - `start`: URL起動 + 再整列
  - `relayout`: 既存AI窓のみ再整列
- `hammerspoon/ai_window_lock.lua`
  - ホットキー運用
  - 任意で自動固定

運用モード
----------

A. 手動再整列モード（推奨）
- 普段は普通に使う
- 崩れたら `relayout` だけ実行

B. 自動固定モード
- Hammerspoonの `AUTO_LOCK=true`
- Safari窓を動かすたびに再整列

今後の拡張案
-----------

- GUIランチャーを追加して「start/relayout」をボタン化
- モニター解像度を自動検出してbounds自動計算
- URL判定のカスタムルールを外部ファイル化
