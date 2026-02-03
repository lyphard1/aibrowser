#!/usr/bin/env bash
set -euo pipefail

# Safari AI window orchestrator
# - start: open missing windows only, then relayout
# - relayout: relayout existing managed windows only
# - close: close managed windows only

MODE="${1:-relayout}"

# ------------------------------------------------------------
# User settings (edit here)
# ------------------------------------------------------------

# Window definitions (id -> url + match patterns)
# To add a new managed window type:
# 1) Add id to PROVIDER_IDS
# 2) Add start URL to PROVIDER_URLS (same index)
# 3) Add match patterns to PROVIDER_MATCHES (same index, comma-separated)
PROVIDER_IDS=(
  "chatgpt"
  "gemini"
  "claude"
  "grok"
  "perplexity"
)

PROVIDER_URLS=(
  "https://chatgpt.com/"
  "https://gemini.google.com/"
  "https://claude.ai/"
  "https://grok.com/"
  "https://www.perplexity.ai/"
)

PROVIDER_MATCHES=(
  "chatgpt.com,chat.openai.com"
  "gemini.google.com"
  "claude.ai"
  "grok.x.ai,grok.com"
  "perplexity.ai"
)

# Group definitions
# You can add groups by extending GROUP_NAMES and creating matching GROUP_<NAME>_* vars.
GROUP_NAMES=("A" "B")

GROUP_A_IDS=(
  "chatgpt"
  "gemini"
  "claude"
)
GROUP_A_BOUNDS="0,30,3008,1662"
GROUP_A_WINDOW_SCALE="1.0"
GROUP_A_HEIGHT_SCALE="0.8"

# "right" or "left" (monitor 2 position relative to monitor 1)
SECOND_MONITOR_SIDE="${SECOND_MONITOR_SIDE:-right}"

GROUP_B_IDS=(
  "grok"
  "perplexity"
)
if [[ "$SECOND_MONITOR_SIDE" == "left" ]]; then
  GROUP_B_BOUNDS="-3008,30,0,1662"
else
  GROUP_B_BOUNDS="3008,30,6016,1662"
fi
GROUP_B_WINDOW_SCALE="1.0"
GROUP_B_HEIGHT_SCALE="0.8"

# Delay (seconds) after opening windows in `start` mode.
OPEN_SETTLE_SECONDS="${OPEN_SETTLE_SECONDS:-1.0}"
STATE_FILE="${STATE_FILE:-$HOME/.ai_window_tool_extra_windows.state}"
ENABLE_EXTRA_STATE="${ENABLE_EXTRA_STATE:-true}"
MANAGED_IDS_FILE="${MANAGED_IDS_FILE:-$HOME/.ai_window_tool_managed_ids.state}"

# URLs containing these patterns are ignored when saving/restoring extra windows.
EXCLUDED_URL_PATTERNS=(
  "file:///Users/maedahideki/Desktop/work/python/tradelog/normalized_csv/report.html"
  "safari-resource:/"
)

# ------------------------------------------------------------

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/ai_window_tool.sh relayout
  ./scripts/ai_window_tool.sh start
  ./scripts/ai_window_tool.sh close
  ./scripts/ai_window_tool.sh debug

Modes:
  relayout  Re-arrange existing managed Safari windows only.
  start     Open missing managed windows, optionally restore saved extra windows, then re-arrange managed windows.
  close     Optionally save extra windows (bounds+tabs), then close managed windows.
  debug     Print Safari window provider+bounds for diagnosis.
USAGE
}

