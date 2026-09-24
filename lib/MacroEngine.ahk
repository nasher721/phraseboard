#Requires AutoHotkey v2.0
#Include MacroParser.ahk
#Include MacroForms.ahk

class MacroEngine {
    static MaxRecursionDepth := 16
    static MaxOutputLength := 100000
    static MaxLoopIterations := 100
    static MaxFileSizeBytes := 102400 ; 100 KB

    static Render(templateText, context := 0) {
        if !IsObject(context)
            context := this.NewContext()

        ; Preflight form collection if top-level and not yet collected
        if context.RecursionDepth = 0 && !context.FormCollected {
            preResult := this.Preflight(templateText, context)
            if preResult.Cancelled
                return {Text: "", CursorOffset: 0, Cancelled: true, Errors: preResult.Errors}
        }

        parsed := MacroParser.Parse(templateText)
        if parsed.Errors.Length > 0 {
            for err in parsed.Errors
                context.Errors.Push(err)
        }

        resultText := ""
        cursorPos := -1

        for node in parsed.Nodes {
            if node.Type = "Literal" {
                resultText .= node.Text
            } else if node.Type = "Macro" {
                expanded := this.EvaluateMacro(node, context)
                if context.Cancelled
                    return {Text: "", CursorOffset: 0, Cancelled: true, Errors: context.Errors}

                if node.Name = "cursor" {
                    cursorPos := StrLen(resultText)
                } else {
                    resultText .= expanded
                }
            }

            if StrLen(resultText) > this.MaxOutputLength {
                resultText := SubStr(resultText, 1, this.MaxOutputLength)
                context.Errors.Push({Message: "Output exceeded maximum length limit of " this.MaxOutputLength " characters."})
                break
            }
        }

        cursorOffset := 0
        if cursorPos >= 0 {
            ; Characters from the end of the text
            cursorOffset := StrLen(resultText) - cursorPos
        }

        return {
            Text: resultText,
            CursorOffset: cursorOffset,
            Cancelled: false,
            Errors: context.Errors,
            PostActions: context.PostActions
        }
    }

    static Preflight(templateText, context) {
        context.FormCollected := true
        parsed := MacroParser.Parse(templateText)
        fields := []
        formTitle := "PhraseBoard - Fill Details"

        for node in parsed.Nodes {
            if node.Type = "Macro" {
                if node.Name = "form" {
                    if node.ParamMap.Has("title")
                        formTitle := node.ParamMap["title"]
                    for p in node.Params {
                        if p.Key = "title"
                            continue
                        keyName := p.Key ? p.Key : p.Value
                        label := p.Key ? p.Key : p.Value
                        defaultVal := p.Key ? p.Value : ""
                        options := []
                        if InStr(defaultVal, "[") && InStr(defaultVal, "]") {
                            ; Parse options like [Low|Medium|High]
                            inner := SubStr(defaultVal, InStr(defaultVal, "[") + 1)
                            inner := SubStr(inner, 1, InStr(inner, "]") - 1)
                            options := StrSplit(inner, "|")
                            defaultVal := options.Length > 0 ? options[1] : ""
                        }
                        fields.Push({Key: keyName, Label: label, Default: defaultVal, Options: options})
                    }
                } else if node.Name = "prompt" {
                    label := "Prompt"
                    defaultVal := ""
                    if node.Params.Length > 0 {
                        if node.Params[1].Key != "" {
                            label := node.Params[1].Key
                            defaultVal := node.Params[1].Value
                        } else {
                            label := node.Params[1].Value
                        }
                    }
                    if node.ParamMap.Has("default")
                        defaultVal := node.ParamMap["default"]
                    fields.Push({Key: label, Label: label, Default: defaultVal, Options: []})
                }
            }
        }

        if fields.Length > 0 {
            collected := MacroForms.Collect(fields, formTitle, context.TargetHwnd)
            if IsObject(collected) && HasProp(collected, "Cancelled") && collected.Cancelled {
                context.Cancelled := true
                return {Cancelled: true, Errors: []}
            }
            if collected is Map {
                for k, v in collected
                    context.FormValues[k] := v
            }
        }

        return {Cancelled: false, Errors: []}
    }

