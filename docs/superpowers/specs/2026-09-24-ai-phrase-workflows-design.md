# AI Phrase Workflows

## Product context

PhraseBoard is a Windows AutoHotkey v2 clipboard-history and text-expansion app. Phrases, folders, triggers, and the sandboxed macro engine are stored locally and encrypted with Windows DPAPI. This design adds phrase generation, selected-text improvement, and an expansion-time AI macro.

AI is available only on a phrase whose **AI phrase** box is checked. The box is off by default, including for phrases already in the library, and it can be changed later in the phrase editor. Checking it is the consent to send text to the configured model. There is no second prompt. Unchecked phrases never call a model. Checking the box does not itself send anything.

PhraseBoard stays Windows-first. There is no cloud sync, no per-phrase provider, and no arbitrary AutoHotkey or shell execution. The AI macro is the only macro that may use the network, and only for a checked phrase. Model replies are plain text and are never parsed as macros.

This design refines the AI section of `phraseboard-feature-expansion.md`. Trigger, folder, and non-AI macro behavior already shipped stays as it is.

## Phrase flag and library

Each phrase has one boolean, `AiPhrase`. A missing value means false. New phrases start unchecked.

PB3 phrase rows have a fixed column count, so the flag is stored as library version PB4. A PB4 phrase row is a PB3 phrase row plus one final bit for `AiPhrase`. Folder rows, trigger rows, and trigger-option rows keep their PB3 shapes. The file header is `PB4`.

Opening a headerless library or a PB3 library does not rewrite `phrases.dat`. Those phrases load with `AiPhrase` false. The next successful phrase-library save writes the whole file as PB4. AI provider settings are stored separately and do not by themselves rewrite the phrase library. A damaged library is left untouched.

`ValidatePhrase` rejects a save when the body contains an `{{ai}}` macro and `AiPhrase` is false. The editor keeps the unsaved text and reports: "Check AI phrase or remove the AI macro before saving." Unchecking the box while an AI macro remains in the body fails with that same message.

At expansion time the macro engine checks the phrase that contains each `{{ai}}` macro. If that phrase is unchecked, PhraseBoard does not call a model, cancels the whole expansion, and pastes nothing. A non-AI phrase may still embed another phrase by name. The embedded phrase's own checkbox decides whether its AI macros run.

## Editor AI

Generate and Improve are disabled while **AI phrase** is off. The **+ Insert Macro** entry for AI is disabled until the box is checked. The user can still type an AI macro by hand. Save then applies the rule above.

**Improve** sends the selected text. With nothing selected, it sends the whole phrase body. The user picks Shorten, Clarify, Fix grammar, or types a custom instruction. The request contains that instruction and the chosen text. It does not contain the rest of the library. The reply opens a preview.

**Keep** replaces only the text that was sent: the selection, or the whole body when the whole body was sent. It does not change the phrase name, triggers, folder, or tags. **Discard** leaves the editor as it was. Keep does not save. The user still uses the normal Save button.

**Generate** asks for a short description and returns a suggested name and body. Both must be non-empty after trimming. If either is missing, the editor stays unchanged and PhraseBoard shows a recoverable error. Keep fills those two fields in the open editor. It does not create a second phrase, does not remove triggers, and does not save. Discard leaves the editor as it was.

Both actions send as soon as they are clicked. Keep and Discard happen after the model has already seen the text.

Ctrl+Z in the phrase editor undoes accepted AI edits newest-first. It changes the editor buffer only. If the phrase was already saved, the editor becomes unsaved, and a later Save writes the undone text. Closing the editor drops that undo stack. When the newest editor change is ordinary typing, Ctrl+Z keeps the editor's normal undo. Ctrl+Z in other applications is unchanged.

If no provider is configured, or the request fails, the editor text stays as it was and PhraseBoard shows a recoverable error. Discard also leaves the text unchanged.

## AI macro

The command is `{{ai:instruction}}` or `{{ai:instruction|input}}`. The instruction is required. The input is optional. Nested macros in either argument are expanded before the request, so `{{ai:Summarize|{{clipboard}}}}` sends the copied text. A blank `{{ai}}` is a syntax error. Save rejects it with: "AI macro requires an instruction."

The macro runs only when the phrase that contains it has **AI phrase** checked. There is no prompt at expansion time. The request contains the instruction, the resolved input, and nothing else from the library. Every AI call uses the global provider. A phrase cannot choose a different model.