start_fresh_managed_windows() {
  # 既存 managed ウィンドウがあれば先に閉じる（extra は残す）
  close_managed_windows 2>/dev/null || true

  local group_defs_blob provider_url_pairs_pipe
  group_defs_blob="$(build_group_defs_blob)"
  provider_url_pairs_pipe="$(build_provider_url_pairs_pipe)"
  if [[ -z "$group_defs_blob" || -z "$provider_url_pairs_pipe" ]]; then
    return
  fi

  local managed_ids
  managed_ids="$(osascript - "$group_defs_blob" "$provider_url_pairs_pipe" <<'APPLESCRIPT'
on split_delim(inputText, delimiterText)
  if inputText is missing value then return {}
  set normalizedText to inputText as text
  if normalizedText is "" then return {}
  set AppleScript's text item delimiters to delimiterText
  set parts to text items of normalizedText
  set AppleScript's text item delimiters to ""
  return parts
end split_delim

on split_pipe(inputText)
  return my split_delim(inputText, "|")
end split_pipe

on join_list(textList, delimiterText)
  set listCount to count of textList
  if listCount is 0 then return ""
  set outputText to ""
  repeat with idx from 1 to listCount
    set currentText to item idx of textList as text
    if idx is 1 then
      set outputText to currentText
    else
      set outputText to outputText & delimiterText & currentText
    end if
  end repeat
  return outputText
end join_list

on parse_bounds(boundsText)
  set parts to my split_delim(boundsText, ",")
  if (count of parts) is not 4 then error "Invalid bounds: " & boundsText
  return {(item 1 of parts as integer), (item 2 of parts as integer), (item 3 of parts as integer), (item 4 of parts as integer)}
end parse_bounds

on parse_scale(scaleText)
  try
    set parsedScale to scaleText as real
    if parsedScale < 0.2 then return 0.2
    if parsedScale > 2.0 then return 2.0
    return parsedScale
  on error
    return 1.0
  end try
end parse_scale

on value_for_id(targetId, idValuePairs)
  repeat with pairText in idValuePairs
    set rawPair to pairText as text
    set pairItems to my split_delim(rawPair, "=")
    if (count of pairItems) is 2 then
      set pairId to item 1 of pairItems
      set pairValue to item 2 of pairItems
      if pairId is (targetId as text) then return pairValue
    end if
  end repeat
  return ""
end value_for_id

on tile_group(windowRefs, groupBounds, widthScale, heightScale)
  set windowCount to count of windowRefs
  if windowCount is 0 then return

  set leftEdge to item 1 of groupBounds
  set topEdge to item 2 of groupBounds
  set rightEdge to item 3 of groupBounds
  set bottomEdge to item 4 of groupBounds
  set groupWidth to rightEdge - leftEdge
  set groupHeight to bottomEdge - topEdge
  if groupWidth < 1 or groupHeight < 1 then return

  set targetHeight to round (groupHeight * heightScale)
  if targetHeight > groupHeight then set targetHeight to groupHeight
  if targetHeight < 1 then set targetHeight to 1
  set targetTopEdge to topEdge
  set targetBottomEdge to targetTopEdge + targetHeight

  if windowCount is 1 then
    set singleBaseWidth to groupWidth
    set singleTargetWidth to round (singleBaseWidth * widthScale)
    if singleTargetWidth > groupWidth then set singleTargetWidth to groupWidth
    if singleTargetWidth < 1 then set singleTargetWidth to 1
    set singleLeft to leftEdge + ((groupWidth - singleTargetWidth) div 2)
    set singleRight to singleLeft + singleTargetWidth
    tell application "Safari"
      set bounds of (item 1 of windowRefs) to {singleLeft, targetTopEdge, singleRight, targetBottomEdge}
    end tell
    return
  end if

  set baseWidth to groupWidth / windowCount
  set targetWidth to round (baseWidth * widthScale)
  if targetWidth > groupWidth then set targetWidth to groupWidth
  if targetWidth < 1 then set targetWidth to 1
  set stepWidth to (groupWidth - targetWidth) / (windowCount - 1)
  if stepWidth < 0 then set stepWidth to 0

  repeat with idx from 1 to windowCount
    set offsetWidth to round ((idx - 1) * stepWidth)
    set slotLeft to leftEdge + offsetWidth
    set slotRight to slotLeft + targetWidth
    if slotRight > rightEdge then
      set slotRight to rightEdge
      set slotLeft to slotRight - targetWidth
    end if
    if slotLeft < leftEdge then set slotLeft to leftEdge
    tell application "Safari"
      set bounds of (item idx of windowRefs) to {slotLeft, targetTopEdge, slotRight, targetBottomEdge}
    end tell
  end repeat
end tile_group

on run argv
  if (count of argv) < 2 then return ""
  set groupDefs to my split_delim(item 1 of argv, ";;;")
  set urlPairs to my split_pipe(item 2 of argv)
  if (count of groupDefs) is 0 then return ""

  tell application "Safari" to activate

  -- close every window は使わない（extra を壊すため）
  -- managed は bash 側で既に閉じ済み

  set managedIds to {}
  repeat with rawGroupDef in groupDefs
    set groupItems to my split_delim((rawGroupDef as text), ":::")
    if (count of groupItems) is 5 then
      set orderList to my split_pipe(item 2 of groupItems)
      set groupBounds to my parse_bounds(item 3 of groupItems)
      set widthScale to my parse_scale(item 4 of groupItems)
      set heightScale to my parse_scale(item 5 of groupItems)
      set groupWindows to {}

      repeat with wantedProvider in orderList
        set openUrl to my value_for_id((wantedProvider as text), urlPairs)
        if openUrl is not "" then
          tell application "Safari"
            set newDoc to make new document with properties {URL:openUrl}
            delay 0.5
            set winRef to front window
            -- Safari が自動挿入する余分なタブを除去（目的URL以外を閉じる）
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
              -- 目的タブ以外を後ろから閉じる
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
            set end of groupWindows to winRef
            set end of managedIds to (id of winRef as text)
          end tell
        end if
      end repeat

      my tile_group(groupWindows, groupBounds, widthScale, heightScale)
    end if
  end repeat

  return my join_list(managedIds, "|")
end run
APPLESCRIPT
)"

  printf "%s" "$managed_ids" > "$MANAGED_IDS_FILE"
}