    static EvaluateMacro(node, context) {
        name := node.Name

        switch name {
            case "date":
                return this.EvalDate(node, context)
            case "time":
                return this.EvalTime(node, context)
            case "clipboard":
                return context.ClipboardText != "" ? context.ClipboardText : A_Clipboard
            case "cursor":
                return ""
            case "prompt":
                return this.EvalPrompt(node, context)
            case "phrase":
                return this.EvalPhrase(node, context)
            case "random":
                return this.EvalRandom(node, context)
            case "set":
                return this.EvalSet(node, context)
            case "get":
                return this.EvalGet(node, context)
            case "if":
                return this.EvalIf(node, context)
            case "each":
                return this.EvalEach(node, context)
            case "process":
                return this.EvalProcess(node, context)
            case "calc":
                return this.EvalCalc(node, context)
            case "file":
                return this.EvalFile(node, context)
            case "form":
                return this.EvalForm(node, context)
            default:
                ; Check if there is a variable matching the macro name
                if context.Variables.Has(name)
                    return context.Variables[name]
                if context.FormValues.Has(name)
                    return context.FormValues[name]
                ; Return raw placeholder if unknown
                return "{{" node.Raw "}}"
        }
    }

    static EvalDate(node, context) {
        format := node.ParamMap.Has("format") ? node.ParamMap["format"] : "yyyy-MM-dd"
        offset := node.ParamMap.Has("offset") ? node.ParamMap["offset"] : ""

        targetTime := A_Now
        if offset != "" {
            targetTime := this.ApplyDateOffset(A_Now, offset)
        }
        return FormatTime(targetTime, format)
    }

    static ApplyDateOffset(baseTime, offsetStr) {
        offsetStr := Trim(offsetStr)
        if RegExMatch(offsetStr, "i)^([+-]?\d+)\s*([dwmy])$", &m) {
            num := Integer(m[1])
            unit := StrLower(m[2])
            switch unit {
                case "d":
                    return DateAdd(baseTime, num, "Days")
                case "w":
                    return DateAdd(baseTime, num * 7, "Days")
                case "m":
                    return DateAdd(baseTime, num * 30, "Days")
                case "y":
                    return DateAdd(baseTime, num * 365, "Days")
            }
        }
        return baseTime
    }

    static EvalTime(node, context) {
        format := node.ParamMap.Has("format") ? node.ParamMap["format"] : "HH:mm"
        return FormatTime(A_Now, format)
    }

    static EvalPrompt(node, context) {
        label := "Value"
        defaultVal := ""

        if node.Params.Length > 0 {
            if node.Params[1].Key != "" {
                label := node.Params[1].Key
                defaultVal := node.Params[1].Value
            } else {
                label := node.Params[1].Value
            }
        }
        if node.ParamMap.Has("default")
            defaultVal := node.ParamMap["default"]

        ; If preflight collected this prompt
        if context.FormValues.Has(label)
            return context.FormValues[label]

        ; Fallback to single prompt modal if not pre-collected
        res := MacroForms.Prompt(label, defaultVal)
        if res.Cancelled {
            context.Cancelled := true
            return ""
        }
        context.FormValues[label] := res.Value
        return res.Value
    }

