-- Safari AI window lock helper
-- Usage:
--   1) Copy this file to ~/.hammerspoon/ai_window_lock.lua
--   2) Add `require("ai_window_lock")` in ~/.hammerspoon/init.lua
--
-- Hotkeys (optional):
--   default is disabled to avoid key conflicts

local SCRIPT_PATH = os.getenv("HOME") .. "/projects/aibrowser/scripts/ai_window_tool.sh"
local AUTO_LOCK = false
local DEBOUNCE_SECONDS = 0.35
local REENTRY_GUARD_SECONDS = 0.80

local ENABLE_HOTKEYS = false
local START_HOTKEY_MODS = { "ctrl", "alt", "cmd" }
local START_HOTKEY_KEY = "S"
local RELAYOUT_HOTKEY_MODS = { "ctrl", "alt", "cmd" }
local RELAYOUT_HOTKEY_KEY = "L"

local function runTool(mode)
  local command = string.format("%q %s", SCRIPT_PATH, mode)
  hs.task.new("/bin/zsh", nil, { "-lc", command }):start()
end

local function setupHotkeys()
  if not ENABLE_HOTKEYS then
    return
  end

  hs.hotkey.bind(START_HOTKEY_MODS, START_HOTKEY_KEY, function()
    runTool("start")
  end)

  hs.hotkey.bind(RELAYOUT_HOTKEY_MODS, RELAYOUT_HOTKEY_KEY, function()
    runTool("relayout")
  end)
end

local function setupMenubar()
  local menu = hs.menubar.new()
  if not menu then
    return
  end

  menu:setTitle("AI")
  menu:setMenu({
    {
      title = "Start (open + relayout)",
      fn = function()
        runTool("start")
      end
    },
    {
      title = "Relayout AI windows",
      fn = function()
        runTool("relayout")
      end
    },
    {
      title = "Close AI windows",
      fn = function()
        runTool("close")
      end
    },
    { title = "-" },
    {
      title = string.format("AUTO_LOCK: %s", AUTO_LOCK and "ON" or "OFF"),
      disabled = true
    },
    {
      title = "Reload Hammerspoon",
      fn = function()
        hs.reload()
      end
    }
  })
end

local function setupAutoLock()
  if not AUTO_LOCK then
    return
  end

  local pendingTimer = nil
  local reentryGuard = false

  local function scheduleRelayout()
    if reentryGuard then
      return
    end

    if pendingTimer then
      pendingTimer:stop()
      pendingTimer = nil
    end

    pendingTimer = hs.timer.doAfter(DEBOUNCE_SECONDS, function()
      reentryGuard = true
      runTool("relayout")
      hs.timer.doAfter(REENTRY_GUARD_SECONDS, function()
        reentryGuard = false
      end)
    end)
  end

  local filter = hs.window.filter.new(false):setAppFilter("Safari", {})
  filter:subscribe(
    {
      hs.window.filter.windowCreated,
      hs.window.filter.windowMoved,
      hs.window.filter.windowResized,
      hs.window.filter.windowFocused
    },
    function()
      scheduleRelayout()
    end
  )
end

setupMenubar()
setupHotkeys()
setupAutoLock()