relayout_by_managed_ids() {
  if [[ ! -f "$MANAGED_IDS_FILE" ]]; then
    return 1
  fi
  local managed_ids
  managed_ids="$(cat "$MANAGED_IDS_FILE")"
  if [[ -z "$managed_ids" ]]; then
    return 1
  fi
  local group_defs_blob
  group_defs_blob="$(build_group_defs_blob)"
  if [[ -z "$group_defs_blob" ]]; then
    return 1
  fi

  osascript - "$group_defs_blob" "$managed_ids" <<'APPLESCRIPT'
on split_delim(inputText, delimiterText)
  if inputText is missing value then return {}
  set normalizedText to inputText as text
  if normalizedText is "" then return {}
  set AppleScript's text item delimiters to delimiterText
  set parts to text items of normalizedText
  set AppleScript's text item delimiters to ""
  return parts
end split_delim

on split_pipe(inputText)
  return my split_delim(inputText, "|")
end split_pipe

on parse_bounds(boundsText)
  set parts to my split_delim(boundsText, ",")
  if (count of parts) is not 4 then error "Invalid bounds: " & boundsText
  return {(item 1 of parts as integer), (item 2 of parts as integer), (item 3 of parts as integer), (item 4 of parts as integer)}
end parse_bounds

on parse_scale(scaleText)
  try
    set parsedScale to scaleText as real
    if parsedScale < 0.2 then return 0.2
    if parsedScale > 2.0 then return 2.0
    return parsedScale
  on error
    return 1.0
  end try
end parse_scale

on window_by_id(targetIdText)
  tell application "Safari"
    repeat with winRef in windows
      try
        if (id of winRef as text) is targetIdText then return winRef
      end try
    end repeat
  end tell
  return missing value
end window_by_id

on tile_group(windowRefs, groupBounds, widthScale, heightScale)
  set windowCount to count of windowRefs
  if windowCount is 0 then return
  set leftEdge to item 1 of groupBounds
  set topEdge to item 2 of groupBounds
  set rightEdge to item 3 of groupBounds
  set bottomEdge to item 4 of groupBounds
  set groupWidth to rightEdge - leftEdge
  set groupHeight to bottomEdge - topEdge
  if groupWidth < 1 or groupHeight < 1 then return

  set targetHeight to round (groupHeight * heightScale)
  if targetHeight > groupHeight then set targetHeight to groupHeight
  if targetHeight < 1 then set targetHeight to 1
  set targetTopEdge to topEdge
  set targetBottomEdge to targetTopEdge + targetHeight

  if windowCount is 1 then
    set singleBaseWidth to groupWidth
    set singleTargetWidth to round (singleBaseWidth * widthScale)
    if singleTargetWidth > groupWidth then set singleTargetWidth to groupWidth
    if singleTargetWidth < 1 then set singleTargetWidth to 1
    set singleLeft to leftEdge + ((groupWidth - singleTargetWidth) div 2)
    set singleRight to singleLeft + singleTargetWidth
    tell application "Safari"
      set bounds of (item 1 of windowRefs) to {singleLeft, targetTopEdge, singleRight, targetBottomEdge}
    end tell
    return
  end if

  set baseWidth to groupWidth / windowCount
  set targetWidth to round (baseWidth * widthScale)
  if targetWidth > groupWidth then set targetWidth to groupWidth
  if targetWidth < 1 then set targetWidth to 1
  set stepWidth to (groupWidth - targetWidth) / (windowCount - 1)
  if stepWidth < 0 then set stepWidth to 0

  repeat with idx from 1 to windowCount
    set offsetWidth to round ((idx - 1) * stepWidth)
    set slotLeft to leftEdge + offsetWidth
    set slotRight to slotLeft + targetWidth
    if slotRight > rightEdge then
      set slotRight to rightEdge
      set slotLeft to slotRight - targetWidth
    end if
    if slotLeft < leftEdge then set slotLeft to leftEdge
    tell application "Safari"
      set bounds of (item idx of windowRefs) to {slotLeft, targetTopEdge, slotRight, targetBottomEdge}
    end tell
  end repeat
end tile_group

on run argv
  if (count of argv) < 2 then return
  set groupDefs to my split_delim(item 1 of argv, ";;;")
  set managedIds to my split_pipe(item 2 of argv)
  if (count of groupDefs) is 0 or (count of managedIds) is 0 then return

  set cursorIndex to 1
  repeat with rawGroupDef in groupDefs
    set groupItems to my split_delim((rawGroupDef as text), ":::")
    if (count of groupItems) is 5 then
      set orderList to my split_pipe(item 2 of groupItems)
      set slotCount to count of orderList
      set groupBounds to my parse_bounds(item 3 of groupItems)
      set widthScale to my parse_scale(item 4 of groupItems)
      set heightScale to my parse_scale(item 5 of groupItems)
      set groupWindows to {}

      repeat with idx from 1 to slotCount
        if cursorIndex <= (count of managedIds) then
          set targetIdText to item cursorIndex of managedIds as text
          set cursorIndex to cursorIndex + 1
          set winRef to my window_by_id(targetIdText)
          if winRef is not missing value then set end of groupWindows to winRef
        end if
      end repeat

      my tile_group(groupWindows, groupBounds, widthScale, heightScale)
    end if
  end repeat
  tell application "Safari" to activate
end run
APPLESCRIPT
}

reassert_managed_urls() {
  if [[ ! -f "$MANAGED_IDS_FILE" ]]; then
    return
  fi
  local managed_ids desired_ids_pipe provider_url_pairs_pipe
  managed_ids="$(cat "$MANAGED_IDS_FILE")"
  desired_ids_pipe="$(build_desired_ids_pipe)"
  provider_url_pairs_pipe="$(build_provider_url_pairs_pipe)"
  if [[ -z "$managed_ids" || -z "$desired_ids_pipe" || -z "$provider_url_pairs_pipe" ]]; then
    return
  fi

  osascript - "$managed_ids" "$desired_ids_pipe" "$provider_url_pairs_pipe" <<'APPLESCRIPT'
on split_delim(inputText, delimiterText)
  if inputText is missing value then return {}
  set normalizedText to inputText as text
  if normalizedText is "" then return {}
  set AppleScript's text item delimiters to delimiterText
  set parts to text items of normalizedText
  set AppleScript's text item delimiters to ""
  return parts
end split_delim

on split_pipe(inputText)
  return my split_delim(inputText, "|")
end split_pipe

on value_for_id(targetId, idValuePairs)
  repeat with pairText in idValuePairs
    set rawPair to pairText as text
    set pairItems to my split_delim(rawPair, "=")
    if (count of pairItems) is 2 then
      set pairId to item 1 of pairItems
      set pairValue to item 2 of pairItems
      if pairId is (targetId as text) then return pairValue
    end if
  end repeat
  return ""
end value_for_id

on run argv
  if (count of argv) < 3 then return
  set managedIds to my split_pipe(item 1 of argv)
  set desiredIds to my split_pipe(item 2 of argv)
  set urlPairs to my split_pipe(item 3 of argv)
  if (count of managedIds) is 0 then return

  tell application "Safari"
    repeat with idx from 1 to (count of managedIds)
      if idx ≤ (count of desiredIds) then
        set targetWindowId to item idx of managedIds as text
        set providerId to item idx of desiredIds as text
        set targetUrl to my value_for_id(providerId, urlPairs)
        if targetUrl is not "" then
          repeat with winRef in windows
            try
              if (id of winRef as text) is targetWindowId then
                try
                  set URL of tab 1 of winRef to targetUrl
                end try
                exit repeat
              end if
            end try
          end repeat
        end if
      end if
    end repeat
  end tell
end run
APPLESCRIPT
}

