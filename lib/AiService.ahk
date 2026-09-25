#Requires AutoHotkey v2.0
#Include AiSettings.ahk

class AiService {
    static MaxReplyChars := 32000

    static Generate(request, settings, key, transport) {
        settings := AiSettings.Normalize(settings)
        key := key ? String(key) : ""
        try {
            if Trim(settings.Model) = ""
                return this.Failure("Choose an AI model before sending.", key)
            if settings.Provider = "OpenAICompatible" && Trim(key) = ""
                return this.Failure("Add an API key before sending.", key)
            if !AiSettings.KeyTransportAllowed(settings.Provider, settings.Endpoint)
                return this.Failure("OpenAI-compatible endpoints must use https, except on localhost.", key)
            content := this.UserContent(request)
            payload := Map(
                "model", settings.Model,
                "messages", [Map("role", "user", "content", content)],
                "temperature", settings.Temperature
            )
            if settings.Provider = "Ollama" {
                payload["stream"] := Json.False
                payload["options"] := Map("temperature", settings.Temperature, "num_predict", settings.MaxTokens)
            } else
                payload["max_tokens"] := settings.MaxTokens
            headers := Map("Content-Type", "application/json")
            if settings.Provider = "OpenAICompatible"
                headers["Authorization"] := "Bearer " key
            response := transport.Request(AiSettings.RequestUrl(settings), Json.Encode(payload), headers, settings.TimeoutSec)
            if IsObject(response) && HasProp(response, "Error") && response.Error
                return this.Failure(response.Error, key)
            status := IsObject(response) && HasProp(response, "Status") ? Integer(response.Status) : 0
            if status < 200 || status > 299
                return this.Failure("The AI request failed.", key)
            body := HasProp(response, "Body") ? response.Body : ""
            text := Trim(this.PlainText(AiSettings.ReadReply(settings.Provider, Json.Decode(body))))
            if text = ""
                return this.Failure("AI reply was empty.", key)
            if StrLen(text) > this.MaxReplyChars
                return this.Failure("AI reply exceeds 32,000 characters.", key)
            return {Ok: true, Text: text, Error: ""}
        } catch as err {
            return this.Failure(err.Message, key)
        }
    }

    static UserContent(request) {
        kind := IsObject(request) && HasProp(request, "Kind") ? request.Kind : "macro"
        input := IsObject(request) && HasProp(request, "Input") ? request.Input : ""
        instruction := IsObject(request) && HasProp(request, "Instruction") ? request.Instruction : ""
        if kind = "test"
            return "Reply with OK"
        if kind = "generate"
            return "Write a phrase from this description. Reply with exactly these labels and nothing else.`nNAME: the phrase name`nBODY:`nthe phrase body`n`nDescription: " input
        if kind = "improve"
            return instruction "`n`n" input
        if Trim(input) = ""
            return instruction
        return instruction "`n`n" input
    }

    static Failure(message, key) {
        return {Ok: false, Text: "", Error: AiSettings.Redact(message, key)}
    }

    static PlainText(text) {
        out := ""
        loop parse String(text) {
            code := Ord(A_LoopField)
            if code = 9 || code = 10 || code = 13 || code >= 32
                out .= A_LoopField
        }
        return out
    }
}

class WinHttpTransport {
    static TransportError(message) {
        text := String(message)
        if InStr(text, "timed out") || InStr(text, "timeout") || InStr(text, "80072EE2")
            return "The AI request timed out."
        return "The AI request failed."
    }

    static Request(url, body, headers, timeoutSec) {
        timeoutMs := Integer(timeoutSec) * 1000
        try {
            web := ComObject("WinHttp.WinHttpRequest.5.1")
            web.Option[6] := 0
            web.Open("POST", url, false)
            web.SetTimeouts(timeoutMs, timeoutMs, timeoutMs, timeoutMs)
            for name, value in headers
                web.SetRequestHeader(name, value)
            web.Send(body)
            return {Status: web.Status, Body: web.ResponseText, Error: ""}
        } catch as err {
            message := this.TransportError(err.Message)
            return {Status: 0, Body: "", Error: message}
        }
    }
}