    static EvalPhrase(node, context) {
        phraseIdentifier := ""
        if node.Params.Length > 0 {
            phraseIdentifier := node.Params[1].Value ? node.Params[1].Value : node.Params[1].Key
        }
        if node.ParamMap.Has("name")
            phraseIdentifier := node.ParamMap["name"]
        if node.ParamMap.Has("id")
            phraseIdentifier := node.ParamMap["id"]

        phraseIdentifier := Trim(phraseIdentifier)
        if phraseIdentifier = ""
            return ""

        ; Check recursion depth limit
        if context.RecursionDepth >= this.MaxRecursionDepth {
            context.Errors.Push({Message: "Maximum phrase recursion depth (16) exceeded."})
            return "[Error: Max recursion depth exceeded]"
        }

        ; Locate phrase
        targetPhrase := 0
        if IsObject(context.Phrases) {
            for p in context.Phrases {
                if p.Id = phraseIdentifier || StrLower(p.Name) = StrLower(phraseIdentifier) {
                    targetPhrase := p
                    break
                }
            }
        }

        if !targetPhrase {
            context.Errors.Push({Message: "Referenced phrase not found: " phraseIdentifier})
            return "[Phrase not found: " phraseIdentifier "]"
        }

        ; Cycle detection
        for visitedId in context.PhraseStack {
            if visitedId = targetPhrase.Id {
                cycleMsg := "Recursion cycle detected: "
                for vid in context.PhraseStack
                    cycleMsg .= vid " -> "
                cycleMsg .= targetPhrase.Id
                context.Errors.Push({Message: cycleMsg})
                return "[" cycleMsg "]"
            }
        }

        ; Create child context
        childContext := this.CloneContext(context)
        childContext.RecursionDepth := context.RecursionDepth + 1
        childContext.PhraseStack.Push(targetPhrase.Id)

        childResult := this.Render(targetPhrase.Text, childContext)
        if childResult.Cancelled {
            context.Cancelled := true
            return ""
        }
        return childResult.Text
    }

    static EvalRandom(node, context) {
        choices := []
        for p in node.Params {
            val := p.Value ? p.Value : p.Key
            if val != ""
                choices.Push(val)
        }
        if choices.Length = 0
            return ""

        idx := 1
        if HasProp(context, "RngSeed") && context.RngSeed > 0 {
            idx := Mod(context.RngSeed, choices.Length) + 1
        } else {
            idx := Random(1, choices.Length)
        }
        selected := choices[idx]

        ; Resolve any nested macro in the selected choice
        if InStr(selected, "{{") {
            sub := this.Render(selected, context)
            return sub.Text
        }
        return selected
    }

    static EvalSet(node, context) {
        varName := ""
        varVal := ""

        if node.Params.Length >= 2 {
            varName := node.Params[1].Value ? node.Params[1].Value : node.Params[1].Key
            varVal := node.Params[2].Value ? node.Params[2].Value : node.Params[2].Key
        } else if node.Params.Length = 1 {
            if node.Params[1].Key != "" {
                varName := node.Params[1].Key
                varVal := node.Params[1].Value
            }
        }

        varName := Trim(varName)
        if varName != "" {
            ; If value contains nested macros, resolve it
            if InStr(varVal, "{{") {
                rendered := this.Render(varVal, context)
                varVal := rendered.Text
            }
            context.Variables[varName] := varVal
        }
        return ""
    }

    static EvalGet(node, context) {
        varName := ""
        defaultVal := ""
        if node.Params.Length > 0
            varName := node.Params[1].Value ? node.Params[1].Value : node.Params[1].Key
        if node.ParamMap.Has("default")
            defaultVal := node.ParamMap["default"]

        varName := Trim(varName)
        if context.Variables.Has(varName)
            return context.Variables[varName]
        if context.FormValues.Has(varName)
            return context.FormValues[varName]
        return defaultVal
    }

    static EvalIf(node, context) {
        ; Syntax: {{if:val1,val2,thenText,elseText}}
        val1 := ""
        val2 := ""
        thenText := ""
        elseText := ""

        if node.Params.Length >= 3 {
            val1 := node.Params[1].Value
            val2 := node.Params[2].Value
            thenText := node.Params[3].Value
            if node.Params.Length >= 4
                elseText := node.Params[4].Value
        } else {
            if node.ParamMap.Has("condition")
                val1 := node.ParamMap["condition"]
            if node.ParamMap.Has("equals")
                val2 := node.ParamMap["equals"]
            if node.ParamMap.Has("then")
                thenText := node.ParamMap["then"]
            if node.ParamMap.Has("else")
                elseText := node.ParamMap["else"]
        }

        ; Resolve nested macros in val1 and val2
        if InStr(val1, "{{")
            val1 := this.Render(val1, context).Text
        if InStr(val2, "{{")
            val2 := this.Render(val2, context).Text

        isMatch := (StrLower(Trim(val1)) = StrLower(Trim(val2)))
        chosen := isMatch ? thenText : elseText

        if InStr(chosen, "{{")
            return this.Render(chosen, context).Text
        return chosen
    }

