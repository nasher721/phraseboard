# PhraseBoard Hotkey and Event Triggers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add keyboard/mouse hotkeys and regex, window, daily-time, and clipboard triggers through one dispatcher.

**Architecture:** Consume the shared trigger model. Separate registration and event-observation adapters emit typed events to one dispatcher, which applies app filters and presents a chooser for multiple matching phrases/actions. Event adapters do not evaluate arbitrary source code.

**Tech Stack:** AutoHotkey v2 hotkeys/timers, Win32 clipboard/window APIs, DPAPI local storage, existing AHK integration harness.

**Spec:** [PhraseBoard feature expansion spec](../specs/phraseboard-feature-expansion.md), “Hotkeys,” “Other triggers,” and folder triggers.

## Global Constraints

- Hotkeys combine Ctrl, Alt, Win, and Shift with a key or mouse button.
- Report PhraseBoard and OS/AHK registration conflicts and warn on common system shortcuts.
- Daily time triggers use configured local time.
- PhraseBoard stays Windows-first, AutoHotkey v2, local, and DPAPI-protected.
- Trigger-model and typed-trigger plans define the shared record and dispatcher before this plan starts.

## Review Focus

- Report a hotkey owned by another app; test registration failure and leave the other app untouched.
- Require both configured process and title conditions when both are set; test mismatches.
- Fire a daily trigger once per local calendar day across sleep/resume and restart; test duplicate timer wakeups and DST boundary dates.
- Ignore PhraseBoard clipboard writes and unchanged sequence numbers; test internal-paste suppression.
- Bound regex input and reject malformed patterns without hanging typing; test invalid and maximum-size values.

---

### Task 1: Register keyboard and mouse hotkeys with warnings

**Files:**
- Modify: `lib/TriggerEngine.ahk`
- Modify: `lib/PhraseBoardApp.ahk:217-228` (`RegisterShortcuts`)
- Modify: `lib/PhraseBoardApp.ahk:1159-1209` (trigger editor)
- Create: `tests/hotkeys.ahk`

**Interfaces:**
- `HotkeyAdapter.Register(trigger)`, `.Unregister(triggerId)`, `.Validate(trigger)` returns `{Valid, ConflictKind, Message}`.
- Options: `Modifiers` Map of `Ctrl|Alt|Win|Shift` booleans, `Key` string, `Device` `Keyboard|Mouse`.
- Import/export maps portable Mac `Command`→`Win`, `Option`→`Alt`, `Control`→`Ctrl` and reverse.

- [ ] **Step 1: Write tests** for every modifier, keyboard and mouse key, modifier-only rejection, both portable mappings, and simulated registration conflict.
- [ ] **Step 2: Run `AutoHotkey64.exe /ErrorStdOut tests\hotkeys.ahk`**; expected: adapter methods fail.
- [ ] **Step 3: Implement registration, cleanup, and editor warnings**; catch AHK registration errors and protect built-in app shortcuts from duplicate assignment.
- [ ] **Step 4: Run tests and a manual same-session check**; expected: each registered hotkey dispatches once and rejected registrations show the combination.
- [ ] **Step 5: Commit** with `feat: register configurable phrase hotkeys`.

### Task 2: Add regex autotext adapter

**Files:**
- Create: `lib/RegexTrigger.ahk`
- Create: `lib/RegexExamples.ahk`
- Modify: `lib/TriggerEngine.ahk`
- Modify: `lib/PhraseBoardApp.ahk` (expert trigger editor)
- Create: `tests/regex-triggers.ahk`

**Interfaces:**
- `RegexTrigger.Compile(pattern, flags := "")` returns a matcher or readable error.
- `.Match(typedBuffer, maxBufferChars := 4096)` returns bounded range and capture Map.
- Named bundled examples include email and URL patterns with plain-language descriptions.

