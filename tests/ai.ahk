#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\AiService.ahk
#Include ..\lib\AiWorkflows.ahk
#Include ..\lib\MacroEngine.ahk
#Include ..\lib\PhraseLibrary.ahk

failures := []

class FakeTransport {
    __New(status, body, error := "") {
        this.Status := status
        this.Body := body
        this.Error := error
        this.Calls := []
    }
    Request(url, payload, headers, timeout) {
        this.Calls.Push({Url: url, Payload: payload, Headers: headers, Timeout: timeout})
        if this.Error
            return {Status: 0, Body: "", Error: this.Error}
        return {Status: this.Status, Body: this.Body, Error: ""}
    }
}

class FakeAi {
    __New(text := "done") {
        this.Text := text
        this.Requests := []
    }
    Call(request) {
        this.Requests.Push(request)
        if this.Text = "EMPTY"
            return {Ok: true, Text: "", Error: ""}
        if this.Text = "FAIL"
            return {Ok: false, Text: "", Error: "The AI request timed out."}
        return {Ok: true, Text: this.Text = "ECHO" ? ("OUT:" request.Input) : this.Text, Error: ""}
    }
}

round := Json.Decode(Json.Encode(Map("ok", true, "n", 2, "items", ["a", "b"])))
Assert(round["ok"] = true && round["n"] = 2 && round["items"][2] = "b", "JSON round-trips objects, numbers, and arrays")
duplicateRejected := false
try Json.Decode("{""a"":1,""a"":2}")
catch
    duplicateRejected := true
Assert(duplicateRejected, "JSON rejects duplicate keys")
trailingRejected := false
try Json.Decode("{""a"":1} trailing")
catch
    trailingRejected := true
Assert(trailingRejected, "JSON rejects trailing data")

settings := AiSettings.Validate({
    Provider: "Ollama", Endpoint: "http://127.0.0.1:11434/", Model: "llama",
    Temperature: "0.2", MaxTokens: "128", TimeoutSec: "30"
})
Assert(AiSettings.RequestUrl(settings) = "http://127.0.0.1:11434/api/chat", "Ollama URL is the server root plus /api/chat")
cloud := AiSettings.Normalize({Provider: "OpenAICompatible", Endpoint: "https://example.com/v1/", Model: "m"})
Assert(AiSettings.RequestUrl(cloud) = "https://example.com/v1/chat/completions",
    "OpenAI-compatible URL is the API root plus /chat/completions")
sentinel := "sk-SENTINEL-KEY-DO-NOT-LEAK"
Assert(!InStr(AiSettings.PreferenceSuffix(settings), sentinel), "saved AI preferences have no API key")
Assert(AiSettings.Redact("failed " sentinel, sentinel) = "failed [redacted]", "errors redact the API key")

transport := FakeTransport(200, Json.Encode(Map("message", Map("content", "hello {{date}}"))))
result := AiService.Generate({Kind: "test", Input: "phrase body", Instruction: "secret"}, settings, "", transport)
Assert(result.Ok && result.Text = "hello {{date}}", "a successful reply is returned unchanged")
sent := Json.Decode(transport.Calls[1].Payload)
Assert(sent["messages"][1]["content"] = "Reply with OK", "test connection sends no phrase text")
Assert(!InStr(transport.Calls[1].Payload, "phrase body"), "test connection payload excludes phrase text")

missingModel := AiService.Generate({Kind: "macro", Instruction: "Hi", Input: ""},
    AiSettings.Normalize({Model: ""}), "", transport)
Assert(!missingModel.Ok && missingModel.Error = "Choose an AI model before sending.",
    "a missing model does not send")
cloudTransport := FakeTransport(200, Json.Encode(Map("choices", [Map("message", Map("content", "ok"))])))
cloudResult := AiService.Generate({Kind: "macro", Instruction: "Hi", Input: ""}, cloud, sentinel, cloudTransport)
Assert(cloudResult.Ok && cloudTransport.Calls[1].Headers["Authorization"] = "Bearer " sentinel,
    "OpenAI-compatible requests send the bearer key")
leaky := FakeTransport(500, "", "boom " sentinel)
leaked := AiService.Generate({Kind: "macro", Instruction: "Hi", Input: ""}, settings, sentinel, leaky)
Assert(!leaked.Ok && !InStr(leaked.Error, sentinel) && InStr(leaked.Error, "[redacted]"),
    "provider failures redact the API key")

