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

To make a phrase: open Phrases, choose **New phrase**, enter a name, one or more triggers, optional comma-separated tags, allowed app process names, and your text, then save. Autotext triggers support immediate, confirmation, after-pause, and while-typing-fast modes; boundary position, SmartCase, and terminator handling are configurable in the phrase editor. Triggers are edited one per line as `Kind|Value|Mode|Enabled`; leave Mode blank to inherit the selected folder default. Shared autotexts open a chooser, and the Phrases list marks shared triggers. SmartComplete suggests phrases by description as you type. Folder hotkeys open a searchable, folder-scoped menu; Up from the first row navigates to the parent, and at the root it selects **Create new snippet here**. Folder defaults can be inherited by phrases and child folders. Right-click a phrase to find every phrase using its autotext. The original abbreviation field remains a shortcut for the first enabled Autotext trigger. PhraseBoard does not expand triggers while its own editor or trigger menu is active. `{{date}}` inserts YYYY-MM-DD, `{{time}}` inserts HH:mm, `{{clipboard}}` inserts current clipboard text, `{{prompt:label}}` asks for a value at insertion time, and `{{cursor}}` places the caret at that point after insertion. Favorites appear first, followed by frequently used phrases. Use **Export phrases CSV** and **Import phrases CSV** in Settings to move the legacy phrase fields. You can also turn any history item into a phrase with **Save as phrase**.

Use the folder selector in Phrases to browse a folder or all phrases. **New folder** creates a nested folder under the currently selected folder; rename, delete, and trigger-default actions are available when a folder is selected. Deleting a folder moves its direct phrases and child folders to its parent. The phrase editor can move a phrase between folders. A folder can set a default execution mode or inherit its parent's mode; these defaults are saved with the encrypted library.

## Saved history

History, phrases, and preferences are encrypted using Windows DPAPI for your Windows account in `%LOCALAPPDATA%\PhraseBoard`. Phrase records use the versioned PB3 library format; older headerless phrase files are read and converted the next time the library is saved. Loading a library does not rewrite it, and malformed library data is not overwritten. Folders, triggers, trigger options, and inherited defaults are part of the encrypted phrase library. They survive application and Windows restarts. This encryption protects files at rest; programs running under your Windows account can still access your clipboard and decrypt its data.

The history retains up to 100 copies and 32 MB of clipboard data, with a 2 MB per-item limit. Pin up to 20 items to protect them from routine eviction. Repeated copies move their existing entry to the top. Image and file capture is off by default; enable **Save image and file copies** in Settings to include them. The optional API-key filter skips common AWS, GitHub, and `sk-` style credentials; it is a best-effort filter, not a general secret detector. Copies carrying the Windows clipboard-monitor exclusion marker are skipped. Settings can automatically remove unpinned history after a chosen number of days and exclude copies made in listed apps (process names such as `KeePass.exe`). **Pause history** stops recording and stays paused after restarting. **Clear all clipboard history** deletes saved history, including pins, while keeping phrases. The picker also has actions for quoting selected text and joining it onto one line.

Choose **Start PhraseBoard when I sign in to Windows** in Settings if desired. This is off on initial installation.

## Installation and source

Run `Install.ps1` with PowerShell to install to `%LOCALAPPDATA%\Programs\PhraseBoard` and create desktop and Start menu shortcuts. AutoHotkey v2 must be installed at `%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe`. The script launches the installed app. Alternatively, run `PhraseBoard.ahk` with AutoHotkey v2 directly. AHK Studio's older AutoHotkey v1 runtime cannot run this program.

## Scope and compatibility

PhraseBoard remains a Windows-first local AutoHotkey tool. Active trigger kinds are Autotext, SmartComplete, and folder Hotkey; other trigger kinds can be stored but are not yet active. Macro execution and AI processing are not implemented. There is no cloud sync, general secret detection, PhraseExpress import, separate phrase libraries per app, or settings per app. CSV import/export covers legacy phrase fields, tags, favorites, and allowed apps, not folder hierarchy or trigger settings. Mac modifier names are not a promise of a Mac client. Clipboard history can preserve rich text/HTML when supplied by the source and accepted by the destination. Paste uses Ctrl+V; elevated apps, remote desktops, and applications with unusual clipboard behavior may need separate validation. Normal Ctrl+C and Ctrl+V keep working.

## Tests

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\RunTests.ps1` from this directory. Tests use real Windows clipboard, keyboard input, native edit controls, and a rich-text control. They temporarily take focus and restore the original clipboard. Use them while PhraseBoard is not running to avoid capturing test copies in your own history.

The model suite covers trigger validation, matching, SmartCase, SmartComplete, execution timing, folders, and library persistence. Startup smoke checks cover app construction and editor-option round trips. The Windows integration harness exercises real clipboard, keyboard, and GUI behavior; some assertions depend on foreground-window focus and native RichEdit behavior, so results can vary by desktop session. These tests do not establish compatibility with every third-party application.
