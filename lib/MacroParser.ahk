#Requires AutoHotkey v2.0

class MacroParser {
    static Parse(text) {
        nodes := []
        errors := []
        len := StrLen(text)
        i := 1
        lastLitStart := 1
        litBuffer := ""

        while i <= len {
            char := SubStr(text, i, 1)

            ; Handle escape sequence: \{{ or \}} or \{ or \}
            if char = "\" && i < len {
                nextChar := SubStr(text, i + 1, 1)
                if nextChar = "{" || nextChar = "}" || nextChar = "\" {
                    litBuffer .= nextChar
                    i += 2
                    continue
                }
            }

            ; Check for opening "{{"
            if char = "{" && i < len && SubStr(text, i + 1, 1) = "{" {
                ; Flush preceding literal text
                if litBuffer != "" {
                    nodes.Push({
                        Type: "Literal",
                        Text: litBuffer,
                        SourceStart: lastLitStart,
                        SourceLength: StrLen(litBuffer)
                    })
                    litBuffer := ""
                }

                macroStart := i
                i += 2 ; skip "{{"
                bodyStart := i

                ; Find matching closing "}}" taking into account nested "{{"
                depth := 1
                body := ""
                foundClose := false

                while i <= len {
                    c := SubStr(text, i, 1)
                    if c = "\" && i < len {
                        nc := SubStr(text, i + 1, 1)
                        if nc = "{" || nc = "}" {
                            i += 2
                            continue
                        }
                    }
                    if c = "{" && i < len && SubStr(text, i + 1, 1) = "{" {
                        depth++
                        i += 2
                        continue
                    }
                    if c = "}" && i < len && SubStr(text, i + 1, 1) = "}" {
                        depth--
                        if depth = 0 {
                            body := SubStr(text, bodyStart, i - bodyStart)
                            i += 2 ; skip "}}"
                            foundClose := true
                            break
                        }
                        i += 2
                        continue
                    }
                    i++
                }

                if !foundClose {
                    errors.Push({
                        Message: "Unclosed macro delimiter '{{'",
                        SourceStart: macroStart,
                        SourceLength: len - macroStart + 1
                    })
                    ; Treat the rest as literal
                    rawRemainder := SubStr(text, macroStart)
                    nodes.Push({
                        Type: "Literal",
                        Text: rawRemainder,
                        SourceStart: macroStart,
                        SourceLength: StrLen(rawRemainder)
                    })
                    break
                }