previewOff := MacroEngine.NewContext()
previewOff.CurrentAiPhrase := false
previewOff.AiGenerate := FakeAi("should-not-run")
offResult := MacroEngine.Render("Before {{ai:Summarize}} after", previewOff)
Assert(offResult.AiAborted && offResult.Text = "" && previewOff.AiGenerate.Requests.Length = 0,
    "an unchecked phrase never calls the model")

echo := FakeAi("ECHO")
on := MacroEngine.NewContext()
on.CurrentAiPhrase := true
on.ClipboardText := "copied text"
on.AiGenerate := echo
onResult := MacroEngine.Render("Go {{ai:Summarize|{{clipboard}}}}", on)
Assert(onResult.Text = "Go OUT:copied text" && echo.Requests[1].Instruction = "Summarize"
    && echo.Requests[1].Input = "copied text", "nested clipboard text is resolved before the AI call")

literal := FakeAi("{{date}}")
literalCtx := MacroEngine.NewContext()
literalCtx.CurrentAiPhrase := true
literalCtx.AiGenerate := literal
literalResult := MacroEngine.Render("{{ai:Hi}}", literalCtx)
Assert(literalResult.Text = "{{date}}", "an AI reply is inserted as plain text and is not parsed again")

emptyCtx := MacroEngine.NewContext()
emptyCtx.CurrentAiPhrase := true
emptyCtx.AiGenerate := FakeAi("EMPTY")
emptyResult := MacroEngine.Render("{{ai:Hi}}", emptyCtx)
Assert(emptyResult.AiAborted && emptyResult.Text = "", "an empty AI reply cancels the expansion")

failCtx := MacroEngine.NewContext()
failCtx.CurrentAiPhrase := true
failCtx.AiGenerate := FakeAi("FAIL")
failResult := MacroEngine.Render("Keep {{ai:Hi}}", failCtx)
Assert(failResult.AiAborted && failResult.Text = "", "a failed AI call pastes nothing")

longCtx := MacroEngine.NewContext()
longCtx.CurrentAiPhrase := true
longText := ""
Loop 32001
    longText .= "x"
longCtx.AiGenerate := FakeAi(longText)
longResult := MacroEngine.Render("{{ai:Hi}}", longCtx)
Assert(longResult.AiAborted && longResult.Text = "", "a reply over 32,000 characters cancels the expansion")

fifth := FakeAi("ok")
fifthCtx := MacroEngine.NewContext()
fifthCtx.CurrentAiPhrase := true
fifthCtx.AiGenerate := fifth
fifthResult := MacroEngine.Render("{{ai:A}}{{ai:B}}{{ai:C}}{{ai:D}}{{ai:E}}", fifthCtx)
Assert(fifthResult.AiAborted && fifthResult.Text = "" && fifth.Requests.Length = 4,
    "the fifth AI call cancels the expansion before it is sent")

inner := FakeAi("from-inner")
embed := MacroEngine.NewContext()
embed.CurrentAiPhrase := false
embed.AiGenerate := inner
embed.Phrases := [
    {Id: "outer", Name: "Outer", Text: "{{phrase:Inner}}", AiPhrase: false},
    {Id: "inner", Name: "Inner", Text: "{{ai:Summarize}}", AiPhrase: true}
]
embedResult := MacroEngine.Render("{{phrase:Inner}}", embed)
Assert(embedResult.Text = "from-inner" && inner.Requests.Length = 1,
    "an embedded AI phrase uses its own checkbox")

comma := FakeAi("ECHO")
commaCtx := MacroEngine.NewContext()
commaCtx.CurrentAiPhrase := true
commaCtx.ClipboardText := "copied text"
commaCtx.AiGenerate := comma
commaResult := MacroEngine.Render("{{ai:Shorten, keep meaning|{{clipboard}}}}", commaCtx)
Assert(commaResult.Text = "OUT:copied text" && comma.Requests.Length = 1
    && comma.Requests[1].Instruction = "Shorten, keep meaning",
    "a comma inside an AI instruction is not a separator")

