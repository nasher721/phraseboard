# PhraseBoard

A native AutoHotkey v2 clipboard-history and text-expansion utility for Windows.

## Everyday use

| Action | Shortcut |
| --- | --- |
| Search clipboard history | Ctrl+Shift+V |
| Paste current clipboard as plain text | Alt+Shift+V |
| Open phrase library | Ctrl+Alt+Space |
| Pause or resume history | Ctrl+Alt+Shift+H |
| Paste selected item as plain text | Ctrl+Enter |
| Pin or favorite selected item | Ctrl+P |
| Delete selected item | Delete |

Open the picker while using your destination app. Type to search, use Up/Down to move through results, and press Enter or double-click to paste. Ctrl+Enter pastes plain text. Ctrl+P pins a history item or favorites a phrase; Delete removes the selected item. Turn on **Keep picker open** in the title bar to paste several items in sequence. **Paste original** restores the available clipboard formats; **Paste plain text** removes formatting. Clipboard items can also be pasted as a quote or joined onto one line. Closing the window keeps PhraseBoard running in the notification area. Use its tray menu to exit.

Open **Customize** to choose a light or dark theme, adjust text size and layout density, change clipboard and phrase ordering, and set the history item and storage limits. Choices are saved for the next launch. Pins are protected from automatic cleanup; the per-item clipboard size limit remains 2 MB.

To make a phrase: open Phrases, choose **New phrase**, enter a name, one or more triggers, optional comma-separated tags, allowed app process names, and your text, then save. Autotext triggers support immediate, confirmation, after-pause, and while-typing-fast modes; boundary position, SmartCase, and terminator handling are configurable in the phrase editor. Triggers are edited one per line as `Kind|Value|Mode|Enabled`; leave Mode blank to inherit the selected folder default. Shared autotexts open a chooser, and the Phrases list marks shared triggers. SmartComplete suggests phrases by description as you type. Folder hotkeys open a searchable, folder-scoped menu; Up from the first row navigates to the parent, and at the root it selects **Create new snippet here**. Direct phrase hotkeys (`Kind="Hotkey"`) allow triggering any phrase instantly via global keyboard shortcuts (e.g. `Ctrl+Alt+S` or `^!s`), with automatic modifier normalization and system conflict detection. Folder defaults can be inherited by phrases and child folders. Right-click a phrase to find every phrase using its autotext. The original abbreviation field remains a shortcut for the first enabled Autotext trigger. PhraseBoard does not expand triggers while its own editor or trigger menu is active.

### Macro Engine & Dynamic Templates

PhraseBoard includes a powerful, sandboxed macro engine that executes during expansion:
- **`{{date [format] [|offset]}}`**: Inserts current date/time with format string and relative offset (e.g. `{{date:YYYY-MM-DD|+7d}}`, `{{date:dddd, MMMM d, yyyy|-1m}}`).
- **`{{time [format]}}`**: Inserts current time formatted (e.g. `{{time:HH:mm:ss}}`).
- **`{{clipboard}}`**: Inserts current clipboard text dynamically.
- **`{{cursor}}`**: Automatically places the text cursor/caret at this position after insertion.
- **`{{prompt:label|default}}`**: Prompts with an interactive single-field modal dialog before insertion.
- **`{{form:field1|field2[choice1|choice2]|field3}}`**: Prompts with an interactive multi-field form supporting text inputs and dropdown selectors.
- **`{{phrase:name}}`**: Recursively expands nested phrases by Title or ID with cycle detection and a 16-level depth cap.
- **`{{random:item1|item2|item3}}`**: Picks one item at random from pipe-separated choices.
- **`{{set:var,value}}` and `{{get:var}}`**: Assigns and retrieves scoped variables during template expansion.
- **`{{if:left,op,right,trueBranch,falseBranch}}`**: Conditionals supporting `=`, `!=`, `>`, `<`, `>=`, `<=`, `contains`.
- **`{{each:item,a|b|c,body}}`**: Bounded iteration over a delimited list (capped at 100 iterations).
- **`{{process:operation,text}}`**: Text transformations including `uppercase`, `lowercase`, `titlecase`, `trim`, `prefix`, `suffix`, and `setClipboard`.
- **`{{calc:expression}}`**: Evaluates arithmetic expressions safely with an operator-precedence recursive-descent math parser (no dynamic code execution).
- **`{{file:path}}`**: Safely reads text from a local file (size-capped at 100 KB).

The Phrase Editor features an interactive **`+ Insert Macro...`** button with one-click templates and a **Preview result** button with live rendering and syntax error reporting.

Check **AI phrase** on a phrase before Generate, Improve, or an `{{ai:instruction}}` / `{{ai:instruction|input}}` macro can call a model. The checkbox is the consent: there is no second prompt, and an unchecked phrase never calls a model. Generate and Improve show the reply so you can keep or discard it. Ctrl+Z in the phrase editor undoes the newest accepted AI edit. Settings stores the Ollama or OpenAI-compatible provider. The API key is kept in a separate encrypted file. A failed expansion pastes nothing. Model replies are plain text and are not run as macros.