join_by_delim() {
  local delimiter="$1"
  shift
  local result=""
  local item
  for item in "$@"; do
    if [[ -z "$item" ]]; then
      continue
    fi
    if [[ -n "$result" ]]; then
      result="${result}${delimiter}${item}"
    else
      result="${item}"
    fi
  done
  printf "%s" "$result"
}

join_by_pipe() {
  join_by_delim "|" "$@"
}

build_excluded_url_patterns_pipe() {
  join_by_pipe "${EXCLUDED_URL_PATTERNS[@]}"
}

build_provider_url_pairs_pipe() {
  local pairs=()
  local index
  for index in "${!PROVIDER_IDS[@]}"; do
    local provider_id="${PROVIDER_IDS[$index]:-}"
    local provider_url="${PROVIDER_URLS[$index]:-}"
    if [[ -n "$provider_id" && -n "$provider_url" ]]; then
      pairs+=("${provider_id}=${provider_url}")
    fi
  done
  join_by_pipe "${pairs[@]}"
}

build_provider_match_pairs_pipe() {
  local pairs=()
  local index
  for index in "${!PROVIDER_IDS[@]}"; do
    local provider_id="${PROVIDER_IDS[$index]:-}"
    local provider_match="${PROVIDER_MATCHES[$index]:-}"
    if [[ -n "$provider_id" && -n "$provider_match" ]]; then
      pairs+=("${provider_id}=${provider_match}")
    fi
  done
  join_by_pipe "${pairs[@]}"
}

build_desired_ids_pipe() {
  local desired_ids=()
  local group_name
  for group_name in "${GROUP_NAMES[@]}"; do
    local group_ids
    eval "group_ids=(\"\${GROUP_${group_name}_IDS[@]}\")"
    local current_id
    for current_id in "${group_ids[@]}"; do
      if [[ -n "$current_id" ]]; then
        desired_ids+=("$current_id")
      fi
    done
  done
  join_by_pipe "${desired_ids[@]}"
}

build_group_defs_blob() {
  local defs=()
  local group_name
  for group_name in "${GROUP_NAMES[@]}"; do
    local group_ids group_bounds group_width_scale group_height_scale
    eval "group_ids=(\"\${GROUP_${group_name}_IDS[@]}\")"
    eval "group_bounds=\"\${GROUP_${group_name}_BOUNDS:-}\""
    eval "group_width_scale=\"\${GROUP_${group_name}_WINDOW_SCALE:-1.0}\""
    eval "group_height_scale=\"\${GROUP_${group_name}_HEIGHT_SCALE:-1.0}\""

    if [[ -z "$group_bounds" ]]; then
      continue
    fi

    local ids_pipe
    ids_pipe="$(join_by_pipe "${group_ids[@]}")"
    if [[ -z "$ids_pipe" ]]; then
      continue
    fi

    defs+=("${group_name}:::${ids_pipe}:::${group_bounds}:::${group_width_scale}:::${group_height_scale}")
  done

  join_by_delim ";;;" "${defs[@]}"
}

open_missing_windows() {
  local desired_ids_pipe provider_url_pairs_pipe provider_match_pairs_pipe
  desired_ids_pipe="$(build_desired_ids_pipe)"
  provider_url_pairs_pipe="$(build_provider_url_pairs_pipe)"
  provider_match_pairs_pipe="$(build_provider_match_pairs_pipe)"

  if [[ -z "$desired_ids_pipe" || -z "$provider_url_pairs_pipe" || -z "$provider_match_pairs_pipe" ]]; then
    return
  fi

  osascript - "$desired_ids_pipe" "$provider_url_pairs_pipe" "$provider_match_pairs_pipe" <<'APPLESCRIPT'
on split_delim(inputText, delimiterText)
  if inputText is missing value then return {}
  set normalizedText to inputText as text
  if normalizedText is "" then return {}
  set AppleScript's text item delimiters to delimiterText
  set parts to text items of normalizedText
  set AppleScript's text item delimiters to ""
  return parts
end split_delim

on split_pipe(inputText)
  return my split_delim(inputText, "|")
end split_pipe

on split_csv(inputText)
  return my split_delim(inputText, ",")
end split_csv

on provider_from_url(rawUrl, matchPairs)
  set targetUrl to rawUrl as text
  repeat with pairText in matchPairs
    set rawPair to pairText as text
    set pairItems to my split_delim(rawPair, "=")
    if (count of pairItems) is 2 then
      set providerId to item 1 of pairItems
      set patternText to item 2 of pairItems
      set patterns to my split_csv(patternText)
      repeat with patternValue in patterns
        set currentPattern to patternValue as text
        if currentPattern is not "" then
          if targetUrl contains currentPattern then return providerId
        end if
      end repeat
    end if
  end repeat
  return ""
end provider_from_url

on provider_from_window(winRef, matchPairs)
  try
    repeat with tabRef in tabs of winRef
      try
        set tabUrl to URL of tabRef
        set providerId to my provider_from_url(tabUrl, matchPairs)
        if providerId is not "" then return providerId
      end try
    end repeat
  end try
  return ""
end provider_from_window

on count_of_id(idList, targetId)
  set totalCount to 0
  repeat with currentId in idList
    if (currentId as text) is (targetId as text) then
      set totalCount to totalCount + 1
    end if
  end repeat
  return totalCount
end count_of_id

on value_for_id(targetId, idValuePairs)
  repeat with pairText in idValuePairs
    set rawPair to pairText as text
    set pairItems to my split_delim(rawPair, "=")
    if (count of pairItems) is 2 then
      set pairId to item 1 of pairItems
      set pairValue to item 2 of pairItems
      if pairId is (targetId as text) then return pairValue
    end if
  end repeat
  return ""
end value_for_id

on run argv
  if (count of argv) < 3 then return

  set desiredIds to my split_pipe(item 1 of argv)
  set urlPairs to my split_pipe(item 2 of argv)
  set matchPairs to my split_pipe(item 3 of argv)
  if (count of desiredIds) is 0 then return

  set existingIds to {}

  tell application "Safari"
    activate

    repeat with winRef in windows
      try
        set providerId to my provider_from_window(winRef, matchPairs)
        if providerId is not "" then
          set end of existingIds to providerId
        end if
      end try
    end repeat

    set scheduledIds to {}
    repeat with wantedId in desiredIds
      set wantedProviderId to wantedId as text
      set wantedCount to my count_of_id(desiredIds, wantedProviderId)
      set currentCount to (my count_of_id(existingIds, wantedProviderId)) + (my count_of_id(scheduledIds, wantedProviderId))

      if currentCount < wantedCount then
        set openUrl to my value_for_id(wantedProviderId, urlPairs)
        if openUrl is not "" then
          make new document
          set URL of front document to openUrl
          set end of scheduledIds to wantedProviderId
        end if
      end if
    end repeat
  end tell
end run
APPLESCRIPT
}

