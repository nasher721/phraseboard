# PhraseBoard Typed Triggers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement reliable autotext and SmartComplete matching, including ambiguity menus, word rules, case handling, and configurable execution modes.

**Architecture:** `TriggerEngine` owns typed-input matching and hotstring lifecycle; `SmartComplete` owns suggestion state and display. Phrase records and shared-trigger lookup come from the trigger-model plan. Route insertion through the existing target-app, token, and cursor path so allowed-app filters and paste behavior remain consistent.

**Tech Stack:** AutoHotkey v2 hotstrings, timers, GUI controls, Win32 keyboard APIs where AHK lacks timing/boundary information; existing PowerShell/AHK harness.

**Spec:** [PhraseBoard feature expansion spec](../specs/phraseboard-feature-expansion.md), sections “Typed text triggers” and shared triggers.

## Global Constraints

- Autotext abbreviations are “limited to 32 characters.”
- SmartComplete “matching is case-sensitive”; autotext case behavior is configured separately.
- SmartCase maps `max` → `maximum`, `Max` → `Maximum`, and `MAX` → `MAXIMUM` only when body/trigger are lowercase and no case-variant collision exists.
- PhraseBoard remains Windows-first, AutoHotkey v2, and locally stored with DPAPI.
- The trigger-model-and-folders plan must land first.

## Review Focus

- A shared abbreviation displays all eligible phrases instead of expanding an arbitrary first match; test two phrases with one trigger.
- Boundary keys are preserved unless removal is enabled; test Space, Enter, Tab, and punctuation.
- SmartCase refuses ambiguous inputs; test lowercase, title case, uppercase, mixed case, and a case-variant collision.
- Slow typing never fires fast-typing mode; test deterministic time samples and pause dismissal.
- PhraseBoard's editor and excluded apps never expand triggers; test window context exclusion.

---

### Task 1: Register autotext records and route duplicate matches

**Files:**
- Create: `lib/TriggerEngine.ahk`
- Modify: `PhraseBoard.ahk:1-3`
- Modify: `lib/PhraseBoardApp.ahk:217-228` (`RegisterShortcuts`)
- Modify: `lib/PhraseBoardApp.ahk:231-290` (`CanExpand`, `RegisterPhrases`, `ExpandPhrase`)
- Modify: `tests/model.ahk`

**Interfaces:**
- `TriggerEngine.Register(phrases)`, `.Unregister()`, `.Candidates(kind, value, targetHwnd)`.
- `PhraseBoardApp.InsertPhrase(phraseId, targetHwnd, caseMode := "Exact")` routes through existing allowed-app, token, and cursor behavior.
- Candidate shape: `{PhraseId, TriggerId, Trigger}`; return only enabled triggers allowed in `targetHwnd`.

- [ ] **Step 1: Write tests** for one match, two shared matches, disallowed target app, disabled expansion, and blank trigger.
- [ ] **Step 2: Run `AutoHotkey64.exe /ErrorStdOut tests\model.ahk`**; expected: new candidate methods fail.
- [ ] **Step 3: Move hotstring registration into `TriggerEngine`** and make shared matches open a chooser, never pick the first record implicitly.
- [ ] **Step 4: Run model tests and `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\RunTests.ps1`**; expected: unique legacy abbreviation still expands and shared values show every candidate.
- [ ] **Step 5: Commit** with `feat: route autotext through trigger engine`.

### Task 2: Validate abbreviation length, conflicts, positions, and boundaries

**Files:**
- Modify: `lib/PhraseModel.ahk` (autotext option validation)
- Modify: `lib/TriggerEngine.ahk`
- Modify: `lib/PhraseBoardApp.ahk:1159-1209` (phrase editor trigger options)
- Modify: `tests/model.ahk`

**Interfaces:**
- Autotext `Options` keys: `CaseMode` (`Exact|SmartCase`), `Position` (`Start|End|Middle|Entire`), `Before`/`After` (`None|Any|Alphanumeric|CharacterSet|Incremental`), `BeforeChars`, `AfterChars`, `RemoveTerminator` (boolean), `MinChars` (integer).
- `TriggerEngine.MatchesBoundary(trigger, typedText, precedingText, followingText)` returns boolean plus match range.

- [ ] **Step 1: Write tests** for 32-character acceptance, 33-character rejection, four word positions, all five boundary rule types, incremental suggestions narrowing after each character, custom `#13`/`#9`, and removable space/period/comma.
- [ ] **Step 2: Run the model tests**; expected: boundary and length assertions fail.
- [ ] **Step 3: Implement option validation and boundary evaluation**; incremental mode uses the SmartComplete query path, and key codes are translated only at the input adapter boundary, never as regex source.
- [ ] **Step 4: Run tests**; expected: all documented rules match and no character is swallowed unless `RemoveTerminator` is true.
- [ ] **Step 5: Commit** with `feat: configure autotext word boundaries`.

### Task 3: Add exact matching, SmartCase, and suspicious-abbreviation warnings