                ; Parse macro body
                macroNode := this.ParseMacroBody(body, macroStart, i - macroStart)
                nodes.Push(macroNode)
                lastLitStart := i
                continue
            }

            litBuffer .= char
            i++
        }

        if litBuffer != "" {
            nodes.Push({
                Type: "Literal",
                Text: litBuffer,
                SourceStart: lastLitStart,
                SourceLength: StrLen(litBuffer)
            })
        }

        return {Nodes: nodes, Errors: errors}
    }

    static ParseMacroBody(body, sourceStart, sourceLength) {
        trimmed := Trim(body)
        if trimmed = "" {
            return {
                Type: "Macro",
                Name: "",
                Raw: body,
                Params: [],
                ParamMap: Map(),
                SourceStart: sourceStart,
                SourceLength: sourceLength
            }
        }

        ; Split name and arguments at the first un-nested colon
        colonPos := this.FindTopLevelChar(trimmed, ":")
        name := ""
        argsString := ""

        if colonPos = 0 {
            name := Trim(trimmed)
            argsString := ""
        } else {
            name := Trim(SubStr(trimmed, 1, colonPos - 1))
            argsString := SubStr(trimmed, colonPos + 1)
        }

        ; Parse parameters split by '|' or ',' at top level
        params := []
        paramMap := Map()

        if Trim(argsString) != "" {
            argTokens := this.SplitTopLevel(argsString)
            for rawArg in argTokens {
                argTrimmed := Trim(rawArg)
                eqPos := this.FindTopLevelChar(argTrimmed, "=")

                if eqPos > 0 {
                    key := StrLower(Trim(SubStr(argTrimmed, 1, eqPos - 1)))
                    val := Trim(SubStr(argTrimmed, eqPos + 1))
                    val := this.Unquote(val)
                    params.Push({Key: key, Value: val})
                    paramMap[key] := val
                } else {
                    val := this.Unquote(argTrimmed)
                    params.Push({Key: "", Value: val})
                }
            }
        }

        return {
            Type: "Macro",
            Name: StrLower(name),
            RawName: name,
            Raw: body,
            Params: params,
            ParamMap: paramMap,
            SourceStart: sourceStart,
            SourceLength: sourceLength
        }
    }

    ; {{ai}} takes instruction|input. Commas and "=" stay inside the instruction.
    static AiInstructionAndInput(rawBody) {
        trimmed := Trim(rawBody)
        colon := this.FindTopLevelChar(trimmed, ":")
        args := colon ? SubStr(trimmed, colon + 1) : ""
        pipe := this.FindTopLevelChar(args, "|")
        if pipe = 0
            return {Instruction: Trim(args), Input: ""}
        return {
            Instruction: Trim(SubStr(args, 1, pipe - 1)),
            Input: Trim(SubStr(args, pipe + 1))
        }
    }

    static SplitTopLevel(str) {
        items := []
        len := StrLen(str)
        i := 1
        buf := ""
        depthBraces := 0
        inQuote := false
        quoteChar := ""

        ; Determine delimiter: if comma is present at top level, use comma; otherwise use pipe
        hasComma := (this.FindTopLevelChar(str, ",") > 0)
        hasPipe := (this.FindTopLevelChar(str, "|") > 0)
        delimiter := hasComma ? "," : (hasPipe ? "|" : ",")

        while i <= len {
            ch := SubStr(str, i, 1)

            if !inQuote && (ch = '"' || ch = "'") {
                inQuote := true
                quoteChar := ch
                buf .= ch
                i++
                continue
            }
            if inQuote && ch = quoteChar {
                if i < len && SubStr(str, i + 1, 1) = quoteChar {
                    buf .= quoteChar
                    i += 2
                    continue
                }
                inQuote := false
                quoteChar := ""
                buf .= ch
                i++
                continue
            }

            if !inQuote {
                if ch = "{" && i < len && SubStr(str, i + 1, 1) = "{" {
                    depthBraces++
                    buf .= "{{"
                    i += 2
                    continue
                }
                if ch = "}" && i < len && SubStr(str, i + 1, 1) = "}" {
                    if depthBraces > 0
                        depthBraces--
                    buf .= "}}"
                    i += 2
                    continue
                }
                if depthBraces = 0 && ch = delimiter {
                    items.Push(buf)
                    buf := ""
                    i++
                    continue
                }
            }

            buf .= ch
            i++
        }

        items.Push(buf)
        return items
    }

    static FindTopLevelChar(str, targetChar) {
        len := StrLen(str)
        i := 1
        depthBraces := 0
        inQuote := false
        quoteChar := ""

        while i <= len {
            ch := SubStr(str, i, 1)
            if !inQuote && (ch = '"' || ch = "'") {
                inQuote := true
                quoteChar := ch
                i++
                continue
            }
            if inQuote && ch = quoteChar {
                inQuote := false
                quoteChar := ""
                i++
                continue
            }
            if !inQuote {
                if ch = "{" && i < len && SubStr(str, i + 1, 1) = "{" {
                    depthBraces++
                    i += 2
                    continue
                }
                if ch = "}" && i < len && SubStr(str, i + 1, 1) = "}" {
                    if depthBraces > 0
                        depthBraces--
                    i += 2
                    continue
                }
                if depthBraces = 0 && ch = targetChar {
                    return i
                }
            }
            i++
        }
        return 0
    }

    static Unquote(val) {
        val := Trim(val)
        len := StrLen(val)
        if len >= 2 {
            first := SubStr(val, 1, 1)
            last := SubStr(val, len, 1)
            if (first = '"' && last = '"') || (first = "'" && last = "'") {
                inner := SubStr(val, 2, len - 2)
                return StrReplace(inner, '\"', '"')
            }
        }
        return val
    }
}
