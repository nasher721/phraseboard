# PhraseBoard Trigger, Macro, and AI Feature Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sequence the PhraseBoard feature expansion into reviewable subprojects with a shared requirements source and explicit dependency order.

**Architecture:** Ship the data model and migration first, then typed triggers, event triggers, the macro engine, and AI workflows. Each subproject has a separate implementation plan so it can be reviewed, implemented, and released independently. Existing clipboard/history code remains operational throughout.

**Tech Stack:** Windows, AutoHotkey v2, DPAPI local storage, current PowerShell/AHK integration harness.

**Spec:** [PhraseBoard feature expansion spec](../specs/phraseboard-feature-expansion.md).

## Global Constraints

- “Keep PhraseBoard Windows-first, AutoHotkey v2, locally stored, and protected at rest with DPAPI.”
- “Preserve clipboard capture, rich/plain paste, all current phrase fields, and existing encrypted phrase data through a versioned migration.”
- Macro evaluation uses bounded, typed capabilities and never evaluates arbitrary AHK source.
- AI cloud requests require explicit provider and payload visibility; AI is not cloud synchronization.
- Existing Windows integration tests touch the real clipboard and keyboard and must be run with PhraseBoard closed.

## Review Focus

- Headerless legacy phrase-to-PB3 migration is the gate before trigger-dependent work; the model plan owns fixture and reload assertions.
- Shared-trigger selection and caller-window restoration gate alternate trigger adapters; trigger plans own these assertions.
- Macro evaluation is bounded and side-effect controlled before AI macros use it; the macro plan owns recursion, output, iteration, and action limits.
- AI provider failures preserve drafts and redact credentials; the AI plan owns mocked-provider and sentinel-key assertions.
- Existing clipboard capture, formatted paste, pause persistence, and phrase editing remain green at every integration gate.

---

## Subproject sequence

1. [Trigger records and folders](2026-09-23-phraseboard-trigger-model-and-folders.md): versioned library, PB2 migration, folders, inherited defaults, multiple/shared triggers.
2. [Typed triggers](2026-09-23-phraseboard-typed-triggers.md): autotext, SmartComplete, matching rules, SmartCase, word boundaries, execution modes, folder menus.
3. [Hotkey and event triggers](2026-09-23-phraseboard-hotkey-and-event-triggers.md): keyboard/mouse hotkeys, regex autotext, window/time/clipboard triggers, conflict feedback.
4. [Macro engine](2026-09-23-phraseboard-macro-engine.md): parser, nested macros, forms, variables, conditionals, loops, processors, data/desktop capabilities, authoring conversion.
5. [AI workflows](2026-09-23-phraseboard-ai-workflows.md): provider configuration, local/cloud adapters, phrase generation/refinement, undo, AI macros.

## Dependency and release gates

| Gate | Required result | Unblocked work |
| --- | --- | --- |
| A | PB3 persistence reads the current headerless eight-field phrase rows, preserves current fields, and round-trips folders/triggers | Typed and event triggers |
| B | Shared trigger dispatch selects all candidates and restores the invoking target window | Event triggers |
| C | Macro parser/evaluators enforce depth, output, loop, path, and action bounds | AI macro integration |
| D | Provider adapters redact secrets and return recoverable errors | AI workflows |
| E | Full current clipboard/phrase integration harness passes after each subproject | Release candidate |

The README currently excludes arbitrary scripting macros and PhraseExpress import. This request supersedes the macro exclusion but does not request PhraseExpress import, synchronization, or a Mac/iOS app. Portable Mac modifier names are shortcut interchange only. Macro Recorder remains separate.

## Requirement coverage check

| Requirement group | Owning plan |
| --- | --- |
| Multiple/shared phrase triggers, folders, inherited defaults, legacy migration | Trigger model and folders |
| Hotkey combinations, conflict warnings, portable Mac modifiers, folder menus | Hotkey/event triggers and typed triggers |
| SmartComplete, autotext length/case/word boundaries, trailing-character option, execution modes | Typed triggers |
| Regex autotext, window, daily-time, exact/regex clipboard events | Hotkey and event triggers |
| Nested macros, forms, ordered execution/processors, naming, selection conversion, all listed desktop capabilities | Macro engine |
| Text improvement/generation, presets/custom instructions, provider settings, undo, AI macro input/pure generation | AI workflows |
| Windows/local DPAPI boundaries, preservation of current phrase/clipboard behavior | All plans; migration and integration gates in trigger model and folders |
