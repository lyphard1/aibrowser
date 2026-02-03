# 修正記録 2026-02-03

## 概要

Safari AI Window Orchestrator の `ai_window_tool.sh` に存在していた3つの重大なバグを修正しました。

---

## 修正前に起きていた問題

### 問題1: 全ウィンドウが `report.html` になる

**症状:**
`start` を実行すると、managed 5窓（ChatGPT, Gemini, Claude, Grok, Perplexity）が全て `report.html` になってしまう。`debug` で確認すると provider 判定も空。

**原因:**

1. `close every window` が Safari のセッション復元を発動させ、`report.html` を自動的に開いていた
2. `make new document` + `set URL of front document` の間にタイミング差があり、Safari がデフォルトページを先に読み込んでしまう（レースコンディション）
3. `open location` を使うと、新ウィンドウではなく既存ウィンドウの新タブとして開かれてしまう

### 問題2: extra ウィンドウが増殖する

**症状:**
`close` → `start` を繰り返すたびに、同じ extra ウィンドウが何度も復元されて増えていく。

**原因:**
- STATE_FILE が復元後にクリアされていなかった
- 次の `close` で再保存 → 次の `start` で再復元 → 無限ループ

### 問題3: 複数タブを持つ extra ウィンドウが一部保存されない

**症状:**
Gmail + X のように2タブあるウィンドウと、YouTube の1タブウィンドウがある場合、片方しか保存されない。

**原因:**
- AppleScript がウィンドウを閉じながらループを回していた
- ウィンドウを閉じた瞬間に window index がずれ、次のウィンドウがスキップされる

---

## 修正内容

### 修正1: `close every window` を廃止

```bash
# 修正前
tell application "Safari"
  close every window  # 全ウィンドウを破壊
end tell

# 修正後
close_managed_windows 2>/dev/null || true  # managed のみを ID 指定で閉じる
```

### 修正2: `make new document with properties {URL:...}` を使用

```applescript
-- 修正前（レースコンディション発生）
make new document
set URL of front document to openUrl

-- 修正後（一発でURL指定）
set newDoc to make new document with properties {URL:openUrl}
delay 0.5
```

### 修正3: Safari が自動挿入する余分タブを除去

```applescript
-- 修正後: ウィンドウ作成後に目的URL以外のタブを閉じる
if (count of tabs of winRef) > 1 then
  -- 目的URLのタブ番号を探す
  set targetTabIndex to -1
  repeat with tidx from 1 to (count of tabs of winRef)
    try
      if (URL of tab tidx of winRef as text) contains openUrl then
        set targetTabIndex to tidx
        exit repeat
      end if
    end try
  end repeat
  -- それ以外を後ろから閉じる
  if targetTabIndex > 0 then
    repeat with tidx from (count of tabs of winRef) to 1 by -1
      if tidx is not targetTabIndex then
        try
          close tab tidx of winRef
        end try
      end if
    end repeat
  end if
end if
```

### 修正4: extra 保存時にデータ収集と閉じる処理を分離

```applescript
-- 修正前: ループ中にウィンドウを閉じていた
repeat with winIndex from totalWindows to 1 by -1
  -- ... データ収集 ...
  close winRef  -- ここで index がずれる
end repeat

-- 修正後: 先に全データを収集してから、最後にまとめて閉じる
set windowsToClose to {}
repeat with winRef in windows
  -- ... データ収集 ...
  set end of windowsToClose to winId
end repeat

-- データ収集完了後にまとめて閉じる
repeat with closeId in windowsToClose
  -- ID で検索して閉じる
end repeat
```

### 修正5: managed_ids が空でも extra を保存

```bash
# 修正前
save_and_close_extra_windows() {
  if [[ ! -f "$MANAGED_IDS_FILE" ]]; then
    : > "$STATE_FILE"
    return  # ここで抜けてしまい、extra が保存されない
  fi

# 修正後
save_and_close_extra_windows() {
  local managed_ids=""
  if [[ -f "$MANAGED_IDS_FILE" ]]; then
    managed_ids="$(cat "$MANAGED_IDS_FILE")"
  fi
  # managed_ids が空でも処理を続行
```

### 修正6: 復元後に STATE_FILE をクリア

```bash
# 修正後
start)
  start_fresh_managed_windows
  if [[ "$ENABLE_EXTRA_STATE" == "true" ]]; then
    restore_saved_extra_windows
    : > "$STATE_FILE"  # 復元したら即クリア（増殖防止）
  fi
```

---

## 修正後の動作確認

### debug 出力例（正常）

```
id=23060 tag=managed#5 expected=perplexity provider= bounds=4512,30,6016,1336 url=https://www.perplexity.ai/
id=23058 tag=managed#4 expected=grok provider= bounds=3008,30,4512,1336 url=https://grok.com/
id=23055 tag=managed#3 expected=claude provider= bounds=2005,30,3008,1336 url=https://claude.ai/new
id=23053 tag=managed#2 expected=gemini provider= bounds=1002,30,2005,1336 url=https://gemini.google.com/app
id=23051 tag=managed#1 expected=chatgpt provider= bounds=0,30,1003,1336 url=https://chatgpt.com/
id=23025 tag=extra expected= provider= bounds=3008,59,4512,1365 url=https://www.google.com/
```

### STATE_FILE 例（正常）

```
3008,59,4512,1365<|FIELD|>https://www.youtube.com/<|WIN|>4512,30,6016,1336<|FIELD|>https://mail.google.com/mail/u/0/#inbox<|TAB|>https://x.com/home
```

- 1つ目のウィンドウ: YouTube (1タブ)
- 2つ目のウィンドウ: Gmail + X (2タブ)

---

## 学んだこと（Safari + AppleScript の罠）

1. **Safari は全ウィンドウを閉じると勝手にセッション復元する。** `close every window` は使わない方がいい。

2. **`set URL of front document` はタイミング次第で無視される。** `make new document with properties {URL:...}` の方が確実。

3. **`open location` は既存ウィンドウの新タブに入る。** 新ウィンドウを作りたい場合は `make new document` を使う。

4. **Safari は `make new document` でも余分なタブを挟むことがある。** 作成後にタブを掃除する処理が必要。

5. **AppleScript でウィンドウを閉じながらループすると index がずれる。** データ収集と閉じる処理は分離する。

6. **状態ファイルは復元後にクリアしないと、同じデータが何度も復元されて増殖する。**