close_managed_windows() {
  if [[ ! -f "$MANAGED_IDS_FILE" ]]; then
    return
  fi
  local managed_ids
  managed_ids="$(cat "$MANAGED_IDS_FILE")"
  if [[ -z "$managed_ids" ]]; then
    return
  fi

  set +e
  osascript - "$managed_ids" <<'APPLESCRIPT'
on split_delim(inputText, delimiterText)
  if inputText is missing value then return {}
  set normalizedText to inputText as text
  if normalizedText is "" then return {}
  set AppleScript's text item delimiters to delimiterText
  set parts to text items of normalizedText
  set AppleScript's text item delimiters to ""
  return parts
end split_delim

on split_pipe(inputText)
  return my split_delim(inputText, "|")
end split_pipe

on run argv
  if (count of argv) < 1 then return
  set managedIds to my split_pipe(item 1 of argv)
  if (count of managedIds) is 0 then return

  tell application "Safari"
    activate
    repeat with targetId in managedIds
      set targetText to targetId as text
      repeat with winRef in windows
        try
          if (id of winRef as text) is targetText then
            close winRef
            exit repeat
          end if
        end try
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT
  local script_status=$?
  set -e
  return "$script_status"
}

save_and_close_extra_windows() {
  # managed_ids が空/ファイルなしでも全ウィンドウを extra として保存する
  local managed_ids=""
  if [[ -f "$MANAGED_IDS_FILE" ]]; then
    managed_ids="$(cat "$MANAGED_IDS_FILE")"
  fi
  local excluded_url_patterns_pipe
  excluded_url_patterns_pipe="$(build_excluded_url_patterns_pipe)"

  local serialized_state
  local script_status=0
  set +e
  serialized_state="$(osascript - "$managed_ids" "$excluded_url_patterns_pipe" <<'APPLESCRIPT'
on split_delim(inputText, delimiterText)
  if inputText is missing value then return {}
  set normalizedText to inputText as text
  if normalizedText is "" then return {}
  set AppleScript's text item delimiters to delimiterText
  set parts to text items of normalizedText
  set AppleScript's text item delimiters to ""
  return parts
end split_delim

on split_pipe(inputText)
  return my split_delim(inputText, "|")
end split_pipe

on join_list(textList, delimiterText)
  set listCount to count of textList
  if listCount is 0 then return ""
  set outputText to ""
  repeat with idx from 1 to listCount
    set currentText to item idx of textList as text
    if idx is 1 then
      set outputText to currentText
    else
      set outputText to outputText & delimiterText & currentText
    end if
  end repeat
  return outputText
end join_list

on should_store_url(urlText, excludedPatterns)
  if urlText is "" or urlText is "missing value" then return false
  repeat with patternText in excludedPatterns
    set currentPattern to patternText as text
    if currentPattern is not "" then
      if (urlText as text) contains currentPattern then return false
    end if
  end repeat
  return true
end should_store_url

on run argv
  if (count of argv) < 2 then return ""
  set managedIds to my split_pipe(item 1 of argv)
  set excludedPatterns to my split_pipe(item 2 of argv)

  set windowDelimiter to "<|WIN|>"
  set fieldDelimiter to "<|FIELD|>"
  set tabDelimiter to "<|TAB|>"
  set serializedWindows to {}
  set windowsToClose to {}

  tell application "Safari"
    activate
    -- まず全ウィンドウのデータを収集（閉じない）
    repeat with winRef in windows
      try
        set winId to id of winRef as text
        set isManaged to false
        repeat with managedId in managedIds
          try
            if winId is (managedId as text) then
              set isManaged to true
              exit repeat
            end if
          end try
        end repeat

        if isManaged is false then
          set winBounds to bounds of winRef
          set boundsText to ((item 1 of winBounds as text) & "," & (item 2 of winBounds as text) & "," & (item 3 of winBounds as text) & "," & (item 4 of winBounds as text))

          set tabUrls to {}
          repeat with tabRef in tabs of winRef
            try
              set tabUrlText to (URL of tabRef as text)
              if my should_store_url(tabUrlText, excludedPatterns) then
                set end of tabUrls to tabUrlText
              end if
            end try
          end repeat

          if (count of tabUrls) > 0 then
            set tabsText to my join_list(tabUrls, tabDelimiter)
            set end of serializedWindows to (boundsText & fieldDelimiter & tabsText)
          end if
          -- 閉じるウィンドウのIDを記録
          set end of windowsToClose to winId
        end if
      end try
    end repeat

    -- データ収集完了後にまとめて閉じる
    repeat with closeId in windowsToClose
      try
        repeat with winRef in windows
          if (id of winRef as text) is (closeId as text) then
            close winRef
            exit repeat
          end if
        end repeat
      end try
    end repeat
  end tell

  return my join_list(serializedWindows, windowDelimiter)
end run
APPLESCRIPT
)"
  script_status=$?
  set -e
  if [[ "$script_status" -ne 0 ]]; then
    return "$script_status"
  fi

  if [[ -z "$serialized_state" ]]; then
    : > "$STATE_FILE"
  else
    printf "%s" "$serialized_state" > "$STATE_FILE"
  fi
}