    static EvalEach(node, context) {
        ; Syntax: {{each:item,val1|val2|val3,body}}
        if node.Params.Length < 3
            return ""

        varName := Trim(node.Params[1].Value)
        rawItems := node.Params[2].Value
        bodyTemplate := node.Params[3].Value

        ; Split items by '|' or ','
        itemList := InStr(rawItems, "|") ? StrSplit(rawItems, "|") : StrSplit(rawItems, ",")
        out := ""
        iterations := 0

        for itemVal in itemList {
            iterations++
            if iterations > this.MaxLoopIterations {
                context.Errors.Push({Message: "Loop exceeded maximum iteration limit of " this.MaxLoopIterations})
                break
            }

            context.Variables[varName] := Trim(itemVal)
            subResult := this.Render(bodyTemplate, context)
            if context.Cancelled
                return ""
            out .= subResult.Text
        }
        return out
    }

    static EvalProcess(node, context) {
        ; Syntax: {{process:input,uppercase|trim}}
        if node.Params.Length < 2
            return ""

        inputText := node.Params[1].Value
        if InStr(inputText, "{{")
            inputText := this.Render(inputText, context).Text

        for i in [2, 3, 4, 5] {
            if i > node.Params.Length
                break
            step := StrLower(Trim(node.Params[i].Value ? node.Params[i].Value : node.Params[i].Key))
            switch step {
                case "uppercase":
                    inputText := StrUpper(inputText)
                case "lowercase":
                    inputText := StrLower(inputText)
                case "titlecase":
                    inputText := StrTitle(inputText)
                case "trim":
                    inputText := Trim(inputText)
                case "setclipboard":
                    context.PostActions.Push(() => (A_Clipboard := inputText))
                default:
                    if InStr(step, "prefix=") {
                        pfx := SubStr(step, 8)
                        inputText := pfx . inputText
                    } else if InStr(step, "suffix=") {
                        sfx := SubStr(step, 8)
                        inputText := inputText . sfx
                    }
            }
        }
        return inputText
    }

    static EvalCalc(node, context) {
        expr := ""
        if node.Params.Length > 0
            expr := node.Params[1].Value ? node.Params[1].Value : node.Params[1].Key
        if InStr(expr, "{{")
            expr := this.Render(expr, context).Text

        return String(this.SafeEvaluateArithmetic(expr))
    }

    static EvalFile(node, context) {
        filePath := ""
        if node.Params.Length > 0
            filePath := node.Params[1].Value ? node.Params[1].Value : node.Params[1].Key
        filePath := Trim(filePath)

        if !FileExist(filePath) {
            context.Errors.Push({Message: "File does not exist: " filePath})
            return "[File not found: " filePath "]"
        }

        fileSize := FileGetSize(filePath)
        if fileSize > this.MaxFileSizeBytes {
            context.Errors.Push({Message: "File exceeds 100 KB limit: " filePath})
            return "[File exceeds size limit]"
        }

        try {
            return FileRead(filePath, "UTF-8")
        } catch as err {
            context.Errors.Push({Message: "Failed reading file: " err.Message})
            return "[Error reading file]"
        }
    }

    static EvalForm(node, context) {
        ; During render, form fields are already in FormValues or produce nothing
        if node.Params.Length > 0 {
            firstParam := node.Params[1].Key ? node.Params[1].Key : node.Params[1].Value
            if context.FormValues.Has(firstParam)
                return context.FormValues[firstParam]
        }
        return ""
    }