tone := FakeAi("ok")
toneCtx := MacroEngine.NewContext()
toneCtx.CurrentAiPhrase := true
toneCtx.AiGenerate := tone
toneResult := MacroEngine.Render("{{ai:Rewrite so tone=formal}}", toneCtx)
Assert(toneResult.Text = "ok" && tone.Requests[1].Instruction = "Rewrite so tone=formal",
    "an equals sign inside an AI instruction is kept")

branch := FakeAi("FAIL")
branchCtx := MacroEngine.NewContext()
branchCtx.CurrentAiPhrase := true
branchCtx.AiGenerate := branch
branchResult := MacroEngine.Render("{{if:{{ai:A}},x,{{ai:B}}}}", branchCtx)
Assert(branchResult.AiAborted && branchResult.Text = "" && branch.Requests.Length = 1,
    "a failed AI call does not send the other branch")

plainHttp := false
try AiSettings.Validate({
    Provider: "OpenAICompatible", Endpoint: "http://example.com/v1", Model: "m",
    Temperature: "0.2", MaxTokens: "128", TimeoutSec: "30"
})
catch
    plainHttp := true
Assert(plainHttp, "a remote OpenAI-compatible endpoint must use https")
loopback := AiSettings.Validate({
    Provider: "OpenAICompatible", Endpoint: "http://127.0.0.1:8080/v1", Model: "m",
    Temperature: "0.2", MaxTokens: "128", TimeoutSec: "30"
})
Assert(loopback.Endpoint = "http://127.0.0.1:8080/v1", "loopback http is allowed for an API key")
blocked := FakeTransport(200, Json.Encode(Map("choices", [Map("message", Map("content", "secret"))])))
insecure := AiSettings.Normalize({Provider: "OpenAICompatible", Endpoint: "http://example.com/v1", Model: "m"})
denied := AiService.Generate({Kind: "macro", Instruction: "Hi", Input: "phrase body"}, insecure, sentinel, blocked)
Assert(!denied.Ok && blocked.Calls.Length = 0 && !InStr(denied.Error, "phrase body"),
    "plain http does not send the API key or the phrase")

controlTransport := FakeTransport(200, Json.Encode(Map("message", Map("content", "a" Chr(1) "b`nc"))))
controlResult := AiService.Generate({Kind: "macro", Instruction: "Hi", Input: ""}, settings, "", controlTransport)
Assert(controlResult.Ok && controlResult.Text = "ab`nc", "replies drop control characters other than tab and newline")
Assert(WinHttpTransport.TransportError("The operation timed out") = "The AI request timed out.",
    "WinHttp timeout text is reported as a timeout")

keptBody := AiWorkflows.ParseGenerated("NAME: Note`nBODY:`nFirst`nBODY: still body")
Assert(keptBody.Name = "Note" && keptBody.Body = "First`nBODY: still body",
    "a later BODY label stays in the generated body")
Assert(AiWorkflows.ValueOffset("a`r`nb", 4) = 3 && AiWorkflows.ValueOffset("a`r`nb", 3) = 2,
    "edit selection offsets drop the extra CR")

Assert(AiWorkflows.ApplyReplacement("Hello", 1, 4, "X") = "HXo", "improve replaces only the selection")
Assert(AiWorkflows.ApplyReplacement("Hello", 0, 5, "Bye") = "Bye", "improve can replace the whole body")
generated := AiWorkflows.ParseGenerated("NAME: Sign`nBODY:`nKind regards")
Assert(generated.Name = "Sign" && generated.Body = "Kind regards", "generate requires a name and body")
draftRejected := false
try AiWorkflows.ParseGenerated("no labels")
catch
    draftRejected := true
Assert(draftRejected, "generate without a name and body is rejected")
Assert(AiWorkflows.PresetInstruction("Shorten") = "Shorten this text. Keep the meaning.",
    "Shorten is a fixed preset")
csv := PhraseLibrary.ExportCsv([PhraseModel.NormalizePhrase({Id: "c", Name: "One", Text: "Body", Abbr: ";a"})])
Assert(!InStr(csv, sentinel), "CSV phrase export does not contain the API key")

if failures.Length {
    for failure in failures
        FileAppend("FAIL: " failure "`n", "*")
    ExitApp(1)
}
FileAppend("ALL AI TESTS PASSED`n", "*")
ExitApp(0)

Assert(condition, name) {
    global failures
    if condition
        return
    failures.Push(name)
}