restore_saved_extra_windows() {
  if [[ ! -f "$STATE_FILE" ]]; then
    return
  fi
  local serialized_state
  serialized_state="$(cat "$STATE_FILE")"
  if [[ -z "$serialized_state" ]]; then
    return
  fi

  local excluded_url_patterns_pipe
  excluded_url_patterns_pipe="$(build_excluded_url_patterns_pipe)"

  osascript - "$serialized_state" "$excluded_url_patterns_pipe" <<'APPLESCRIPT'
on split_delim(inputText, delimiterText)
  if inputText is missing value then return {}
  set normalizedText to inputText as text
  if normalizedText is "" then return {}
  set AppleScript's text item delimiters to delimiterText
  set parts to text items of normalizedText
  set AppleScript's text item delimiters to ""
  return parts
end split_delim

on parse_bounds(boundsText)
  set itemsList to my split_delim(boundsText, ",")
  if (count of itemsList) is not 4 then return {0, 30, 1200, 900}
  return {(item 1 of itemsList as integer), (item 2 of itemsList as integer), (item 3 of itemsList as integer), (item 4 of itemsList as integer)}
end parse_bounds

on split_pipe(inputText)
  return my split_delim(inputText, "|")
end split_pipe

on should_restore_url(urlText, excludedPatterns)
  if urlText is "" or urlText is "missing value" then return false
  repeat with patternText in excludedPatterns
    set currentPattern to patternText as text
    if currentPattern is not "" then
      if (urlText as text) contains currentPattern then return false
    end if
  end repeat
  return true
end should_restore_url

on run argv
  if (count of argv) < 2 then return
  set rawState to item 1 of argv
  set excludedPatterns to my split_pipe(item 2 of argv)
  if rawState is "" then return

  set windowDelimiter to "<|WIN|>"
  set fieldDelimiter to "<|FIELD|>"
  set tabDelimiter to "<|TAB|>"
  set serializedWindows to my split_delim(rawState, windowDelimiter)

  tell application "Safari"
    activate
    repeat with serializedWindow in serializedWindows
      set parts to my split_delim(serializedWindow as text, fieldDelimiter)
      if (count of parts) is not 2 then
        -- skip malformed record
      else
        set boundsText to item 1 of parts
        set tabsText to item 2 of parts
        set tabUrls to my split_delim(tabsText, tabDelimiter)
        if (count of tabUrls) > 0 then
          set firstUrl to item 1 of tabUrls
          if my should_restore_url(firstUrl, excludedPatterns) then
            make new document
            set URL of front document to firstUrl
            set winRef to front window
            set bounds of winRef to my parse_bounds(boundsText)
            if (count of tabUrls) > 1 then
              repeat with tabIndex from 2 to (count of tabUrls)
                set extraUrl to item tabIndex of tabUrls
                if my should_restore_url(extraUrl, excludedPatterns) then
                  set newTab to make new tab at end of tabs of winRef
                  set URL of newTab to extraUrl
                end if
              end repeat
            end if
          end if
        end if
      end if
    end repeat
  end tell
end run
APPLESCRIPT
}