    static SafeEvaluateArithmetic(expr) {
        ; Simple, safe recursive-descent parser for arithmetic: +, -, *, /, %, ^, (, )
        tokens := this.TokenizeMath(expr)
        if tokens.Length = 0
            return 0
        pos := 1
        val := this.ParseAddSub(tokens, &pos)
        if val = Round(val, 0)
            return String(Integer(val))
        res := String(Round(val, 4))
        return RegExReplace(res, "(\.\d*?[1-9])0+$|\.0+$", "$1")
    }

    static TokenizeMath(expr) {
        tokens := []
        len := StrLen(expr)
        i := 1
        while i <= len {
            ch := SubStr(expr, i, 1)
            if ch = " " || ch = "`t" {
                i++
                continue
            }
            if InStr("+-*/%^()", ch) {
                tokens.Push({Type: "Op", Value: ch})
                i++
                continue
            }
            if RegExMatch(SubStr(expr, i), "^(\d+(\.\d+)?)", &m) {
                tokens.Push({Type: "Num", Value: Float(m[1])})
                i += StrLen(m[1])
                continue
            }
            i++
        }
        return tokens
    }

    static ParseAddSub(tokens, &pos) {
        val := this.ParseMulDiv(tokens, &pos)
        while pos <= tokens.Length {
            op := tokens[pos]
            if op.Type = "Op" && (op.Value = "+" || op.Value = "-") {
                pos++
                right := this.ParseMulDiv(tokens, &pos)
                val := (op.Value = "+") ? (val + right) : (val - right)
            } else break
        }
        return val
    }

    static ParseMulDiv(tokens, &pos) {
        val := this.ParseUnary(tokens, &pos)
        while pos <= tokens.Length {
            op := tokens[pos]
            if op.Type = "Op" && (op.Value = "*" || op.Value = "/" || op.Value = "%") {
                pos++
                right := this.ParseUnary(tokens, &pos)
                if op.Value = "*"
                    val *= right
                else if op.Value = "/"
                    val := (right != 0) ? (val / right) : 0
                else if op.Value = "%"
                    val := Mod(val, right)
            } else break
        }
        return val
    }

    static ParseUnary(tokens, &pos) {
        if pos <= tokens.Length && tokens[pos].Type = "Op" && tokens[pos].Value = "-" {
            pos++
            return -this.ParsePrimary(tokens, &pos)
        }
        return this.ParsePrimary(tokens, &pos)
    }

    static ParsePrimary(tokens, &pos) {
        if pos > tokens.Length
            return 0
        tok := tokens[pos]
        if tok.Type = "Num" {
            pos++
            return tok.Value
        }
        if tok.Type = "Op" && tok.Value = "(" {
            pos++ ; skip '('
            val := this.ParseAddSub(tokens, &pos)
            if pos <= tokens.Length && tokens[pos].Type = "Op" && tokens[pos].Value = ")"
                pos++ ; skip ')'
            return val
        }
        pos++
        return 0
    }

    static NewContext() {
        return {
            ClipboardText: "",
            TargetHwnd: 0,
            PhraseId: "",
            Phrases: [],
            Variables: Map(),
            FormValues: Map(),
            FormCollected: false,
            RecursionDepth: 0,
            PhraseStack: [],
            Cancelled: false,
            Errors: [],
            PostActions: []
        }
    }

    static CloneContext(ctx) {
        newCtx := this.NewContext()
        newCtx.ClipboardText := ctx.ClipboardText
        newCtx.TargetHwnd := ctx.TargetHwnd
        newCtx.Phrases := ctx.Phrases
        newCtx.FormValues := ctx.FormValues
        newCtx.FormCollected := ctx.FormCollected
        newCtx.RecursionDepth := ctx.RecursionDepth
        newCtx.PostActions := ctx.PostActions
        for k, v in ctx.Variables
            newCtx.Variables[k] := v
        for id in ctx.PhraseStack
            newCtx.PhraseStack.Push(id)
        return newCtx
    }
}
