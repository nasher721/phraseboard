#Requires AutoHotkey v2.0
#Include MacroParser.ahk

class PhraseModel {
    static TriggerKinds := Map(
        "Autotext", true,
        "SmartComplete", true,
        "Hotkey", true,
        "RegexAutotext", true,
        "Window", true,
        "Time", true,
        "Clipboard", true,
        "RegexClipboard", true
    )

    static NormalizePhrase(record) {
        if !IsObject(record)
            throw Error("Phrase record must be an object.")

        triggers := []
        if HasProp(record, "Triggers") {
            if !IsObject(record.Triggers)
                throw Error("Phrase triggers must be an array.")
            for trigger in record.Triggers
                triggers.Push(this.NormalizeTrigger(trigger))
        } else if HasProp(record, "Abbr") && Trim(record.Abbr) {
            triggers.Push(this.NormalizeTrigger({
                Id: (HasProp(record, "Id") ? record.Id : "legacy") "-autotext",
                Kind: "Autotext",
                Value: record.Abbr
            }))
        }

        return {
            Id: this.StringField(record, "Id"),
            Name: this.StringField(record, "Name"),
            Abbr: this.StringField(record, "Abbr"),
            Text: this.StringField(record, "Text"),
            Rtf: this.StringField(record, "Rtf"),
            Format: (HasProp(record, "Format") && record.Format = "rich") || (HasProp(record, "Rtf") && record.Rtf != "") ? "rich" : "text",
            Tags: this.StringField(record, "Tags"),
            Favorite: HasProp(record, "Favorite") && !!record.Favorite,
            Uses: HasProp(record, "Uses") ? Integer(record.Uses) : 0,
            Apps: this.StringField(record, "Apps"),
            FolderId: this.StringField(record, "FolderId"),
            AiPhrase: HasProp(record, "AiPhrase") && !!record.AiPhrase,
            Triggers: triggers
        }
    }

    static ValidatePhrase(record) {
        phrase := this.NormalizePhrase(record)
        if !Trim(phrase.Name) || !phrase.Text
            throw Error("Enter a phrase name and its text.")
        if StrLen(phrase.Text) > 100000
            throw Error("Keep each phrase under 100,000 characters.")
        if phrase.Rtf && StrLen(phrase.Rtf) > 500000
            throw Error("Keep each formatted phrase under 500,000 characters.")
        if this.HasBlankAiMacro(phrase.Text)
            throw Error("AI macro requires an instruction.")
        if this.ContainsAiMacro(phrase.Text) && !phrase.AiPhrase
            throw Error("Check AI phrase or remove the AI macro before saving.")
        for trigger in phrase.Triggers
            this.NormalizeTrigger(trigger)
        return true
    }

    static ContainsAiMacro(text) {
        return this.NodesHaveAi(MacroParser.Parse(text).Nodes, false)
    }

    static HasBlankAiMacro(text) {
        return this.NodesHaveAi(MacroParser.Parse(text).Nodes, true)
    }

    static NodesHaveAi(nodes, blankOnly) {
        for node in nodes {
            if node.Type != "Macro"
                continue
            if node.Name = "ai" {
                instruction := MacroParser.AiInstructionAndInput(node.Raw).Instruction
                if blankOnly {
                    if Trim(instruction) = ""
                        return true
                } else
                    return true
            }
            for param in node.Params
                if InStr(param.Value, "{{") && this.NodesHaveAi(MacroParser.Parse(param.Value).Nodes, blankOnly)
                    return true
        }
        return false
    }