relayout_managed_windows() {
  local group_defs_blob provider_match_pairs_pipe provider_url_pairs_pipe
  group_defs_blob="$(build_group_defs_blob)"
  provider_match_pairs_pipe="$(build_provider_match_pairs_pipe)"
  provider_url_pairs_pipe="$(build_provider_url_pairs_pipe)"

  if [[ -z "$group_defs_blob" || -z "$provider_match_pairs_pipe" || -z "$provider_url_pairs_pipe" ]]; then
    return
  fi

  osascript - "$group_defs_blob" "$provider_match_pairs_pipe" "$provider_url_pairs_pipe" <<'APPLESCRIPT'
on split_delim(inputText, delimiterText)
  if inputText is missing value then return {}
  set normalizedText to inputText as text
  if normalizedText is "" then return {}
  set AppleScript's text item delimiters to delimiterText
  set parts to text items of normalizedText
  set AppleScript's text item delimiters to ""
  return parts
end split_delim

on split_pipe(inputText)
  return my split_delim(inputText, "|")
end split_pipe

on split_csv(inputText)
  return my split_delim(inputText, ",")
end split_csv

on parse_bounds(boundsText)
  set parts to my split_delim(boundsText, ",")
  if (count of parts) is not 4 then error "Invalid bounds: " & boundsText
  return {(item 1 of parts as integer), (item 2 of parts as integer), (item 3 of parts as integer), (item 4 of parts as integer)}
end parse_bounds

on parse_scale(scaleText)
  try
    set parsedScale to scaleText as real
    if parsedScale < 0.2 then return 0.2
    if parsedScale > 2.0 then return 2.0
    return parsedScale
  on error
    return 1.0
  end try
end parse_scale

on value_for_id(targetId, idValuePairs)
  repeat with pairText in idValuePairs
    set rawPair to pairText as text
    set pairItems to my split_delim(rawPair, "=")
    if (count of pairItems) is 2 then
      set pairId to item 1 of pairItems
      set pairValue to item 2 of pairItems
      if pairId is (targetId as text) then return pairValue
    end if
  end repeat
  return ""
end value_for_id

on provider_from_url(rawUrl, matchPairs)
  set targetUrl to rawUrl as text
  repeat with pairText in matchPairs
    set rawPair to pairText as text
    set pairItems to my split_delim(rawPair, "=")
    if (count of pairItems) is 2 then
      set providerId to item 1 of pairItems
      set patternText to item 2 of pairItems
      set patterns to my split_csv(patternText)
      repeat with patternValue in patterns
        set currentPattern to patternValue as text
        if currentPattern is not "" then
          if targetUrl contains currentPattern then return providerId
        end if
      end repeat
    end if
  end repeat
  return ""
end provider_from_url

on provider_from_window(winRef, matchPairs)
  try
    repeat with tabRef in tabs of winRef
      try
        set tabUrl to URL of tabRef
        set providerId to my provider_from_url(tabUrl, matchPairs)
        if providerId is not "" then return providerId
      end try
    end repeat
  end try
  return ""
end provider_from_window

on list_contains(textList, targetText)
  repeat with currentValue in textList
    if (currentValue as text) is (targetText as text) then return true
  end repeat
  return false
end list_contains

on pick_window_for_provider(providerText, detectedWindows, usedWindowIds)
  repeat with tupleData in detectedWindows
    set tupleProvider to item 1 of tupleData
    set tupleWindowId to item 2 of tupleData
    set tupleWindowRef to item 3 of tupleData
    if tupleProvider is (providerText as text) and my list_contains(usedWindowIds, tupleWindowId as text) is false then
      return {tupleWindowRef, tupleWindowId as text}
    end if
  end repeat
  return {missing value, ""}
end pick_window_for_provider

on tile_group_by_slots(orderList, detectedWindows, usedWindowIds, groupBounds, widthScale, heightScale, urlPairs)
  set slotCount to count of orderList
  if slotCount is 0 then return usedWindowIds

  set leftEdge to item 1 of groupBounds
  set topEdge to item 2 of groupBounds
  set rightEdge to item 3 of groupBounds
  set bottomEdge to item 4 of groupBounds

  set groupWidth to rightEdge - leftEdge
  if groupWidth < 1 then return

  set groupHeight to bottomEdge - topEdge
  if groupHeight < 1 then return

  set targetHeight to round (groupHeight * heightScale)
  if targetHeight > groupHeight then set targetHeight to groupHeight
  if targetHeight < 1 then set targetHeight to 1

  set targetTopEdge to topEdge
  set targetBottomEdge to targetTopEdge + targetHeight

  set nextUsedIds to usedWindowIds

  if slotCount is 1 then
    set singleBaseWidth to groupWidth
    set singleTargetWidth to round (singleBaseWidth * widthScale)
    if singleTargetWidth > groupWidth then set singleTargetWidth to groupWidth
    if singleTargetWidth < 1 then set singleTargetWidth to 1
    set singleLeft to leftEdge + ((groupWidth - singleTargetWidth) div 2)
    set singleRight to singleLeft + singleTargetWidth
    set pickedData to my pick_window_for_provider((item 1 of orderList as text), detectedWindows, nextUsedIds)
    set pickedWindow to item 1 of pickedData
    set pickedWindowId to item 2 of pickedData
    if pickedWindow is missing value then
      set openUrl to my value_for_id((item 1 of orderList as text), urlPairs)
      if openUrl is not "" then
        tell application "Safari"
          make new document
          set URL of front document to openUrl
          set pickedWindow to front window
          set pickedWindowId to (id of pickedWindow as text)
        end tell
      end if
    end if
    if pickedWindowId is not "" then set end of nextUsedIds to pickedWindowId
    if pickedWindow is not missing value then
      tell application "Safari"
        set bounds of pickedWindow to {singleLeft, targetTopEdge, singleRight, targetBottomEdge}
      end tell
    end if
    return nextUsedIds
  end if

  set baseWidth to groupWidth / slotCount
  set targetWidth to round (baseWidth * widthScale)
  if targetWidth > groupWidth then set targetWidth to groupWidth
  if targetWidth < 1 then set targetWidth to 1

  set stepWidth to (groupWidth - targetWidth) / (slotCount - 1)
  if stepWidth < 0 then set stepWidth to 0

  repeat with idx from 1 to slotCount
    set offsetWidth to round ((idx - 1) * stepWidth)
    set slotLeft to leftEdge + offsetWidth
    set slotRight to slotLeft + targetWidth

    if slotRight > rightEdge then
      set slotRight to rightEdge
      set slotLeft to slotRight - targetWidth
    end if
    if slotLeft < leftEdge then set slotLeft to leftEdge

    set targetBounds to {slotLeft, targetTopEdge, slotRight, targetBottomEdge}
    set pickedData to my pick_window_for_provider((item idx of orderList as text), detectedWindows, nextUsedIds)
    set pickedWindow to item 1 of pickedData
    set pickedWindowId to item 2 of pickedData
    if pickedWindow is missing value then
      set openUrl to my value_for_id((item idx of orderList as text), urlPairs)
      if openUrl is not "" then
        tell application "Safari"
          make new document
          set URL of front document to openUrl
          set pickedWindow to front window
          set pickedWindowId to (id of pickedWindow as text)
        end tell
      end if
    end if
    if pickedWindowId is not "" then set end of nextUsedIds to pickedWindowId
    if pickedWindow is not missing value then
      tell application "Safari"
        set bounds of pickedWindow to targetBounds
      end tell
    end if
  end repeat
  return nextUsedIds
end tile_group_by_slots

on run argv
  if (count of argv) < 3 then return

  set groupDefs to my split_delim(item 1 of argv, ";;;")
  set matchPairs to my split_pipe(item 2 of argv)
  set urlPairs to my split_pipe(item 3 of argv)
  if (count of groupDefs) is 0 then return

  set detectedWindows to {}
  try
    tell application "Safari"
      repeat with winRef in windows
        try
          set providerId to my provider_from_window(winRef, matchPairs)
          if providerId is not "" then
            set end of detectedWindows to {providerId, id of winRef, winRef}
          end if
        end try
      end repeat
    end tell
  on error
    return
  end try

  set usedIds to {}
  repeat with rawGroupDef in groupDefs
    set groupItems to my split_delim((rawGroupDef as text), ":::")
    if (count of groupItems) is not 5 then
      -- skip invalid group
    else
      set orderList to my split_pipe(item 2 of groupItems)
      set groupBounds to my parse_bounds(item 3 of groupItems)
      set widthScale to my parse_scale(item 4 of groupItems)
      set heightScale to my parse_scale(item 5 of groupItems)

      set usedIds to my tile_group_by_slots(orderList, detectedWindows, usedIds, groupBounds, widthScale, heightScale, urlPairs)
    end if
  end repeat

  tell application "Safari" to activate
end run
APPLESCRIPT
}

