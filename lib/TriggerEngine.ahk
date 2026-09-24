#Requires AutoHotkey v2.0
#Include PhraseModel.ahk

class TriggerEngine {
    static TypingRate() => PhraseTypingRate()
    static Candidates(kind, value, targetHwnd, phrases, processName := "") {
        matches := []
        if !Trim(value)
            return matches
        if !processName && targetHwnd {
            try processName := WinGetProcessName("ahk_id " targetHwnd)
            catch
                processName := ""
        }
        processName := StrLower(processName)
        ordered := PhraseModel.FindPhrasesByTrigger(kind, value, phrases)
        for phrase in ordered {
            if Trim(phrase.Apps) {
                if !processName
                    continue
                allowed := false
                for app in StrSplit(StrLower(phrase.Apps), ",") {
                    app := Trim(app)
                    if app = processName || app = StrReplace(processName, ".exe") {
                        allowed := true
                        break
                    }
                }
                if !allowed
                    continue
            }
            for trigger in phrase.Triggers {
                if trigger.Enabled && trigger.Kind = kind && trigger.Value == value {
                    matches.Push({PhraseId: phrase.Id, TriggerId: trigger.Id, Trigger: trigger})
                    break
                }
            }
        }
        return matches
    }

    static FolderCandidates(value, folders) {
        matches := []
        for folder in folders
            for trigger in folder.Triggers
                if trigger.Enabled && trigger.Kind = "Hotkey" && trigger.Value == value {
                    matches.Push({FolderId: folder.Id, TriggerId: trigger.Id, Trigger: trigger})
                    break
                }
        return matches
    }

    static HotkeyWarnings(value, folders, exceptFolderId := "") {
        warnings := []
        key := StrLower(Trim(value))
        risky := Map("#r", "Windows Run", "#e", "File Explorer", "#d", "Show desktop",
            "!f4", "Close window", "^!delete", "Security screen", "^c", "Copy",
            "^v", "Paste", "^x", "Cut", "^z", "Undo", "^w", "Close tab/window")
        if risky.Has(key)
            warnings.Push("This shortcut commonly belongs to " risky[key] ".")
        if !RegExMatch(value, "[\^!+#<>]")
            warnings.Push("A shortcut without a modifier is likely to interfere with ordinary typing.")
        for folder in folders {
            if folder.Id = exceptFolderId
                continue
            for trigger in folder.Triggers
                if trigger.Enabled && trigger.Kind = "Hotkey" && StrLower(trigger.Value) = key {
                    warnings.Push("This shortcut is already used by folder '" folder.Name "'; both folders will appear in a chooser.")
                    return warnings
                }
        }
        return warnings
    }

    static CandidatesForInput(inputMatch, targetHwnd, phrases, processName := "") {
        matches := []
        if !processName && targetHwnd {
            try processName := WinGetProcessName("ahk_id " targetHwnd)
            catch
                processName := ""
        }
        processName := StrLower(processName)
        for phrase in phrases {
            if Trim(phrase.Apps) {
                if !processName
                    continue
                allowed := false
                for app in StrSplit(StrLower(phrase.Apps), ",") {
                    app := Trim(app)
                    if app = processName || app = StrReplace(processName, ".exe") {
                        allowed := true
                        break
                    }
                }
                if !allowed
                    continue
            }
            for trigger in phrase.Triggers {
                if !trigger.Enabled || trigger.Kind != "Autotext"
                    continue
                smartCase := trigger.Options.Has("CaseMode") && trigger.Options["CaseMode"] = "SmartCase"
                eligible := trigger.Value == inputMatch
                if smartCase
                    for variant in TriggerEngine.AutotextVariants(trigger)
                        if variant == inputMatch
                            eligible := true
                alreadyAdded := false
                if eligible
                    for match in matches
                        if match.PhraseId = phrase.Id
                            alreadyAdded := true
                if eligible && !alreadyAdded
                    matches.Push({PhraseId: phrase.Id, TriggerId: trigger.Id, Trigger: trigger})
            }
        }
        Loop matches.Length {
            index := A_Index
            while index > 1 {
                left := this.FindPhrase(phrases, matches[index].PhraseId)
                right := this.FindPhrase(phrases, matches[index - 1].PhraseId)
                if !PhraseModel.PhrasePrecedes(left, right)
                    break
                prior := matches[index - 1]
                matches[index - 1] := matches[index]
                matches[index] := prior
                index -= 1
            }
        }
        return matches
    }

    static FindPhrase(phrases, id) {
        for phrase in phrases
            if phrase.Id = id
                return phrase
        return 0
    }

