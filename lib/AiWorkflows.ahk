#Requires AutoHotkey v2.0

class AiWorkflows {
    static PresetInstruction(preset, custom := "") {
        if preset = "Shorten"
            return "Shorten this text. Keep the meaning."
        if preset = "Clarify"
            return "Clarify this text. Keep the meaning."
        if preset = "Fix grammar"
            return "Fix grammar and spelling. Keep the meaning."
        if preset = "Custom" {
            instruction := Trim(custom)
            if instruction = ""
                throw Error("Type an instruction.")
            return instruction
        }
        throw Error("Choose a preset or type an instruction.")
    }

    ; Edit controls count CRLF as two characters. Phrase text stores LF as one.
    static ValueOffset(raw, controlOffset) {
        if controlOffset <= 0
            return 0
        if controlOffset > StrLen(raw)
            controlOffset := StrLen(raw)
        head := SubStr(raw, 1, controlOffset)
        returns := 0
        StrReplace(head, "`r", "", false, &returns)
        return controlOffset - returns
    }

    static ApplyReplacement(body, start, end, replacement) {
        if start < 0 || end < start || end > StrLen(body)
            throw Error("The selection is outside the phrase body.")
        return SubStr(body, 1, start) replacement SubStr(body, end + 1)
    }

    static ParseGenerated(text) {
        name := ""
        body := ""
        foundBody := false
        startedBody := false
        for line in StrSplit(StrReplace(text, "`r", ""), "`n") {
            if !foundBody && RegExMatch(line, "i)^NAME:\s*(.*)$", &match) {
                name := Trim(match[1])
                continue
            }
            if !foundBody && RegExMatch(line, "i)^BODY:\s*(.*)$", &match) {
                foundBody := true
                body := match[1]
                startedBody := true
                continue
            }
            if foundBody
                body .= (startedBody ? "`n" : "") line
        }
        name := Trim(name)
        body := Trim(body, " `t`r`n")
        if name = "" || body = ""
            throw Error("The AI draft needs a name and body.")
        return {Name: name, Body: body}
    }
}