debug_windows() {
  local provider_match_pairs_pipe managed_ids desired_ids_pipe
  provider_match_pairs_pipe="$(build_provider_match_pairs_pipe)"
  desired_ids_pipe="$(build_desired_ids_pipe)"
  managed_ids=""
  if [[ -f "$MANAGED_IDS_FILE" ]]; then
    managed_ids="$(cat "$MANAGED_IDS_FILE")"
  fi
  if [[ -z "$provider_match_pairs_pipe" ]]; then
    return
  fi

  osascript - "$provider_match_pairs_pipe" "$managed_ids" "$desired_ids_pipe" <<'APPLESCRIPT'
on split_delim(inputText, delimiterText)
  if inputText is missing value then return {}
  set normalizedText to inputText as text
  if normalizedText is "" then return {}
  set AppleScript's text item delimiters to delimiterText
  set parts to text items of normalizedText
  set AppleScript's text item delimiters to ""
  return parts
end split_delim

on split_pipe(inputText)
  return my split_delim(inputText, "|")
end split_pipe

on split_csv(inputText)
  return my split_delim(inputText, ",")
end split_csv

on list_index_of(textList, targetText)
  set idx to 1
  repeat with currentValue in textList
    if (currentValue as text) is (targetText as text) then return idx
    set idx to idx + 1
  end repeat
  return 0
end list_index_of

on provider_from_url(rawUrl, matchPairs)
  set targetUrl to rawUrl as text
  repeat with pairText in matchPairs
    set rawPair to pairText as text
    set pairItems to my split_delim(rawPair, "=")
    if (count of pairItems) is 2 then
      set providerId to item 1 of pairItems
      set patternText to item 2 of pairItems
      set patterns to my split_csv(patternText)
      repeat with patternValue in patterns
        set currentPattern to patternValue as text
        if currentPattern is not "" then
          if targetUrl contains currentPattern then return providerId
        end if
      end repeat
    end if
  end repeat
  return ""
end provider_from_url

on provider_from_window(winRef, matchPairs)
  try
    repeat with tabRef in tabs of winRef
      try
        set tabUrl to URL of tabRef
        set providerId to my provider_from_url(tabUrl, matchPairs)
        if providerId is not "" then return providerId
      end try
    end repeat
  end try
  return ""
end provider_from_window

on run argv
  if (count of argv) < 3 then return
  set matchPairs to my split_pipe(item 1 of argv)
  set managedIds to my split_pipe(item 2 of argv)
  set desiredIds to my split_pipe(item 3 of argv)
  tell application "Safari"
    repeat with winRef in windows
      try
        set providerId to my provider_from_window(winRef, matchPairs)
        set winIdText to (id of winRef as text)
        set managedIndex to my list_index_of(managedIds, winIdText)
        set managedTag to "extra"
        set expectedProvider to ""
        if managedIndex > 0 then
          set managedTag to "managed#" & (managedIndex as text)
          if managedIndex <= (count of desiredIds) then
            set expectedProvider to (item managedIndex of desiredIds as text)
          end if
        end if
        set b to bounds of winRef
        set u to ""
        try
          set u to URL of tab 1 of winRef
        end try
        log ("id=" & winIdText & " tag=" & managedTag & " expected=" & expectedProvider & " provider=" & providerId & " bounds=" & (item 1 of b as text) & "," & (item 2 of b as text) & "," & (item 3 of b as text) & "," & (item 4 of b as text) & " url=" & u)
      end try
    end repeat
  end tell
end run
APPLESCRIPT
}

case "$MODE" in
  relayout)
    if ! relayout_by_managed_ids; then
      relayout_managed_windows
    fi
    ;;
  start)
    start_fresh_managed_windows
    if [[ "$ENABLE_EXTRA_STATE" == "true" ]]; then
      restore_saved_extra_windows
      # 復元後に STATE_FILE をクリア（次回 start での増殖防止）
      : > "$STATE_FILE"
    fi
    sleep "$OPEN_SETTLE_SECONDS"
    if ! relayout_by_managed_ids; then
      relayout_managed_windows
    fi
    ;;
  close)
    if [[ "$ENABLE_EXTRA_STATE" == "true" ]]; then
      if ! save_and_close_extra_windows; then
        echo "warn: failed to save extra windows state; continuing with managed close only." >&2
      fi
    fi
    if ! close_managed_windows; then
      echo "warn: failed to close managed windows cleanly." >&2
    fi
    rm -f "$MANAGED_IDS_FILE"
    ;;
  debug)
    debug_windows
    ;;
  *)
    usage
    exit 1
    ;;
esac