    static MatchesBoundary(trigger, typedText, precedingText := "", followingText := "") {
        value := trigger.Value
        position := InStr(typedText, value, true, -1)
        options := trigger.Options
        incremental := (options.Has("Before") && options["Before"] = "Incremental")
            || (options.Has("After") && options["After"] = "Incremental")
        if !position {
            minChars := options.Has("MinChars") ? Integer(options["MinChars"]) : 1
            if incremental && StrLen(typedText) >= minChars && StrLen(typedText) < StrLen(value)
                && SubStr(value, 1, StrLen(typedText)) == typedText
                return {Matches: true, Start: 1, Length: StrLen(typedText), Incremental: true}
            return {Matches: false, Start: 0, Length: 0, Incremental: false}
        }

        before := precedingText != "" ? SubStr(precedingText, -1) : SubStr(typedText, position - 1, 1)
        afterIndex := position + StrLen(value)
        after := followingText != "" ? SubStr(followingText, 1, 1) : SubStr(typedText, afterIndex, 1)
        hasBefore := before != ""
        hasAfter := after != ""
        beforeWord := hasBefore && RegExMatch(before, "^[A-Za-z0-9_]$")
        afterWord := hasAfter && RegExMatch(after, "^[A-Za-z0-9_]$")

        wordPosition := options.Has("Position") ? options["Position"] : "Start"
        if (wordPosition = "Start" || wordPosition = "Entire") && beforeWord
            return {Matches: false, Start: 0, Length: 0, Incremental: false}
        if (wordPosition = "End" || wordPosition = "Entire") && afterWord
            return {Matches: false, Start: 0, Length: 0, Incremental: false}
        if wordPosition = "Middle" && (!beforeWord || !afterWord)
            return {Matches: false, Start: 0, Length: 0, Incremental: false}

        if !this.CheckNeighbor(options, "Before", "BeforeChars", before, hasBefore)
            return {Matches: false, Start: 0, Length: 0, Incremental: false}
        if !this.CheckNeighbor(options, "After", "AfterChars", after, hasAfter)
            return {Matches: false, Start: 0, Length: 0, Incremental: false}
        return {Matches: true, Start: position, Length: StrLen(value), Incremental: incremental}
    }

    static CheckNeighbor(options, ruleKey, charsKey, character, exists) {
        rule := options.Has(ruleKey) ? options[ruleKey] : "None"
        if rule = "None" || rule = "Incremental"
            return true
        if !exists
            return false
        if rule = "Any"
            return true
        if rule = "Alphanumeric"
            return !!RegExMatch(character, "^[A-Za-z0-9_]$")
        if rule != "CharacterSet"
            return false
        set := options.Has(charsKey) ? String(options[charsKey]) : ""
        set := StrReplace(set, "#13", Chr(13))
        set := StrReplace(set, "#9", Chr(9))
        return InStr(set, character, true) > 0
    }

    static TerminatorAction(trigger, endChar) {
        if !endChar || !trigger.Options.Has("RemoveTerminator") || !trigger.Options["RemoveTerminator"]
            return "Keep"
        if endChar = " " || InStr(".,!?;:) ]}" Chr(34) "'", endChar, true)
            return "Remove"
        return "Keep"
    }

    static ApplyCase(inputMatch, phraseText, trigger, phrases := []) {
        options := trigger.Options
        if !options.Has("CaseMode") || options["CaseMode"] != "SmartCase"
            return phraseText
        value := trigger.Value
        if value !== StrLower(value) || phraseText !== StrLower(phraseText)
            return phraseText
        for phrase in phrases
            for other in phrase.Triggers
                if other.Kind = "Autotext" && StrLower(other.Value) = StrLower(value)
                    && other.Value !== value
                    return phraseText

        typed := inputMatch
        if typed == value
            return phraseText
        if typed == StrUpper(value)
            return StrUpper(phraseText)
        title := StrUpper(SubStr(value, 1, 1)) SubStr(value, 2)
        if typed == title
            return StrUpper(SubStr(phraseText, 1, 1)) SubStr(phraseText, 2)
        return phraseText
    }

    static ConflictWarnings(trigger, phrases) {
        warnings := []
        if trigger.Kind != "Autotext"
            return warnings
        value := trigger.Value
        if RegExMatch(value, "^[A-Za-z0-9]{1,2}$")
            warnings.Push("This short, ordinary autotext may interfere with normal typing.")
        for phrase in phrases
            for other in phrase.Triggers {
                if other.Kind != "Autotext" || other.Value == value
                    continue
                if StrLower(other.Value) = StrLower(value) {
                    warnings.Push("A case-variant registration ('" other.Value "') makes SmartCase ambiguous.")
                    return warnings
                }
                if SubStr(other.Value, 1, StrLen(value)) == value
                    || SubStr(value, 1, StrLen(other.Value)) == other.Value {
                    warnings.Push("This autotext overlaps with '" other.Value "'.")
                    return warnings
                }
            }
        return warnings
    }

    static SmartCaseWarnings(trigger, phraseText, phrases) {
        warnings := []
        if !trigger.Options.Has("CaseMode") || trigger.Options["CaseMode"] != "SmartCase"
            return warnings
        if trigger.Value !== StrLower(trigger.Value)
            warnings.Push("SmartCase requires a lowercase autotext.")
        if phraseText !== StrLower(phraseText)
            warnings.Push("SmartCase requires lowercase phrase content.")
        for phrase in phrases
            for other in phrase.Triggers
                if other.Kind = "Autotext" && StrLower(other.Value) = StrLower(trigger.Value)
                    && other.Value !== trigger.Value {
                    warnings.Push("SmartCase is disabled by the case-variant trigger '" other.Value "'.")
                    return warnings
                }
        return warnings
    }

