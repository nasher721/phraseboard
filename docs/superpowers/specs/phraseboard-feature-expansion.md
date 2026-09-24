# PhraseBoard Feature Expansion Spec

## Product context

PhraseBoard is a Windows-only AutoHotkey v2 clipboard-history and text-expansion utility. Phrases and history are stored locally and protected with Windows DPAPI. Current phrases contain a name, body, abbreviation, tags, favorite/use metadata, and allowed apps. The app has basic date/time/clipboard/prompt/cursor tokens, one phrase library, and a real Windows integration harness.

This expansion adds trigger, macro, and AI workflows. Keep phrase content local unless the user explicitly invokes an AI provider. PhraseBoard remains Windows-first; Mac modifier names are portable import/export representations only, not a Mac client.

## Triggers and folders

- A phrase may have multiple triggers. Multiple phrases may deliberately share one trigger; invoking a shared trigger opens a menu containing every eligible phrase.
- A trigger may expand immediately or suggest phrases in a menu.
- A folder may have a trigger that opens a menu of its phrases and subfolders. Search stays inside that folder; Up exposes “Create new snippet here.”
- Folder trigger settings may become inherited defaults for descendants. A descendant can override an inherited setting.
- Shared triggers are visibly marked and provide an action to find all phrases using them.

## Hotkeys

- Combine Ctrl, Alt, Win, and Shift with a keyboard key or mouse button.
- Warn on conflicts between PhraseBoard registrations, Windows-rejected registrations, and likely common system shortcuts.
- Portable shortcut records map Mac Command to Win, Option to Alt, and Control to Ctrl.
- A folder hotkey opens its scoped folder menu and provides the Up-arrow create-phrase action.

## Typed text triggers

- SmartComplete suggests phrases by description, narrows after each character, and accepts with arrows plus a confirm hotkey. Escape or continued typing dismisses the current popup. Matching is case-sensitive and its minimum character count is configurable.
- Autotext supports abbreviations, typo correction, and macro-based app launching. Abbreviations are limited to 32 characters; likely typing conflicts produce a warning.
- Exact case or SmartCase is configurable. SmartCase maps `max` to `maximum`, `Max` to `Maximum`, and `MAX` to `MAXIMUM`. It is enabled only when body and autotext are lowercase and no case-variant trigger exists.
- Word positions are start (default), end, middle, or entire word. Boundary rules are none, any character, letter/number, custom character set, or incremental suggestions. Custom sets may use `#13` for Enter and `#9` for Tab.
- Optionally remove trailing space or punctuation after expansion.
- Execution modes: immediate; manual popup confirmation; fire after a pause whose threshold adapts to typing speed; or fire only during continuous fast typing and dismiss on pause.
- Shared triggers remain discoverable and selectable.

## Other triggers

- Regex autotext matches typed text; provide examples and mark it expert-only.
- Window triggers match focused program name and window title.
- Daily time triggers fire at a configured local time.
- Exact clipboard triggers match text. Regex clipboard triggers can open menus of actions, for example for copied URLs.

## Macro engine and editing

- Macros are placeholders for dynamic insertion-time content. They run in source order, except forms gather inputs before output assembly.
- Nested macros are allowed in every parameter. Capabilities include linked/nested phrases, random alternatives, date/time, forms, external file/Excel data, email generation, app launch, math, keypress emulation, loops, variables, and conditionals.
- Additional processing applies ordered post-processing steps, such as input → uppercase → set clipboard.
- A macro name displays as a readable token; an unnamed macro displays its raw syntax.
- Plain text can be authored first, then a selected variable part converted into a macro.
- Macro Recorder is separate. Macro authoring is desktop-only; this does not imply a mobile macro editor.

## AI

- Improve all or selected phrase text with a preset or custom instruction. The user selects provider/engine and parameters; Ctrl+Z undoes the accepted edit.
- Generate a phrase from a natural-language description and let the user refine the draft before saving.
- AI macros accept direct input, another macro's output, or empty input for pure generation.
- Support paid cloud services and local models such as Ollama through provider adapters. Show provider and payload before cloud requests.

## Platform and compatibility constraints

- Keep PhraseBoard Windows-first, AutoHotkey v2, locally stored, and protected at rest with DPAPI. Do not add cloud synchronization, a Mac/iOS client, or arbitrary AHK/shell execution.
- Preserve clipboard capture, rich/plain paste, all current phrase fields, and existing encrypted phrase data through a versioned migration.
- Test pure matching/serialization separately from OS integration. Integration tests that use the clipboard/keyboard restore the clipboard and close temporary GUIs.
