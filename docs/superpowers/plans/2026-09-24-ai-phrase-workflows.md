# AI Phrase Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a checked AI phrase generate text, improve a selection, and expand `{{ai}}` through Ollama or an OpenAI-compatible model, with no second prompt.

**Architecture:** PB4 adds one `AiPhrase` bit. `AiService` sends redacted provider requests through an injectable transport. The macro engine runs `{{ai}}` only when the phrase that contains it is checked, inserts the reply as plain text, and aborts the whole expansion on failure. The phrase editor keeps Generate, Improve, preview, and one-step undo behind the same checkbox.

**Tech Stack:** Windows, AutoHotkey v2, DPAPI via `SecureStore`, WinHttp for live requests, fake transports in tests.

**Spec:** [AI phrase workflows design](../specs/2026-09-24-ai-phrase-workflows-design.md).

## Global Constraints

- AI is available only on a phrase whose **AI phrase** box is checked.
- The box is off by default, including for phrases already in the library, and it can be changed later in the phrase editor.
- Checking it is the consent to send text to the configured model. There is no second prompt.
- Unchecked phrases never call a model. Checking the box does not itself send anything.
- The AI macro is the only macro that may use the network, and only for a checked phrase.
- Model replies are plain text and are never parsed as macros.
- One expansion allows at most four `{{ai}}` calls and a reply of at most 32,000 characters.
- A failed expansion pastes nothing and restores the clipboard from before the trigger.
- The API key lives only in DPAPI `ai-secrets.dat`.
- Ollama defaults to `http://127.0.0.1:11434` and uses `POST {endpoint}/api/chat`.
- OpenAI-compatible uses `POST {base}/chat/completions` and reads `choices[0].message.content`.
- Defaults are temperature 0.2, max output tokens 1024, and timeout 30 seconds.

## File structure

- `lib/Json.ahk` encodes and decodes the provider payloads.
- `lib/AiSettings.ahk` validates provider settings, builds URLs, and redacts keys.
- `lib/AiService.ahk` performs one request through a transport.
- `lib/AiWorkflows.ahk` applies selection replacement, presets, and generated name/body parsing.
- `lib/PhraseModel.ahk` and `lib/PhraseLibrary.ahk` store the PB4 flag and reject illegal AI macros on save.
- `lib/MacroEngine.ahk` evaluates `{{ai}}`.
- `lib/PhraseBoardApp.ahk` adds Settings controls and the phrase-editor actions.
- `tests/ai.ahk` covers the provider, macro, and editor helpers. `tests/model.ahk` covers PB3/PB4.

### Task 1: Library flag

- [x] Add `AiPhrase` to phrase normalization. Missing means false.
- [x] Save libraries as PB4 and still load PB3 without rewriting it.
- [x] Reject `{{ai}}` while the box is off, and reject a blank `{{ai}}` always.
- [x] Extend `tests/model.ahk` for those rules.

### Task 2: Provider

- [x] Add JSON, settings, and `AiService.Generate`.
- [x] Keep the key out of preferences, CSV export, and error text.
- [x] Cover success, missing model, URL joining, and redaction in `tests/ai.ahk`.

### Task 3: Expansion

- [x] Evaluate `{{ai:instruction}}` and `{{ai:instruction|input}}` only for a checked phrase.
- [x] Resolve nested macros first, cap calls at four, and do not parse the reply.
- [x] Cancel the whole expansion on failure. Embedded phrases use their own checkbox.

### Task 4: Editor and settings

- [x] Add the checkbox, Generate, Improve, preview, and Ctrl+Z undo.
- [x] Add global provider fields and Test connection on the Settings tab.
- [x] On an AI abort, paste nothing and restore the previous clipboard.

### Task 5: Docs and harness

- [x] Document the checkbox and PB4 in the README.
- [x] Run `tests/ai.ahk` from `tests/RunTests.ps1`.
