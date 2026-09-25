#Requires AutoHotkey v2.0
#Include Json.ahk
#Include Storage.ahk

class AiSettings {
    static Default() {
        return {
            Provider: "Ollama",
            Endpoint: "http://127.0.0.1:11434",
            Model: "",
            Temperature: 0.2,
            MaxTokens: 1024,
            TimeoutSec: 30
        }
    }

    static Normalize(settings) {
        base := this.Default()
        if !IsObject(settings)
            return base
        provider := HasProp(settings, "Provider") ? settings.Provider : ""
        if provider = "Ollama" || provider = "OpenAICompatible"
            base.Provider := provider
        endpoint := HasProp(settings, "Endpoint") ? Trim(settings.Endpoint) : ""
        if this.IsHttpUrl(endpoint)
            base.Endpoint := RTrim(endpoint, "/")
        if HasProp(settings, "Model")
            base.Model := Trim(settings.Model)
        if HasProp(settings, "Temperature") && this.IsTemperature(settings.Temperature)
            base.Temperature := this.Number(settings.Temperature)
        if HasProp(settings, "MaxTokens") && this.IsTokens(settings.MaxTokens)
            base.MaxTokens := Integer(settings.MaxTokens)
        if HasProp(settings, "TimeoutSec") && this.IsTimeout(settings.TimeoutSec)
            base.TimeoutSec := Integer(settings.TimeoutSec)
        return base
    }

    static Validate(settings) {
        normalized := this.Normalize(settings)
        if !HasProp(settings, "Provider") || (settings.Provider != "Ollama" && settings.Provider != "OpenAICompatible")
            throw Error("Choose Ollama or an OpenAI-compatible provider.")
        endpoint := HasProp(settings, "Endpoint") ? settings.Endpoint : ""
        if !this.IsHttpUrl(endpoint)
            throw Error("Enter an http or https endpoint.")
        if settings.Provider = "OpenAICompatible" && !this.KeyTransportAllowed(settings.Provider, endpoint)
            throw Error("OpenAI-compatible endpoints must use https, except on localhost.")
        if !HasProp(settings, "Temperature") || !this.IsTemperature(settings.Temperature)
            throw Error("Temperature must be from 0 through 2.")
        if !HasProp(settings, "MaxTokens") || !this.IsTokens(settings.MaxTokens)
            throw Error("Max tokens must be from 1 through 4096.")
        if !HasProp(settings, "TimeoutSec") || !this.IsTimeout(settings.TimeoutSec)
            throw Error("Timeout must be from 5 through 120 seconds.")
        return normalized
    }

    static IsHttpUrl(value) {
        return !!RegExMatch(Trim(value), "i)^https?://\S+$")
    }

    static KeyTransportAllowed(provider, endpoint) {
        if provider != "OpenAICompatible"
            return true
        endpoint := Trim(endpoint)
        if RegExMatch(endpoint, "i)^https://\S+$")
            return true
        return !!RegExMatch(endpoint, "i)^http://(\[::1\]|localhost|127\.0\.0\.1)(:\d+)?(/.*)?$")
    }

    static Host(endpoint) {
        if !RegExMatch(Trim(endpoint), "i)^https?://([^/?#]+)", &match)
            return ""
        return StrLower(match[1])
    }

    static SameKeyTarget(next, current) {
        if !IsObject(next) || !IsObject(current)
            return false
        if !HasProp(next, "Provider") || !HasProp(current, "Provider")
            return false
        if next.Provider != current.Provider
            return false
        return this.Host(next.Endpoint) = this.Host(current.Endpoint)
    }

    static IsTemperature(value) {
        return RegExMatch(String(value), "^\d+(\.\d+)?$") && this.Number(value) >= 0 && this.Number(value) <= 2
    }

    static IsTokens(value) {
        return RegExMatch(String(value), "^\d+$") && Integer(value) >= 1 && Integer(value) <= 4096
    }

    static IsTimeout(value) {
        return RegExMatch(String(value), "^\d+$") && Integer(value) >= 5 && Integer(value) <= 120
    }

    static Number(value) {
        text := String(value)
        return InStr(text, ".") ? Float(text) : Integer(text)
    }

    static PreferenceSuffix(settings) {
        normalized := this.Normalize(settings)
        return normalized.Provider "|" SecureStore.Encode(normalized.Endpoint)
            . "|" SecureStore.Encode(normalized.Model) "|" normalized.Temperature
            . "|" normalized.MaxTokens "|" normalized.TimeoutSec
    }

    static JoinUrl(base, path) {
        return RTrim(Trim(base), "/") path
    }

    static RequestUrl(settings) {
        if settings.Provider = "Ollama"
            return this.JoinUrl(settings.Endpoint, "/api/chat")
        return this.JoinUrl(settings.Endpoint, "/chat/completions")
    }

    static Redact(text, key) {
        if !key || StrLen(key) < 8
            return text
        return StrReplace(StrReplace(text, "Bearer " key, "Bearer [redacted]"), key, "[redacted]")
    }

    static ReadReply(provider, payload) {
        if !(payload is Map)
            throw Error("The AI reply could not be read.")
        if provider = "Ollama" {
            if !payload.Has("message") || !(payload["message"] is Map) || !payload["message"].Has("content")
                throw Error("The AI reply could not be read.")
            return String(payload["message"]["content"])
        }
        if !payload.Has("choices") || !(payload["choices"] is Array) || !payload["choices"].Length
            throw Error("The AI reply could not be read.")
        choice := payload["choices"][1]
        if !(choice is Map) || !choice.Has("message") || !(choice["message"] is Map)
            || !choice["message"].Has("content")
            throw Error("The AI reply could not be read.")
        return String(choice["message"]["content"])
    }
}