    static NormalizeTrigger(record) {
        if !IsObject(record)
            throw Error("Trigger record must be an object.")
        kind := HasProp(record, "Kind") ? record.Kind : ""
        value := HasProp(record, "Value") ? String(record.Value) : ""
        if !this.TriggerKinds.Has(kind)
            throw Error("Unsupported trigger kind: " kind)
        if !Trim(value)
            throw Error("Trigger value cannot be blank.")
        if kind = "Autotext" && StrLen(value) > 32
            throw Error("Autotext abbreviations must be 32 characters or fewer.")

        options := Map()
        if HasProp(record, "Options") && IsObject(record.Options) {
            if record.Options is Map {
                for key, option in record.Options
                    options[key] := option
            } else {
                for key, option in record.Options.OwnProps()
                    options[key] := option
            }
        }
        if kind = "Autotext" && options.Has("CaseMode")
            && options["CaseMode"] != "Exact" && options["CaseMode"] != "SmartCase"
            throw Error("Autotext CaseMode must be Exact or SmartCase.")
        if kind = "Autotext" {
            if options.Has("Position") && !RegExMatch(String(options["Position"]), "^(Start|End|Middle|Entire)$")
                throw Error("Autotext Position must be Start, End, Middle, or Entire.")
            for key in ["Before", "After"]
                if options.Has(key) && !RegExMatch(String(options[key]), "^(None|Any|Alphanumeric|CharacterSet|Incremental)$")
                    throw Error("Autotext " key " rule is invalid.")
            if options.Has("MinChars") {
                minChars := String(options["MinChars"])
                if !RegExMatch(minChars, "^\d+$") || Integer(minChars) < 1 || Integer(minChars) > 32
                    throw Error("Autotext MinChars must be from 1 to 32.")
                options["MinChars"] := Integer(minChars)
            }
            if options.Has("RemoveTerminator") {
                remove := options["RemoveTerminator"]
                if !(remove = true || remove = false || remove = 0 || remove = 1)
                    throw Error("Autotext RemoveTerminator must be boolean.")
                options["RemoveTerminator"] := !!remove
            }
        }

        mode := HasProp(record, "Mode") ? String(record.Mode) : "Immediate"
        if (kind = "Autotext" || kind = "SmartComplete") && mode
            && !RegExMatch(mode, "^(Immediate|Confirm|AfterPause|WhileTypingFast)$")
            throw Error("Unsupported typed-trigger mode: " mode)

        return {
            Id: HasProp(record, "Id") && record.Id ? String(record.Id) : this.NewId(),
            Kind: kind,
            Value: value,
            Mode: mode,
            Enabled: !HasProp(record, "Enabled") || !!record.Enabled,
            Options: options
        }
    }

    static NormalizeFolder(record) {
        if !IsObject(record)
            throw Error("Folder record must be an object.")
        triggers := []
        if HasProp(record, "Triggers") {
            if !IsObject(record.Triggers)
                throw Error("Folder triggers must be an array.")
            for trigger in record.Triggers
                triggers.Push(this.NormalizeTrigger(trigger))
        }
        defaults := Map()
        if HasProp(record, "TriggerDefaults") && IsObject(record.TriggerDefaults) {
            if record.TriggerDefaults is Map {
                for key, value in record.TriggerDefaults
                    defaults[key] := value
            } else {
                for key, value in record.TriggerDefaults.OwnProps()
                    defaults[key] := value
            }
        }
        return {
            Id: this.StringField(record, "Id"),
            ParentId: this.StringField(record, "ParentId"),
            Name: this.StringField(record, "Name"),
            Triggers: triggers,
            TriggerDefaults: defaults,
            CreatedAt: this.StringField(record, "CreatedAt")
        }
    }

    static ResolveFolderDefaults(folderId, folders, key) {
        seen := Map()
        while folderId != "" {
            if seen.Has(folderId)
                return ""
            seen[folderId] := true
            folder := 0
            for candidate in folders {
                if candidate.Id = folderId {
                    folder := candidate
                    break
                }
            }
            if !IsObject(folder)
                return ""
            if folder.TriggerDefaults.Has(key)
                return folder.TriggerDefaults[key]
            folderId := folder.ParentId
        }
        return ""
    }

    static FindPhrasesByTrigger(kind, value, phrases) {
        matches := []
        for phrase in phrases {
            for trigger in phrase.Triggers {
                if trigger.Enabled && trigger.Kind = kind && trigger.Value == value {
                    matches.Push(phrase)
                    break
                }
            }
        }
        Loop matches.Length {
            index := A_Index
            while index > 1 && this.PhrasePrecedes(matches[index], matches[index - 1]) {
                previous := matches[index - 1]
                matches[index - 1] := matches[index]
                matches[index] := previous
                index -= 1
            }
        }
        return matches
    }

    static PhrasePrecedes(left, right) {
        if left.Favorite != right.Favorite
            return left.Favorite
        if left.Uses != right.Uses
            return left.Uses > right.Uses
        return StrCompare(StrLower(left.Name), StrLower(right.Name)) < 0
    }

    static FirstAutotext(triggers) {
        for trigger in triggers
            if trigger.Kind = "Autotext" && trigger.Enabled
                return trigger.Value
        return ""
    }

    static StringField(record, name) {
        return HasProp(record, name) && record.%name% != "" ? String(record.%name%) : ""
    }

    static NewId() => A_NowUTC "-" Format("{:012}", A_TickCount) "-" Random(100000, 999999)
}
