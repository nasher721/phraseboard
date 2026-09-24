# PhraseBoard Macro Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn phrase templates into a bounded, composable macro system with nested values, forms, variables, conditionals, loops, data sources, and safe desktop actions.

**Architecture:** Parse a small documented grammar into typed nodes and evaluate them through an explicit context and capability registry. Never evaluate arbitrary AHK or shell source. Resolve forms before assembling output, apply post-processing in order, then hand text/cursor placement to the existing PhraseBoard insertion path.

**Tech Stack:** AutoHotkey v2, existing DPAPI store and GUI toolkit; Excel via Windows COM only when Excel is installed; no arbitrary source evaluation.

**Spec:** [PhraseBoard feature expansion spec](../specs/phraseboard-feature-expansion.md), section “Macro engine and editing.”

## Global Constraints

- “Macros are placeholders for dynamic insertion-time content.”
- “They run in source order, except forms gather inputs before output assembly.”
- “Additional processing applies ordered post-processing steps.”
- PhraseBoard remains Windows-first, AutoHotkey v2, and locally stored with DPAPI.
- Macro Recorder stays separate and macro execution never evaluates arbitrary AHK source.

## Review Focus

- Recursive nesting stops at a fixed depth; test the maximum and one over.
- Malformed syntax produces a clear validation error without silently corrupting output; test editor and insert modes.
- Loops and external reads have explicit iteration/size/time bounds; test each limit.
- Canceling a form never partially inserts text or increments usage; test cancel and complete.
- Launch/key macros use explicit allowlisted parameters; test invalid paths and unsupported keys.

---

### Task 1: Add macro lexer/parser and typed node model

**Files:**
- Create: `lib/MacroParser.ahk`
- Create: `lib/MacroEngine.ahk`
- Create: `tests/macros.ahk`
- Modify: `PhraseBoard.ahk:1-3` (module includes)

**Interfaces:**
- `MacroParser.Parse(text)` returns AST nodes `{Type, Name, Parameters, Children, SourceStart, SourceLength}` plus parse errors.
- Grammar v1 is literal text plus `{{name}}` and `{{name:param=value}}`; quoted parameter values use backslash escaping; nested arguments parse recursively.
- `MacroEngine.Render(text, context)` returns `{Text, CursorOffset, Cancelled, Errors}`. Context fields: `ClipboardText`, `TargetHwnd`, `PhraseId`, `Variables`, `TriggerCaptures`, `FormValues`, `Limits`.

- [ ] **Step 1: Write parser tests** for plain text, current date/time/clipboard/cursor tokens, named tokens, nested parameters, escaped braces, malformed delimiters, and source ranges.
- [ ] **Step 2: Run `AutoHotkey64.exe /ErrorStdOut tests\macros.ahk`**; expected: parser APIs fail.
- [ ] **Step 3: Implement the parser** without `Execute`, dynamic calls from parsed text, or `Run` of parsed source.
- [ ] **Step 4: Run parser tests**; expected: AST preserves literal content and exact source offsets.
- [ ] **Step 5: Commit** with `feat: parse phrase macro syntax`.

### Task 2: Resolve existing tokens, nested phrases, and random choices

**Files:**
- Modify: `lib/MacroEngine.ahk`
- Modify: `lib/PhraseBoardApp.ahk:288-318` (`ResolveTokens`, `ExtractCursor`, `PreviewTemplate`)
- Modify: `tests/macros.ahk`, `tests/integration.ahk`

**Interfaces:**
- `MacroEngine.Register(name, evaluator)` adds typed capability evaluators.
- Built-ins: `date`, `time`, `clipboard`, `cursor`, `prompt`, `phrase`, `random`.
- `phrase` resolves by phrase ID with recursion stack tracking; `random` chooses among explicit literal/macro alternatives.
- Defaults: maximum depth 16; output maximum 100,000 characters; cycles produce a phrase-name path.

- [ ] **Step 1: Write tests** for nested phrase content, injected-RNG alternative selection, old-token equivalence, recursion cycle, depth 16, and output limit.
- [ ] **Step 2: Run macro tests**; expected: evaluators fail.
- [ ] **Step 3: Implement evaluators and keep `ResolveTokens` as a compatibility wrapper** for existing templates.
- [ ] **Step 4: Run macro and integration tests**; expected: current token/cursor behavior is unchanged and nested phrases resolve in source order.
- [ ] **Step 5: Commit** with `feat: resolve nested and dynamic phrase macros`.

### Task 3: Add preflight forms, variables, conditionals, and bounded loops

