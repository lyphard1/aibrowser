# ai_window_tool.sh 修正記録

## 何のツールか

Safari のウィンドウを自動で並べるツール。
managed（管理対象）5窓（ChatGPT, Gemini, Claude, Grok, Perplexity）を起動・整列し、
ユーザーが手動で開いた extra ウィンドウは close 時に保存、次回 start で復元する。

---

## 修正前に起きていた問題

### 問題1: 全ウィンドウが `report.html` になる

**症状:**
`debug` で確認すると、managed 5窓も extra も全部こうなっていた:
```
url=file:///Users/.../report.html
```
ChatGPT や Claude のURLが入っているはずなのに、全部 report.html。
provider 判定も全部空（`provider=`）。

**原因は3つあった:**

#### 原因A: `close every window` が全部壊していた

修正前の `start` コマンドは、最初に **Safari の全ウィンドウを閉じていた**:
```applescript
-- 修正前（ダメだったコード）
tell application "Safari"
  close every window    ← これが元凶
end tell
```
これをやると:
- extra ウィンドウも巻き添えで消える
- Safari が「全部閉じられた」と判断して、セッション復元で report.html を自動的に開く

#### 原因B: `make new document` + `set URL` のレースコンディション

修正前はウィンドウをこう作っていた:
```applescript
-- 修正前（ダメだったコード）
make new document                    ← まず空のウィンドウを作る
set URL of front document to openUrl ← その後URLを設定する
```
この2行の間に Safari が勝手に report.html を読み込んでしまい、
`set URL` が無視されるか、上書きされていた。
これが「レースコンディション（タイミング競合）」。

#### 原因C: `open location` は新タブに吸収された

原因B を直すために最初に試したのが `open location`:
```applescript
-- 試したけどダメだったコード
open location openUrl
```
しかし Safari は `open location` を「既存ウィンドウの新しいタブ」として開いてしまった。
結果:
- 1つのウィンドウに chatgpt, gemini, claude, grok, perplexity が全部タブとして入った
- タブ1は相変わらず report.html
- `debug` は `URL of tab 1` しか見ていないので全部 report.html に見えた

### 問題2: extra ウィンドウが増殖する

**症状:**
`close` → `start` を繰り返すたびに、保存していないウィンドウが増えていった。

**原因:**
- `close every window` で extra も消してから、STATE_FILE から復元していた
- しかし STATE_FILE は復元後もクリアされていなかった
- 次の `close` で「復元された extra」がまた保存される
- 次の `start` でまた復元される → 毎回同じものが増える

---

## 何を修正したか

### 修正1: `close every window` を廃止

```bash
# 修正後
start_fresh_managed_windows() {
  # managed だけを閉じる（extra は残す）
  close_managed_windows 2>/dev/null || true
  ...
}
```
**変更点:** `close every window` を使わず、managed ウィンドウだけを ID 指定で閉じるようにした。
extra ウィンドウは一切触らない。

### 修正2: `make new document with properties {URL:...}` を使用

```applescript
-- 修正後
set newDoc to make new document with properties {URL:openUrl}
delay 0.5
```
**変更点:** URLを「後から設定」するのではなく、ウィンドウ作成時に一発で指定する。
これで Safari が勝手に report.html を挟む隙がなくなる。

### 修正3: Safari が自動挿入する余分タブを除去

修正2 でも Safari はなぜか report.html をタブ1に自動挿入してきた。
（Safari のセッション復元機能が原因と推測）

そこで、ウィンドウ作成直後に「目的URL以外のタブを全部閉じる」処理を追加:
```applescript
-- 修正後: 余分タブを除去するロジック
if (count of tabs of winRef) > 1 then
  -- 目的URLのタブを探す
  set targetTabIndex to -1
  repeat with tidx from 1 to (count of tabs of winRef)
    if (URL of tab tidx of winRef as text) contains openUrl then
      set targetTabIndex to tidx
      exit repeat
    end if
  end repeat
  -- それ以外を後ろから閉じる
  if targetTabIndex > 0 then
    repeat with tidx from (count of tabs of winRef) to 1 by -1
      if tidx is not targetTabIndex then
        close tab tidx of winRef
      end if
    end repeat
  end if
end if
```

### 修正4: STATE_FILE を復元後にクリア（増殖防止）

```bash
# 修正後
start)
  start_fresh_managed_windows
  if [[ "$ENABLE_EXTRA_STATE" == "true" ]]; then
    restore_saved_extra_windows
    : > "$STATE_FILE"    ← 復元したら即クリア
  fi
  ...
```
**変更点:** extra を復元した直後に STATE_FILE を空にする。
これで「同じ extra が何度も復元される」増殖が起きなくなった。

### 修正5: `reassert_managed_urls` を削除

修正前は `start` フローの最後に「managed ウィンドウの URL を再設定する」処理があった。
修正2 で最初から正しいURLで開くようになったので不要になり、削除した。

---

## 修正前後の比較

### start フロー

| ステップ | 修正前 | 修正後 |
|---|---|---|
| 1 | `close every window`（全部消す） | `close_managed_windows`（managed だけ消す） |
| 2 | `make new document` + `set URL`（レース発生） | `make new document with properties {URL:...}`（一発指定） |
| 3 | - | 余分タブを自動除去 |
| 4 | extra 復元 | extra 復元 |
| 5 | - | STATE_FILE クリア（増殖防止） |
| 6 | `reassert_managed_urls`（URL再設定、効かない） | 削除（不要） |
| 7 | relayout | relayout |

### debug 出力

**修正前:**
```
id=21379 tag=managed#5 expected=perplexity provider= bounds=... url=file:///...report.html
id=21374 tag=managed#4 expected=grok      provider= bounds=... url=file:///...report.html
id=21369 tag=managed#3 expected=claude     provider= bounds=... url=file:///...report.html
id=21363 tag=managed#2 expected=gemini     provider= bounds=... url=file:///...report.html
id=21360 tag=managed#1 expected=chatgpt    provider= bounds=... url=file:///...report.html
```
→ 全部 report.html、provider 判定も全部空

**修正後:**
```
id=21652 tag=managed#5 expected=perplexity provider= bounds=... url=https://www.perplexity.ai/
id=21650 tag=managed#4 expected=grok       provider= bounds=... url=https://grok.com/
id=21647 tag=managed#3 expected=claude     provider= bounds=... url=https://claude.ai/new
id=21645 tag=managed#2 expected=gemini     provider= bounds=... url=https://gemini.google.com/app
id=21643 tag=managed#1 expected=chatgpt    provider= bounds=... url=https://chatgpt.com/
```
→ 全部正しいURL

---

## 学んだこと（Safari + AppleScript の罠）

1. **Safari は全ウィンドウを閉じると勝手にセッション復元する。** `close every window` は使わない方がいい。
2. **`set URL of front document` はタイミング次第で無視される。** `make new document with properties {URL:...}` の方が確実。
3. **`open location` は既存ウィンドウの新タブに入る。** 新ウィンドウを作りたい場合は `make new document` を使う。
4. **Safari は `make new document` でも余分なタブを挟むことがある。** 作成後にタブを掃除する処理が必要。
5. **状態ファイルは復元後にクリアしないと、同じデータが何度も復元されて増殖する。**

---

## 残っている軽微な問題

- `favorites://`（スタートページ）のウィンドウが extra として1つ残る。
  Safari が全 managed 閉じた後に自動生成するもので、実害なし。
  `EXCLUDED_URL_PATTERNS` に `"favorites://"` を追加すれば保存対象から除外可能。