**Files:**
- Modify: `lib/TriggerEngine.ahk`
- Modify: `lib/PhraseModel.ahk`
- Modify: `lib/PhraseBoardApp.ahk:1159-1209` (editor feedback)
- Modify: `tests/model.ahk`

**Interfaces:**
- `TriggerEngine.ApplyCase(inputMatch, phraseText, trigger)` returns transformed text or unchanged text.
- `TriggerEngine.ConflictWarnings(trigger, phrases)` returns readable, non-blocking warnings for short ordinary strings and overlapping registrations.

- [ ] **Step 1: Write tests** for exact matching; three SmartCase examples; mixed case; non-lowercase body/trigger; and case-variant collision.
- [ ] **Step 2: Run tests**; expected: SmartCase cases fail.
- [ ] **Step 3: Implement the case transform and warning checks** without modifying saved phrase text.
- [ ] **Step 4: Run tests**; expected: valid SmartCase transforms pass and ambiguous cases return a warning naming the condition.
- [ ] **Step 5: Commit** with `feat: add autotext SmartCase and collision warnings`.

### Task 4: Build SmartComplete suggestions and keyboard behavior

**Files:**
- Create: `lib/SmartComplete.ahk`
- Modify: `lib/PhraseBoardApp.ahk:217-228` (navigation/confirm hotkeys)
- Modify: `lib/PhraseBoardApp.ahk:500-625` (suggestion GUI helper)
- Modify: `lib/PhraseBoardApp.ahk:1159-1209` (description and minimum-character preference)
- Modify: `tests/integration.ahk`

**Interfaces:**
- `SmartComplete.Query(text, phrases, minChars)` performs case-sensitive substring matching on phrase `Name`, returning stable ranked results.
- `.Show(targetHwnd, query, results)`, `.MoveSelection(delta)`, `.Accept()`, `.Dismiss(reason)` manage the popup. Continued typing dismisses the current popup and reruns matching with new text.

- [ ] **Step 1: Write tests** for the min-character threshold, character-by-character narrowing, case sensitivity, stable ties, arrows, confirm, Escape, and continued typing.
- [ ] **Step 2: Run tests**; expected: query and selection tests fail.
- [ ] **Step 3: Implement query ranking and a non-activating popup** anchored near the caret; use arrows and a configurable confirmation hotkey.
- [ ] **Step 4: Run model and bounded GUI integration checks**; expected: target app retains focus and accepted phrase inserts into the original target.
- [ ] **Step 5: Commit** with `feat: suggest phrases with SmartComplete`.

### Task 5: Implement trigger execution modes and adaptive typing speed

**Files:**
- Modify: `lib/TriggerEngine.ahk`
- Modify: `lib/SmartComplete.ahk`
- Modify: `lib/PhraseBoardApp.ahk` (trigger editor settings)
- Modify: `tests/model.ahk`, `tests/integration.ahk`

**Interfaces:**
- Trigger `Mode`: `Immediate|Confirm|AfterPause|WhileTypingFast`.
- `TriggerEngine.TypingRate.Record(timestamp)`, `.Threshold(samples, configuredFloor)`, `.Evaluate(mode, elapsedMs)` accept test timestamps and do not read the clock internally.

- [ ] **Step 1: Write deterministic timing tests** for immediate, confirm-only, pause-adaptive, fast-typing, and pause-dismissal behavior.
- [ ] **Step 2: Run tests**; expected: mode evaluator assertions fail.
- [ ] **Step 3: Implement timestamp-driven timing** and connect each mode to insertion or suggestion UI.
- [ ] **Step 4: Run integration checks** with normal and delayed key sequences; expected: correct fire/dismiss behavior without duplicated typed characters.
- [ ] **Step 5: Commit** with `feat: add configurable autotext execution modes`.

### Task 6: Finish folder-trigger menus and user help

**Files:**
- Modify: `lib/TriggerEngine.ahk`
- Modify: `lib/PhraseBoardApp.ahk` (folder menu, scoped search, Up action)
- Modify: `tests/integration.ahk`
- Modify: `README.md`

**Interfaces:**
- `FolderTriggerMenu.Open(folderId, targetHwnd)`, `.Search(query)`, `.Select(itemId)`, `.MoveUp()` consumes folder model/defaults.
- At the top level, `.MoveUp()` focuses “Create new snippet here,” bound to the current folder.

- [ ] **Step 1: Write GUI assertions** for scoped search, nested navigation, and Up-arrow focus on the create row.
- [ ] **Step 2: Run the GUI integration harness**; expected: folder-menu assertions fail.
- [ ] **Step 3: Connect folder hotkey/menu selection to phrase insertion** and retain the invoking target window handle.
- [ ] **Step 4: Run the full integration harness**; expected: selection inserts only the chosen phrase into the prior foreground app.
- [ ] **Step 5: Document autotext limits, modes, word rules, and SmartComplete; commit** with `feat: add folder-scoped phrase trigger menus`.
