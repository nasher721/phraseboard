## Learned User Preferences

- AI features should apply only to phrases explicitly marked with a single per-phrase "AI phrase" checkbox (off by default, editable later); that checkbox is the consent, with no extra prompt at expansion time, and unmarked phrases never call a model.

## Learned Workspace Facts

- PhraseBoard is a Windows AutoHotkey clipboard-history and text-expansion app (`PhraseBoard.ahk`, `Install.ps1`, `lib/`, `tests/`, `docs/`), cloned from `nasher721/phraseboard` on `main`.
- The phrase library supports folders, shared triggers, autotext, SmartComplete, phrase and folder hotkeys, and a macro engine, stored locally with DPAPI protection.
- The macro engine is sandboxed: `{{name:arguments}}` syntax, unknown commands rejected, bounded depth, and no arbitrary AutoHotkey or shell. The only networked macro is `{{ai}}`, and only on a phrase whose AI phrase checkbox is on.
- Design specs and plans live under `docs/superpowers/specs/` and `docs/superpowers/plans/`.