Favorites appear first, followed by frequently used phrases. Use **Export phrases CSV** and **Import phrases CSV** in Settings to move the legacy phrase fields. You can also turn any history item into a phrase with **Save as phrase**.

Use the folder selector in Phrases to browse a folder or all phrases. **New folder** creates a nested folder under the currently selected folder; rename, delete, and trigger-default actions are available when a folder is selected. Deleting a folder moves its direct phrases and child folders to its parent. The phrase editor can move a phrase between folders. A folder can set a default execution mode or inherit its parent's mode; these defaults are saved with the encrypted library.

## Saved history

History, phrases, and preferences are encrypted using Windows DPAPI for your Windows account in `%LOCALAPPDATA%\PhraseBoard`. Phrase records use the versioned PB4 library format. Headerless files and PB3 libraries still load, with **AI phrase** off, and are written as PB4 the next time the library is saved. Loading a library does not rewrite it, and malformed library data is not overwritten. Folders, triggers, trigger options, and inherited defaults are part of the encrypted phrase library. They survive application and Windows restarts. This encryption protects files at rest; programs running under your Windows account can still access your clipboard and decrypt its data.

The history retains up to 100 copies and 32 MB of clipboard data, with a 2 MB per-item limit. Pin up to 20 items to protect them from routine eviction. Repeated copies move their existing entry to the top. Image and file capture is off by default; enable **Save image and file copies** in Settings to include them. The optional API-key filter skips common AWS, GitHub, and `sk-` style credentials; it is a best-effort filter, not a general secret detector. Copies carrying the Windows clipboard-monitor exclusion marker are skipped. Settings can automatically remove unpinned history after a chosen number of days and exclude copies made in listed apps (process names such as `KeePass.exe`). **Pause history** stops recording and stays paused after restarting. **Clear all clipboard history** deletes saved history, including pins, while keeping phrases. The picker also has actions for quoting selected text and joining it onto one line.

Choose **Start PhraseBoard when I sign in to Windows** in Settings if desired. This is off on initial installation.

## Installation and source

Run `Install.ps1` with PowerShell to install to `%LOCALAPPDATA%\Programs\PhraseBoard` and create desktop and Start menu shortcuts. AutoHotkey v2 must be installed at `%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe`. The script launches the installed app. Alternatively, run `PhraseBoard.ahk` with AutoHotkey v2 directly. AHK Studio's older AutoHotkey v1 runtime cannot run this program.

## Scope and compatibility

PhraseBoard is a Windows-first local AutoHotkey tool. Active trigger kinds are Autotext, SmartComplete, phrase Hotkey, and folder Hotkey. The Macro Engine provides bounded, secure template evaluation without dynamic script execution (no arbitrary AHK/PowerShell evaluation). The only networked macro is `{{ai}}`, and only while that phrase's **AI phrase** box is checked. There is no cloud sync, general secret detection, PhraseExpress import, separate phrase libraries per app, or settings per app. CSV import/export covers legacy phrase fields, tags, favorites, and allowed apps, not folder hierarchy or trigger settings. Mac modifier names are automatically mapped to Windows keys (Command -> Win, Option -> Alt). Clipboard history preserves rich text/HTML when supplied by the source and accepted by the destination. Paste operations use robust activation fallbacks (`AttachThreadInput`, `SetForegroundWindow`, and `WM_PASTE` fallbacks) before restoring previous clipboard content. Normal Ctrl+C and Ctrl+V keep working.

## Tests

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\RunTests.ps1` from this directory. Tests use real Windows clipboard, keyboard input, native edit controls, and a rich-text control. They temporarily take focus and restore the original clipboard. Use them while PhraseBoard is not running to avoid capturing test copies in your own history.

The test harness runs 6 comprehensive suites:
1. **Smoke suite (`smoke.ahk`)**: Startup and lifecycle verification.
2. **Model suite (`model.ahk`)**: trigger normalization, SmartCase, SmartComplete ranking, execution timing, folder hierarchy, cycle rejection, PB3 loading, and encrypted PB4 persistence.
3. **AI suite (`ai.ahk`)**: provider requests, redaction, AI-phrase save rules, expansion limits, and editor text helpers.
4. **Macro suite (`macros.ahk`)**: 25 tests covering AST parsing, nested syntax, relative dates/times, scoped variables, conditionals, bounded loops, safe math evaluations, nested phrase expansion, recursion depth limits, and interactive forms.
5. **Hotkey suite (`hotkeys.ahk`)**: 10 tests verifying hotkey normalization, Mac modifier mapping, system shortcut conflict detection, and runtime registration.
6. **Integration harness (`integration.ahk`)**: end-to-end tests exercising DPAPI encryption, live clipboard capture, RTF formatting, native paste restoration, SmartComplete UI, and safe process termination.
