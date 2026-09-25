## Learned User Preferences

- AI features should apply only to phrases explicitly marked with a single per-phrase "AI phrase" checkbox (off by default, editable later). That checkbox is the consent, with no extra prompt at expansion time. The phrase that contains `{{ai}}` must be checked. An embedded phrase uses its own checkbox, so an unchecked phrase can still cause a model call by embedding a checked one.

## Learned Workspace Facts

- PhraseBoard is a Windows AutoHotkey clipboard-history and text-expansion app (`PhraseBoard.ahk`, `Install.ps1`, `lib/`, `tests/`, `docs/`), cloned from `nasher721/phraseboard` on `main`.
- The phrase library supports folders, shared triggers, autotext, SmartComplete, phrase and folder hotkeys, and a macro engine, stored locally with DPAPI protection.
- The macro engine is sandboxed: `{{name:arguments}}` syntax, unknown commands rejected, bounded depth, and no arbitrary AutoHotkey or shell. The only networked macro is `{{ai}}`, and only when the phrase that contains that macro has its AI phrase checkbox on. Embedded phrases use their own checkbox.
- Design specs and plans live under `docs/superpowers/specs/` and `docs/superpowers/plans/`.