**Files:**
- Modify: `lib/MacroParser.ahk`
- Modify: `lib/MacroEngine.ahk`
- Create: `lib/MacroForms.ahk`
- Modify: `tests/macros.ahk`

**Interfaces:**
- `form` nodes register field descriptors before rendering; `MacroForms.Collect(fields, context)` returns a values Map or `{Cancelled:true}`.
- `set(name, value)` and `get(name)` use only the per-insertion context.
- `if(condition, equals, then, else)` compares resolved scalar values without expression evaluation.
- `each(name, values, body)` accepts an explicit array and stops at 100 iterations.

- [ ] **Step 1: Write tests** for one/two-field forms, nested defaults, cancellation, per-insertion variable reset, both conditional branches, 100/101 loop items, and source-order assembly after form preflight.
- [ ] **Step 2: Run macro tests**; expected: form/control node assertions fail.
- [ ] **Step 3: Implement form preflight and bounded control nodes**; cancel returns before paste or usage-count update.
- [ ] **Step 4: Run tests**; expected: each form is collected once before output assembly while output nodes retain source order.
- [ ] **Step 5: Commit** with `feat: add forms and bounded macro control flow`.

### Task 4: Add post-processing chains and macro naming

**Files:**
- Modify: `lib/MacroParser.ahk`, `lib/MacroEngine.ahk`
- Modify: `lib/PhraseBoardApp.ahk` (editor preview and macro display)
- Modify: `tests/macros.ahk`

**Interfaces:**
- `process(input, steps)` applies registered operations in array order. V1 operations: `uppercase`, `lowercase`, `trim`, `prefix`, `suffix`, `setClipboard`.
- Human-readable names live in phrase metadata. Named macros display readable tokens; unnamed macros display raw grammar.
- Clipboard writes are deferred in the render result until the user accepts the completed phrase.

- [ ] **Step 1: Write tests** for transformation order, deferred clipboard side effects, named token display, and raw syntax when unnamed.
- [ ] **Step 2: Run macro tests**; expected: processor/display assertions fail.
- [ ] **Step 3: Implement ordered processors** with an allowlist and separate preview formatting from evaluation.
- [ ] **Step 4: Run tests**; expected: output and effects follow the declared sequence.
- [ ] **Step 5: Commit** with `feat: add named macros and output processing`.

### Task 5: Add external file/Excel, email, math, app launch, and keypress capabilities

**Files:**
- Create: `lib/MacroCapabilities.ahk`
- Modify: `lib/MacroEngine.ahk`
- Modify: `lib/PhraseBoardApp.ahk` (capability settings and errors)
- Modify: `tests/macros.ahk`

**Interfaces:**
- File reads use a user-selected path or approved PhraseBoard data path and cap input at 1 MB.
- Excel reads a chosen workbook/sheet/cell range via COM; missing local Excel returns a recoverable unavailable error.
- Email macro formats validated `to`, `subject`, `body` for insertion; sending mail is never implicit.
- Math accepts numeric operands and `+ - * /`; divide-by-zero is an error.
- App launch accepts a file-picker-selected executable and never interpolates through a shell.
- Keypress accepts an explicit supported-key enum; loop bounds cap emitted events.

- [ ] **Step 1: Write tests** for path/size limits, Excel unavailable, email formatting without sending, math and zero divisor, app-path validation, and supported/unsupported keys.
- [ ] **Step 2: Run capability tests**; expected: registry entries fail.
- [ ] **Step 3: Implement bounded adapters** and show capability errors in preview and insertion status.
- [ ] **Step 4: Run tests** with and without Excel; expected: available paths work and missing Excel reports a recoverable message.
- [ ] **Step 5: Commit** with `feat: add bounded data and desktop macro actions`.

### Task 6: Convert selected plain text into a macro and document authoring

**Files:**
- Modify: `lib/PhraseBoardApp.ahk:1159-1209` (phrase editor context action)
- Modify: `lib/MacroParser.ahk`
- Modify: `tests/integration.ahk`, `README.md`

- [ ] **Step 1: Write an integration assertion** that selecting a phrase substring and choosing “Convert to macro” replaces only that range with a valid named macro token.
- [ ] **Step 2: Run the bounded phrase-editor integration check**; expected: the action is absent.
- [ ] **Step 3: Add selection conversion** with a macro picker, parameter editor, and live preview; preserve unselected text.
- [ ] **Step 4: Run integration tests**; expected: the selected source becomes parseable syntax and preview output equals insertion output.
- [ ] **Step 5: Document syntax, bounds, forms, and Windows/Excel requirements; commit** with `feat: author macros from selected phrase text`.
