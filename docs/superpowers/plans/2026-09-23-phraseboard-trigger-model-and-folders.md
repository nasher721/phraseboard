# PhraseBoard Trigger Model and Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent phrase folders and a shared, multi-trigger model that later trigger runtimes can consume.

**Architecture:** Keep the existing window and app lifecycle, but move phrase/folder/trigger validation and serialization into focused modules. Migrate `Abbr` into a legacy-compatible autotext trigger while preserving old encrypted phrase files and every current phrase property.

**Tech Stack:** AutoHotkey v2, Windows DPAPI through `SecureStore`, existing PowerShell/AHK integration harness; no new runtime dependency.

**Spec:** [PhraseBoard feature expansion spec](../specs/phraseboard-feature-expansion.md), sections “Triggers and folders,” “Hotkeys,” and “Platform and compatibility constraints.”

## Global Constraints

- “Keep PhraseBoard Windows-first, AutoHotkey v2, locally stored, and protected at rest with DPAPI.”
- “Preserve clipboard capture, rich/plain paste, all current phrase fields, and existing encrypted phrase data through a versioned migration.”
- “A phrase may have multiple triggers. Multiple phrases may deliberately share one trigger.”
- “Folder trigger settings may become inherited defaults for descendants. A descendant can override an inherited setting.”
- Trigger records contain data, never executable AutoHotkey source.

## Review Focus

- Existing legacy `phrases.dat` rows retain every current field; pin a fixture migration test.
- Shared trigger values resolve to all matching phrases; pin lookup and round-trip tests.
- Folder deletion/moves cannot orphan phrases; pin explicit reparenting behavior.
- A malformed record does not overwrite the last good library; pin corruption/write-failure tests.
- A child override does not modify siblings; pin inheritance and override tests.

---

### Task 1: Define versioned phrase, folder, and trigger records

**Files:**
- Create: `lib/PhraseModel.ahk`
- Create: `tests/model.ahk`
- Modify: `lib/PhraseBoardApp.ahk:367-405` (`ValidatePhrase`, `UpsertPhrase`, `FindPhrase`)
- Modify: `PhraseBoard.ahk:1-3` (module includes)

**Interfaces:**
- `PhraseModel.NormalizePhrase(record)`, `.ValidatePhrase(record)`, `.NormalizeTrigger(record)`, `.NormalizeFolder(record)`, `.ResolveFolderDefaults(folderId, folders, key)`.
- Phrase: `{Id, Name, Text, Tags, Favorite, Uses, Apps, FolderId, Triggers}`.
- Trigger: `{Id, Kind, Value, Mode, Options}`; kind/mode are strings, options is a plain AHK Map, and IDs remain stable across edits.
- Folder: `{Id, ParentId, Name, Triggers, TriggerDefaults, CreatedAt}`; `Triggers` is an array of trigger records. Defaults are a Map where a missing key inherits and an explicit key overrides.

- [ ] **Step 1: Write model tests** for legacy `Abbr` to one `Autotext` trigger, preserving all old fields and ID; allow two phrases to share a value; allow a folder trigger; reject blank values and unsupported kinds.
- [ ] **Step 2: Run `AutoHotkey64.exe /ErrorStdOut tests\model.ahk`**; expected: absent model methods fail.
- [ ] **Step 3: Implement normalizers and validators** in `lib/PhraseModel.ahk`; normalization is deterministic and does not mutate input.
- [ ] **Step 4: Run model tests**; expected: migration, shared-value, and invalid-record assertions pass.
- [ ] **Step 5: Commit** with `feat: define phrase folders and trigger records`.

### Task 2: Persist PB3 phrase and folder data with PB2 migration

**Files:**
- Create: `lib/PhraseLibrary.ahk`
- Modify: `lib/PhraseBoardApp.ahk:50-121` (`Load`)
- Modify: `lib/PhraseBoardApp.ahk:126-132` (`SavePhrases`)
- Modify: `lib/Storage.ahk:61-76` (atomic read/write helpers if needed)
- Modify: `tests/model.ahk`, `tests/integration.ahk:1-40`