- [ ] **Step 1: Write tests** for email, URL, invalid regex, captures, unmatched text, and maximum buffer.
- [ ] **Step 2: Run regex tests**; expected: compile/match assertions fail.
- [ ] **Step 3: Implement expert-only pattern configuration** with examples and clear compile errors.
- [ ] **Step 4: Run tests**; expected: each match dispatches once, unmatched text remains intact, and invalid patterns never register.
- [ ] **Step 5: Commit** with `feat: support regex autotext triggers`.

### Task 3: Add window focus triggers

**Files:**
- Create: `lib/WindowTrigger.ahk`
- Modify: `lib/TriggerEngine.ahk`
- Modify: `lib/PhraseBoardApp.ahk` (event lifecycle and trigger editor)
- Create: `tests/window-triggers.ahk`

**Interfaces:**
- Options: `ProcessName`, `TitlePattern`, `MatchMode` (`Exact|Contains|Regex`).
- `WindowTrigger.OnFocus(hwnd)` returns matching trigger IDs; `PhraseBoardApp.DispatchTrigger(triggerId, context)` opens the configured menu/action.

- [ ] **Step 1: Write tests** for process-only, title-only, combined filters, exact/contains/regex title, and PhraseBoard self-window exclusion.
- [ ] **Step 2: Run tests**; expected: focus matcher assertions fail.
- [ ] **Step 3: Implement debounced active-window observation** and persist last-window/trigger identity to avoid repeated firing.
- [ ] **Step 4: Run tests**; expected: one dispatch per focus transition and another after switching away and back.
- [ ] **Step 5: Commit** with `feat: add application window triggers`.

### Task 4: Add daily local-time triggers

**Files:**
- Create: `lib/TimeTrigger.ahk`
- Modify: `lib/TriggerEngine.ahk`
- Modify: `lib/PhraseBoardApp.ahk` (timer startup/shutdown)
- Create: `tests/time-triggers.ahk`

**Interfaces:**
- Options: `LocalTime` as `HH:mm`, `Enabled`, and optional `ActionPhraseIds`.
- `TimeTrigger.Due(nowLocal, lastFiredDate)` returns `{Due, FireDate}`; deterministic under tests.
- Persist local last-fired date before dispatch to suppress repeated callbacks/restarts.

- [ ] **Step 1: Write deterministic tests** before/during/after target minute, duplicate callback, same-day restart, next-day firing, and invalid time.
- [ ] **Step 2: Run tests**; expected: due calculations fail.
- [ ] **Step 3: Implement one shared timer** over enabled triggers and save fire date before dispatch.
- [ ] **Step 4: Run tests and a bounded local check**; expected: exactly one dispatch per trigger per local day.
- [ ] **Step 5: Commit** with `feat: schedule daily phrase triggers`.

### Task 5: Add exact and regex clipboard triggers

**Files:**
- Create: `lib/ClipboardTrigger.ahk`
- Modify: `lib/PhraseBoardApp.ahk:150-193` (`ClipboardChanged`, `Capture`)
- Modify: `lib/TriggerEngine.ahk`
- Modify: `tests/integration.ahk`

**Interfaces:**
- Options: `MatchKind` (`Exact|Regex`), `Pattern`, `ActionPhraseIds`, `MenuTitle`.
- `ClipboardTrigger.Evaluate(text, triggers, sequenceNumber, internalSequence)` returns all matching IDs and never writes the clipboard.

- [ ] **Step 1: Write tests** for exact, URL regex, multiple actions, non-text exclusion, duplicate sequence suppression, and internal clipboard suppression.
- [ ] **Step 2: Run integration tests**; expected: clipboard trigger evaluation is absent.
- [ ] **Step 3: Evaluate triggers in the existing callback** after capture bookkeeping and dispatch matching action menus.
- [ ] **Step 4: Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\RunTests.ps1`**; expected: current capture/paste/restore checks pass and one matching copy opens one action menu.
- [ ] **Step 5: Document trigger scope and commit** with `feat: add clipboard phrase triggers`.