    static ModeDecision(mode, elapsedMs, adaptivePauseMs, confirmed := false) {
        switch mode {
            case "Immediate":
                return "Fire"
            case "Confirm":
                return confirmed ? "Fire" : "Confirm"
            case "AfterPause":
                return elapsedMs >= adaptivePauseMs ? "Fire" : "Wait"
            case "WhileTypingFast":
                return elapsedMs >= adaptivePauseMs ? "Dismiss" : "Suggest"
            default:
                return "Wait"
        }
    }

    static AdaptivePause(intervals, minMs := 200, maxMs := 1200) {
        if !intervals.Length
            return Max(1, minMs)
        total := 0
        for interval in intervals
            total += Max(1, interval)
        average := total / intervals.Length
        return Max(minMs, Min(maxMs, Round(average * 3)))
    }

    __New(app) {
        this.App := app
        this.Bindings := []
    }

    Unregister() {
        HotIf(this.App.HotstringContext)
        try {
            for binding in this.Bindings
                if binding.Kind = "Autotext"
                    Hotstring(binding.Key, , "Off")
            HotIf(this.App.FolderHotkeyContext)
            for binding in this.Bindings
                if binding.Kind = "FolderHotkey"
                    Hotkey(binding.Key, , "Off")
            this.Bindings := []
        } finally HotIf()
    }

    Register(phrases, folders := []) {
        this.Unregister()
        groups := Map()
        groups.CaseSensitive := true
        for phrase in phrases
            for trigger in phrase.Triggers {
                if trigger.Kind != "Autotext" || !trigger.Enabled || !Trim(trigger.Value)
                    continue
                variants := TriggerEngine.AutotextVariants(trigger)
                for variant in variants
                    if !groups.Has(variant)
                        groups[variant] := true
            }
        HotIf(this.App.HotstringContext)
        try {
            for variant in groups {
                key := ":CO?:" variant
                callback := ObjBindMethod(this.App, "ExpandTrigger", variant)
                Hotstring(key, callback, this.App.Expansions ? "On" : "Off")
                this.Bindings.Push({Kind: "Autotext", Key: key})
            }
            HotIf(this.App.FolderHotkeyContext)
            hotkeys := Map()
            for folder in folders
                for trigger in folder.Triggers {
                    if trigger.Kind != "Hotkey" || !trigger.Enabled || !Trim(trigger.Value)
                        continue
                    if !hotkeys.Has(trigger.Value)
                        hotkeys[trigger.Value] := true
            }
            for key in hotkeys {
                if Map("^+v", true, "!+v", true, "^!Space", true, "^!+h", true).Has(key) {
                    this.App.Notify("Folder hotkey conflicts with a PhraseBoard shortcut: " key)
                    continue
                }
                try {
                    Hotkey(key, ObjBindMethod(this.App, "OpenFolderTrigger", key), "On")
                    this.Bindings.Push({Kind: "FolderHotkey", Key: key})
                } catch as err {
                    this.App.Notify("Could not register folder hotkey '" key "': " err.Message)
                }
            }
        } finally HotIf()
    }

    static AutotextVariants(trigger) {
        variants := [trigger.Value]
        if !trigger.Options.Has("CaseMode") || trigger.Options["CaseMode"] != "SmartCase"
            return variants
        value := trigger.Value
        for variant in [StrUpper(value), StrUpper(SubStr(value, 1, 1)) SubStr(value, 2)] {
            exists := false
            for current in variants
                if current == variant
                    exists := true
            if !exists
                variants.Push(variant)
        }
        return variants
    }
}

class PhraseTypingRate {
    Timestamps := []

    Record(timestamp) {
        timestamp := Integer(timestamp)
        if this.Timestamps.Length && timestamp < this.Timestamps[this.Timestamps.Length]
            throw Error("Typing timestamps must be monotonic.")
        this.Timestamps.Push(timestamp)
        while this.Timestamps.Length > 32
            this.Timestamps.RemoveAt(1)
        return this.Timestamps.Length
    }

    Threshold(samples := 5, configuredFloor := 200) {
        if this.Timestamps.Length < 2
            return Max(1, configuredFloor)
        count := Min(Max(1, Integer(samples)), this.Timestamps.Length - 1)
        intervals := []
        index := this.Timestamps.Length - count + 1
        while index <= this.Timestamps.Length {
            intervals.Push(this.Timestamps[index] - this.Timestamps[index - 1])
            index += 1
        }
        return Max(configuredFloor, TriggerEngine.AdaptivePause(intervals, 1, 10000))
    }

    Evaluate(mode, elapsedMs, configuredFloor := 200, samples := 5, confirmed := false) {
        return TriggerEngine.ModeDecision(mode, elapsedMs,
            this.Threshold(samples, configuredFloor), confirmed)
    }
}
