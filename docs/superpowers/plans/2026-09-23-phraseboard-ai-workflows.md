# PhraseBoard AI Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate phrases and improve selected phrase text through local or explicitly configured cloud AI providers, including an AI macro capability.

**Architecture:** Add an `AiService` provider interface with local Ollama and OpenAI-compatible HTTP adapters. Store provider settings/credentials through DPAPI. AI edits remain previews until accepted, preserve selection boundaries, and add a local undo snapshot. Macro calls resolve inputs first and pass them through the same provider interface.

**Tech Stack:** AutoHotkey v2, Windows HTTP facilities, strict JSON codec in `lib/Json.ahk`, existing DPAPI `SecureStore`, Ollama HTTP API, OpenAI-compatible HTTP API; no cloud synchronization.

**Spec:** [PhraseBoard feature expansion spec](../specs/phraseboard-feature-expansion.md), section “AI.”

## Global Constraints

- AI can improve all or selected phrase text with a preset or custom instruction.
- Users choose provider/engine and parameters.
- Generation starts from natural language and remains an editable draft until saved.
- PhraseBoard remains Windows-first, AutoHotkey v2, and locally stored with DPAPI.
- A cloud request identifies provider and exact payload before sending; editing/saving alone never uploads text.

## Review Focus

- Cancel at any point leaves phrase text and selection untouched; test cancel before request, while waiting, and at preview.
- A cloud request cannot start before provider/payload confirmation; test the confirmation boundary.
- Keys never appear in logs, errors, CSV, or plaintext preferences; test a sentinel key in each path.
- Timeout, malformed response, and unavailable Ollama preserve the draft and return a recoverable message.
- Ctrl+Z restores exactly the pre-AI phrase text once per accepted AI edit and leaves unrelated undo behavior intact.

---

### Task 1: Add encrypted provider configuration and service interface

**Files:**
- Create: `lib/AiService.ahk`
- Create: `lib/AiProviders.ahk`
- Create: `lib/Json.ahk` (strict request encoder/response decoder)
- Modify: `lib/Storage.ahk` (encrypted named secret storage if needed)
- Modify: `lib/PhraseBoardApp.ahk:50-121` (settings load)
- Modify: `lib/PhraseBoardApp.ahk:500-625` (AI settings UI)
- Create: `tests/ai.ahk`

**Interfaces:**
- `AiService.Generate(request)` returns `{Text, Provider, Model, Usage, Error}` and accepts `{Input, Instruction, Preset, Model, Temperature, MaxTokens, IsCloud}`.
- `AiProviders.Register(name, provider)`; provider implements `ListModels()`, `Generate(request)`, `ValidateSettings(settings)`.
- `Json.Encode(value)` and `Json.Decode(text)` support objects, arrays, strings, numbers, booleans, and null; reject duplicate keys, invalid escapes, trailing data, and payloads above 2 MB.
- Secrets live in DPAPI-protected `ai-secrets.dat`; provider/model/endpoint/temperature/token limit/timeout preferences contain no secret.

- [ ] **Step 1: Write tests** for strict JSON round-trip/invalid inputs, encrypted key round-trip, provider settings persistence, sentinel-key absence from CSV/status, invalid settings, and provider interface failures.
- [ ] **Step 2: Run `AutoHotkey64.exe /ErrorStdOut tests\ai.ahk`**; expected: provider and secret APIs fail.
- [ ] **Step 3: Implement `Json`, `AiService`, and encrypted settings**; thrown errors and diagnostics never include credentials.
- [ ] **Step 4: Run AI tests**; expected: settings persist, secrets remain encrypted, and sentinel text is absent from visible/exported output.
- [ ] **Step 5: Commit** with `feat: add encrypted AI provider configuration`.

### Task 2: Add Ollama and OpenAI-compatible provider adapters

**Files:**
- Modify: `lib/AiProviders.ahk`, `lib/AiService.ahk`
- Modify: `tests/ai.ahk`

**Interfaces:**
- `OllamaProvider` uses a configurable localhost endpoint and sends model/prompt/options to its generation endpoint.
- `OpenAICompatibleProvider` uses a user-configured base URL, model, and key with chat-completions-compatible requests.
- Requests have connect/read timeouts and maximum response size; diagnostics redact authorization headers and key-like strings.

