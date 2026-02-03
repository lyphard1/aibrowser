# 反省会: Codex版とClaude版の比較（2026-02-03）

## 結論（先に要点）
- 動いた要因は、Claude版が「Safariの全閉じをやめる」「URL付きで新規作成する」「余分タブを掃除する」「復元後にSTATEを空にする」を同時に満たしたこと。
- Codex版は要件（extra温存）に反する全閉じや、段階的検証不足で不安定化を招いた。
- この文書は `claude/ai_window_tool_修正記録.md` の内容を反映した改訂版。

## 何が悪かったか（技術）
## 1) `start` の責務を壊した（最重要）
- Codex版は `start_fresh_managed_windows` 内で `close every window` を実行していた（`scripts/ai_window_tool.sh.codex_bak:230-235`）。
- これにより「extra を残したい」要件と衝突し、毎回状態を壊す原因になった。
- Claude版はここを修正し、managed だけ閉じる構成にした（`scripts/ai_window_tool.sh:102-105`, `scripts/ai_window_tool.sh:233-236`）。

## 2) URL設定方式の選択ミスと余分タブ掃除不足
- Codex版は `make new document` → `set URL` の2段で、タイミング競合（レース）を引き起こしやすかった。
- Claude版は `make new document with properties {URL:...}` を使い、初期URL設定の競合を減らした（`scripts/ai_window_tool.sh:252`）。
- さらに、Safariが挿入した目的外タブを閉じる処理を追加（`scripts/ai_window_tool.sh:255-277`）。

## 3) 復元状態ファイルのライフサイクル管理が弱かった
- Codex版では復元後に `STATE_FILE` を消しておらず、同じ内容を再利用しやすかった（`scripts/ai_window_tool.sh.codex_bak:1338-1342`）。
- Claude版は復元後に `STATE_FILE` を明示クリアして再増殖を防止（`scripts/ai_window_tool.sh:1363-1367`）。

## 4) URL再強制ロジックの副作用
- Codex版の `reassert_managed_urls` 呼び出し（`scripts/ai_window_tool.sh.codex_bak:1342`）が、環境依存挙動と干渉して混乱を増やした。
- Claude版はこの呼び出しを外している（`scripts/ai_window_tool.sh:1361-1371` に該当呼び出しなし）。

## 5) AppleScript変更の連打で不安定化
- Codex版の開発途中で、`with properties` / `current tab` / handler重複など、構文・実行差異に弱い変更を重ねた。
- この結果、`-2741` や `-10006` 系のエラーを誘発し、修正が後手になった。

## 6) `open location` の誤用
- `open location` は新規ウィンドウ保証ではなく、既存ウィンドウの新タブに吸収されるケースがある。
- その結果、判定対象が崩れ、`debug`上で意図しないURL/タブ構成になった。

## 何が悪かったか（進め方）
## 1) 仮説検証の粒度が粗かった
- 1つずつ切り分けるべきところを、複数箇所同時に変えてしまった。
- 「どの変更が効いたか」が追えず、往復回数が増えた。

## 2) 安定版の固定が遅れた
- 「見た目で動く版」が一度あったのに、保険（明確なブランチ/固定コピー）を先に確定せず改修を継続した。

## 3) ユーザー負担の高い試行回数
- 手動確認が多いプロジェクトで、再実行ループを増やした。
- 結果として「修正コスト < 検証コスト」の逆転を起こした。

## Codex版 → Claude版の主要差分（実ファイル比較）
- 比較元:
  - 旧Codex版: `scripts/ai_window_tool.sh.codex_bak`
  - 現在採用版: `scripts/ai_window_tool.sh`（`claude/ai_window_tool.sh`を反映）
- 主要差分:
  - managed先閉じ追加（extra温存）: `scripts/ai_window_tool.sh:102-105`
  - `close every window` 削除: `scripts/ai_window_tool.sh:233-236`
  - URL付き生成方式へ変更: `scripts/ai_window_tool.sh:252`
  - 余分タブ掃除追加: `scripts/ai_window_tool.sh:255-277`
  - 復元後STATEクリア: `scripts/ai_window_tool.sh:1365-1366`
  - `reassert_managed_urls` 呼び出し撤去（旧は `scripts/ai_window_tool.sh.codex_bak:1342`）

## `debug` の見方（ユーザー向け）
- `tag=managed#N expected=...` が5件出ていれば、管理窓の識別は成立。
- `provider=` が空でも、URL/画面が実際に正しければ運用可能（Safari内部状態と表示の差異があるため）。
- `tag=extra` は保存・復元対象。不要なら `close` 前に閉じる。

## 再発防止（次回以降の実装ルール）
1. `start` は「managed起動 + 整列 + 必要ならextra復元」以外の責務を入れない。  
2. `close every window` は禁止（要件上の地雷）。  
3. 仕様変更は1コミット1論点（保存形式、起動順、整列ロジックを分離）。  
4. 失敗時は即ロールバックできるよう、`*.bak` を必ず先に保存。  
5. 「動いている版」に新機能を入れる時は、別ファイルでプロトタイプしてから本体反映。  

## 今回の反省（Codexとして）
- 判断ミス: 要件（extra温存）より「クリーン起動」を優先してしまった。  
- 実装ミス: AppleScriptの環境差異を軽視し、修正を急ぎすぎた。  
- 運用ミス: ユーザーの検証負荷を下げる設計（固定版・段階反映）が遅れた。  

以上。次はこの反省を前提に、「安定版を壊さない」進め方で実装します。