**Interfaces:**
- `PhraseLibrary.Load(store)` and `.Save(store, phrases, folders)` consume Task 1 records, including folder `Triggers`.
- Legacy phrase storage is one tab-delimited phrase row per line with eight fields and no file header. PB3 begins with a `PB3` header and uses `P`, `F`, `T`, and `O` tab-delimited rows for phrase, folder, trigger, and option/default records. `P` fields are ID, name, text, tags, favorite, uses, allowed apps, folder ID; `F` fields are ID, parent ID, name, creation time; `T` fields are trigger ID, owner type, owner ID, kind, value, mode, enabled; `O` fields are owner type, owner ID, key, value. Base64-encode each cell separately; base64 output has no tab/newline delimiters. Link rows by opaque record IDs. Keep DPAPI at the storage boundary and atomic temp-file replacement.

- [ ] **Step 1: Add tests** for legacy eight-field phrase row load, PB3 round-trip, shared triggers, unicode/newlines, truncated record rejection, and preservation of the original file on error.
- [ ] **Step 2: Run the model tests**; expected: legacy fixture passes while PB3 assertions fail.
- [ ] **Step 3: Implement `PhraseLibrary`** and route app load/save through it.
- [ ] **Step 4: Run model tests and `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\RunTests.ps1`**; expected: legacy migration and all current phrase/history checks pass.
- [ ] **Step 5: Commit** with `feat: migrate phrase storage to versioned library records`.

### Task 3: Add folder CRUD and inherited defaults

**Files:**
- Create: `lib/FolderTree.ahk`
- Modify: `lib/PhraseBoardApp.ahk:500-625` (phrase-library controls)
- Modify: `lib/PhraseBoardApp.ahk:717-777` (phrase listing/preview)
- Modify: `lib/PhraseBoardApp.ahk:1159-1209` (phrase editor/delete flow)
- Modify: `tests/model.ahk`, `tests/integration.ahk`

**Interfaces:**
- `FolderTree.Children(parentId)`, `.Move(itemId, parentId)`, `.Delete(folderId, reparentTo)`, `.EffectiveDefaults(folderId)`.
- Empty `ParentId` is the root. Folder and phrase IDs are opaque strings. Phrase editor accepts `FolderId`; inherited values are shown, and only changed values are persisted as overrides.

- [ ] **Step 1: Write tests** for nested folder paths, moving a phrase, deleting with explicit reparenting, inherited defaults, and child override independent of siblings.
- [ ] **Step 2: Run model tests**; expected: folder operations fail.
- [ ] **Step 3: Implement folder operations** with cycle prevention and explicit delete behavior; add create/rename/move controls to the Phrases tab.
- [ ] **Step 4: Run model and integration tests**; expected: hierarchy/persistence assertions pass and phrase editing still works.
- [ ] **Step 5: Commit** with `feat: organize phrases into folders`.

### Task 4: Edit multiple triggers and expose shared-trigger discovery

**Files:**
- Modify: `lib/PhraseBoardApp.ahk:367-405` (validation/upsert)
- Modify: `lib/PhraseBoardApp.ahk:717-777` (phrase list/search)
- Modify: `lib/PhraseBoardApp.ahk:1159-1209` (phrase editor)
- Modify: `tests/integration.ahk`
- Modify: `README.md`

**Interfaces:**
- `PhraseModel.FindPhrasesByTrigger(kind, value, phrases)` returns every match ordered favorite, usage count, then name.
- Phrase editor provides add/remove controls and per-trigger kind, value, mode, and enabled state.
- Until all callers use the new model, legacy `Abbr` display reads the first enabled autotext trigger.

- [ ] **Step 1: Write integration assertions** that create two phrases with one shared autotext and verify edit/reload preserves both.
- [ ] **Step 2: Run the harness**; expected: shared-trigger persistence assertion fails.
- [ ] **Step 3: Add trigger-list editing and lookup**; mark shared values with a count/icon and add “Find phrases using this trigger.”
- [ ] **Step 4: Run the harness**; expected: each phrase stays separately editable and existing CSV/token behavior passes.
- [ ] **Step 5: Commit** with `feat: edit and discover shared phrase triggers`.

### Task 5: Document model and migration guarantees

**Files:**
- Modify: `README.md`
- Modify: `tests/integration.ahk`

- [ ] **Step 1: Add reload assertions** for favorite, uses, tags, apps, folder, and triggers.
- [ ] **Step 2: Run the full integration harness**; expected: old clipboard and phrase data remains available after legacy-to-PB3 migration.
- [ ] **Step 3: Document folders, shared/multiple triggers, and the local encrypted PB3 library** in README.
- [ ] **Step 4: Review documentation against the implementation**; expected: it does not promise synchronization or non-Windows clients.
- [ ] **Step 5: Commit** with `docs: describe phrase folders and trigger model`.