The reply is inserted as plain text. PhraseBoard does not scan it for macros. One trigger expansion allows at most four `{{ai}}` calls, including calls inside embedded phrases. A reply longer than 32,000 characters fails. Each AI call counts toward the existing 16-level macro depth.

**Preview result** uses the same rules. With the box checked, preview sends and shows the rendered text. With the box off, preview does not call a model. Preview of a non-AI phrase that embeds a checked AI phrase may still send, because the embedded phrase's checkbox applies.

If the containing phrase is unchecked, the provider is missing, the request times out, the response is not successful, the reply cannot be read, the reply is empty, the reply exceeds 32,000 characters, or a fifth `{{ai}}` call is reached, PhraseBoard cancels the whole expansion. It pastes nothing and restores the clipboard from before the trigger. Text already produced earlier in that same expansion is not pasted.

## Provider and failures

AI settings are global and live on the Settings tab. The user chooses Ollama or OpenAI-compatible. Saved preferences are the provider kind, endpoint, model, temperature, token limit, and timeout. They contain no secret.

Ollama defaults to `http://127.0.0.1:11434`. That value is the server root, with no path. PhraseBoard calls `POST {endpoint}/api/chat` with streaming off and reads `message.content`. OpenAI-compatible uses a base URL the user must enter. That value is the API root, with no `/chat/completions` suffix. PhraseBoard calls `POST {base}/chat/completions` with a bearer key and reads `choices[0].message.content`. One trailing slash on either URL is removed before the path is added. There is no default cloud endpoint. A response is successful only when its HTTP status is 200 through 299 and the text field above is a non-empty string. Both providers require a model name before any request. Until a model is set, phrase AI and Test connection fail without changing phrase text.

The API key for an OpenAI-compatible provider is stored only in the DPAPI file `ai-secrets.dat`. It is never written into preferences, CSV phrase export, status text, logs, or error messages. Ollama has no API key.

Defaults are temperature 0.2 (allowed range 0 through 2), max output tokens 1024 (allowed range 1 through 4096), and timeout 30 seconds (allowed range 5 through 120). The timeout is the whole request. The 32,000-character reply cap still applies after the token limit.

**Test connection** sends a fixed prompt, "Reply with OK", and no phrase text. It reports success or a recoverable failure and does not change any phrase.

Editor failures leave the open text unchanged. Expansion failures cancel the whole expansion, paste nothing, and restore the previous clipboard. Turning **AI phrase** off, or saving an unchecked phrase that still contains `{{ai}}`, never starts a request.

## Testing

Phrase and macro rules run without the Windows UI and without a live model.

`tests/model.ahk` covers the library. A PB3 file loads with `AiPhrase` off and is not rewritten. A PB4 file round-trips the flag on and off. A missing flag stays off. Save rejects an `{{ai}}` macro while the box is off, including an uncheck that leaves the macro in the body. Save accepts that body when the box is on. A blank `{{ai}}` is rejected on save.

`tests/macros.ahk` and `tests/ai.ahk` use a fake provider that records the instruction and resolved input and returns canned text. They cover both AI macro forms, nested clipboard input resolved before the call, plain-text insertion that is not parsed again, the fifth-call failure, the 32,000-character failure, timeout, a bad response, and an empty reply. An unchecked phrase never calls the fake provider. Embedded phrases obey the checkbox on the phrase that contains the macro, and all calls in one expansion share the four-call limit.

The integration harness keeps the real clipboard and editor, with the model still faked. Generate and Improve are disabled while the box is off. Preview does not call the provider for that phrase until its box is on. Keep changes only the sent selection, or the whole body when that was sent. Generate Keep fills the name and body and leaves triggers in place. Discard leaves the editor unchanged. Ctrl+Z restores the newest accepted AI edit in the PhraseBoard editor only, and ordinary typing undo still works when the newest change is not an AI edit. A failed expansion pastes nothing and restores the clipboard. Settings persist the endpoint and model. A sentinel API key is absent from preferences, CSV phrase export, status text, and errors. Test connection does not change any phrase and does not send phrase text.

## Out of scope

This design does not add a per-expansion confirmation, a per-phrase model, cloud synchronization, a Mac client, PhraseExpress import, or a macro recorder. It does not let model output execute macros, AutoHotkey, or shell commands.