- [ ] **Step 1: Add mocked HTTP tests** for success, non-2xx, timeout, malformed response, and response-size cap.
- [ ] **Step 2: Run `AutoHotkey64.exe /ErrorStdOut tests\ai.ahk`**; expected: adapter assertions fail.
- [ ] **Step 3: Implement adapters and provider settings UI** for model, endpoint, parameters, and “Test connection.”
- [ ] **Step 4: Run mocked tests and a bounded local Ollama check when available**; expected: unavailable service does not block startup.
- [ ] **Step 5: Commit** with `feat: connect local and OpenAI-compatible AI providers`.

### Task 3: Add safe phrase generation and selected-text previews

**Files:**
- Create: `lib/AiWorkflows.ahk`
- Modify: `lib/PhraseBoardApp.ahk:500-625` (preview dialog)
- Modify: `lib/PhraseBoardApp.ahk:1159-1209` (phrase editor)
- Modify: `lib/AiService.ahk`
- Modify: `tests/ai.ahk`, `tests/integration.ahk`

**Interfaces:**
- `AiWorkflows.ProcessSelection(text, instruction, preset, providerSettings)` returns original text, proposed text, and provider metadata.
- `.GeneratePhrase(description, providerSettings)` returns an unsaved name/body draft; final save uses `UpsertPhrase` validation.
- Presets/custom instructions are local until a request is confirmed. Preview shows provider and exact payload.
- Accept pushes `{Before, After, PhraseId, Timestamp}` to `AiUndoStack`; Cancel leaves source untouched.

- [ ] **Step 1: Write tests** for substring boundaries, whole phrase, generated draft, accepted/rejected preview, cancel, and one-step undo snapshot.
- [ ] **Step 2: Run AI tests**; expected: workflow tests fail.
- [ ] **Step 3: Add “AI text processing”** and phrase generation; show provider, payload, and local/cloud label before sending.
- [ ] **Step 4: Run mocked workflows and app integration**; expected: acceptance changes only selected text and cancel leaves phrase unchanged.
- [ ] **Step 5: Commit** with `feat: generate and refine phrases with AI previews`.

### Task 4: Add Ctrl+Z undo for accepted AI changes

**Files:**
- Modify: `lib/AiWorkflows.ahk`
- Modify: `lib/PhraseBoardApp.ahk:217-228` (editor-scoped undo)
- Modify: `lib/PhraseBoardApp.ahk:1159-1209` (selection restoration)
- Modify: `tests/ai.ahk`

**Interfaces:**
- `AiUndoStack.Push(entry)`, `.Undo(phraseId)` returns prior text/selection or empty when no accepted AI edit exists.
- Ctrl+Z intercepts only in the PhraseBoard editor when an AI edit is the newest undo record; otherwise native edit undo is preserved.

- [ ] **Step 1: Write tests** for accepted edit, canceled edit, two edits undone newest-first, native typing undo, and deletion clearing stale entries.
- [ ] **Step 2: Run AI tests**; expected: undo routing fails.
- [ ] **Step 3: Implement editor-scoped undo**; restored text remains unsaved until normal phrase save.
- [ ] **Step 4: Run AI/integration tests**; expected: Ctrl+Z reverses one accepted AI change and does not affect other apps.
- [ ] **Step 5: Commit** with `feat: undo accepted AI phrase edits`.

### Task 5: Add AI macro integration and document data handling

**Files:**
- Modify: `lib/MacroEngine.ahk` (AI capability)
- Modify: `lib/AiWorkflows.ahk`
- Modify: `lib/PhraseBoardApp.ahk` (privacy copy/settings)
- Modify: `tests/ai.ahk`, `README.md`

**Interfaces:**
- `AiMacro.Evaluate(input, instruction, context)` accepts resolved macro input or empty input and returns text via `AiService.Generate`.
- Cloud macros require per-invocation confirmation by default; local Ollama may use a user-configured confirmation setting.
- Output passes through the same post-processing chain as other macro output.

- [ ] **Step 1: Write tests** for nested clipboard/form input, empty generation input, cloud confirmation, configured local execution, and provider failure.
- [ ] **Step 2: Run AI and macro tests**; expected: AI macro capability is absent.
- [ ] **Step 3: Implement the AI macro adapter** with macro limits and diagnostic redaction.
- [ ] **Step 4: Run tests**; expected: no request occurs before required confirmation and failed requests never paste partial output.
- [ ] **Step 5: Document setup, local/cloud distinction, payload confirmation, key storage, and undo; commit** with `feat: support AI generation macros`.
