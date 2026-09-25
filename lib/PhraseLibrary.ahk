#Requires AutoHotkey v2.0
#Include PhraseModel.ahk
#Include Storage.ahk

class PhraseLibrary {
    static Load(store) {
        phrases := []
        folders := []
        path := store.Dir "\phrases.dat"
        if !FileExist(path)
            return {Phrases: phrases, Folders: folders}
        text := store.Read("phrases.dat")
        lines := StrSplit(text, "`n")
        header := lines.Length ? RTrim(lines[1], "`r") : ""
        if header = "PB3" || header = "PB4"
            return this.LoadVersioned(lines, header)
        for line in lines {
            line := RTrim(line, "`r")
            if line = ""
                continue
            fields := StrSplit(line, "`t")
            if fields.Length < 4 || fields.Length > 8
                throw Error("Invalid legacy phrase record.")
            phrase := PhraseModel.NormalizePhrase({
                Id: fields[1], Name: SecureStore.Decode(fields[2], true),
                Abbr: SecureStore.Decode(fields[3], true), Text: SecureStore.Decode(fields[4], true),
                Tags: fields.Length >= 5 ? SecureStore.Decode(fields[5], true) : "",
                Favorite: fields.Length >= 6 && fields[6] = "1",
                Uses: fields.Length >= 7 && fields[7] != "" ? Integer(fields[7]) : 0,
                Apps: fields.Length >= 8 ? SecureStore.Decode(fields[8], true) : "",
                FolderId: ""
            })
            if !phrase.Id || !phrase.Name || !phrase.Text
                throw Error("Legacy phrase is missing its ID, name, or text.")
            this.AssertUnique(phrases, phrase.Id, "phrase")
            phrases.Push(phrase)
        }
        return {Phrases: phrases, Folders: folders}
    }

    static LoadVersioned(lines, version) {
        phrases := []
        folders := []
        triggers := []
        options := []
        ids := Map()
        for index, line in lines {
            if index = 1
                continue
            line := RTrim(line, "`r")
            if line = ""
                continue
            fields := StrSplit(line, "`t")
            tag := fields[1]
            counts := Map("P", version = "PB4" ? 10 : 9, "F", 5, "T", 8, "O", 5)
            if !counts.Has(tag) || fields.Length != counts[tag]
                throw Error("Invalid " version " " tag " record column count.")
            decoded := [tag]
            Loop fields.Length - 1
                decoded.Push(SecureStore.Decode(fields[A_Index + 1], true))
            if tag = "P" {
                p := PhraseModel.NormalizePhrase({Id: decoded[2], Name: decoded[3], Text: decoded[4],
                    Tags: decoded[5], Favorite: this.ParseBit(decoded[6]), Uses: this.ParseInteger(decoded[7]),
                    Apps: decoded[8], FolderId: decoded[9],
                    AiPhrase: version = "PB4" ? this.ParseBit(decoded[10]) : false, Triggers: []})
                this.RegisterId(ids, p.Id, "phrase")
                phrases.Push(p)
            } else if tag = "F" {
                f := PhraseModel.NormalizeFolder({Id: decoded[2], ParentId: decoded[3],
                    Name: decoded[4], CreatedAt: decoded[5], Triggers: [], TriggerDefaults: Map()})
                if !f.Id || !f.Name
                    throw Error("PB3 folder is missing its ID or name.")
                this.RegisterId(ids, f.Id, "folder")
                folders.Push(f)
            } else if tag = "T" {
                ownerType := decoded[3]
                if ownerType != "phrase" && ownerType != "folder"
                    throw Error("Invalid PB3 trigger owner type.")
                trigger := PhraseModel.NormalizeTrigger({Id: decoded[2], Kind: decoded[5], Value: decoded[6],
                    Mode: decoded[7], Enabled: this.ParseBit(decoded[8]), Options: Map()})
                this.RegisterId(ids, trigger.Id, "trigger")
                triggers.Push({OwnerType: ownerType, OwnerId: decoded[4], Trigger: trigger})
            } else {
                ownerType := decoded[2]
                if ownerType != "trigger" && ownerType != "folder"
                    throw Error("Invalid PB3 option owner type.")
                options.Push({OwnerType: ownerType, OwnerId: decoded[3], Key: decoded[4], Value: decoded[5]})
            }
        }
        for phrase in phrases {
            if !phrase.Id || !phrase.Name || !phrase.Text
                throw Error("PB3 phrase is missing its ID, name, or text.")
            if phrase.FolderId && !this.FindById(folders, phrase.FolderId)
                throw Error("PB3 phrase refers to a missing folder.")
        }
        for folder in folders {
            if folder.ParentId && !this.FindById(folders, folder.ParentId)
                throw Error("PB3 folder refers to a missing parent.")
        }
        this.ValidateFolderTree(folders)
        for entry in triggers {
            owner := this.FindById(entry.OwnerType = "phrase" ? phrases : folders, entry.OwnerId)
            if !owner
                throw Error("PB3 trigger refers to a missing owner.")
            owner.Triggers.Push(entry.Trigger)
        }
        for option in options {
            owner := option.OwnerType = "trigger" ? this.FindById(triggers, option.OwnerId, "Trigger")
                : this.FindById(folders, option.OwnerId)
            if !owner || !option.Key
                throw Error("PB3 option refers to a missing owner or key.")
            (option.OwnerType = "trigger" ? owner.Options : owner.TriggerDefaults)[option.Key] := option.Value
        }
        for phrase in phrases {
            phrase.Abbr := this.FirstAutotext(phrase.Triggers)
        }
        return {Phrases: phrases, Folders: folders}
    }

    static Save(store, phrases, folders) {
        normalizedPhrases := []
        normalizedFolders := []
        ids := Map()
        for raw in phrases {
            p := PhraseModel.NormalizePhrase(raw)
            if !p.Id || !p.Name || !p.Text
                throw Error("Phrase needs an ID, name, and text before saving.")
            if p.FolderId && !this.FindById(folders, p.FolderId)
                throw Error("Phrase refers to a missing folder.")
            PhraseModel.ValidatePhrase(p)
            this.RegisterId(ids, p.Id, "phrase")
            p.Triggers := this.NormalizeTriggers(p.Triggers, ids)
            p.Abbr := this.FirstAutotext(p.Triggers)
            normalizedPhrases.Push(p)
        }
        for raw in folders {
            f := PhraseModel.NormalizeFolder(raw)
            if !f.Id || !f.Name
                throw Error("Folder needs an ID and name before saving.")
            if f.ParentId && !this.FindById(folders, f.ParentId)
                throw Error("Folder refers to a missing parent.")
            this.RegisterId(ids, f.Id, "folder")
            f.Triggers := this.NormalizeTriggers(f.Triggers, ids)
            normalizedFolders.Push(f)
        }
        this.ValidateFolderTree(normalizedFolders)
        output := "PB4`n"
        for p in normalizedPhrases {
            output .= this.Row("P", [p.Id, p.Name, p.Text, p.Tags, p.Favorite ? "1" : "0",
                p.Uses, p.Apps, p.FolderId, p.AiPhrase ? "1" : "0"])
        }
        for f in normalizedFolders
            output .= this.Row("F", [f.Id, f.ParentId, f.Name, f.CreatedAt])
        for f in normalizedFolders
            output .= this.WriteTriggers("folder", f.Id, f.Triggers)
        for p in normalizedPhrases
            output .= this.WriteTriggers("phrase", p.Id, p.Triggers)
        for f in normalizedFolders
            output .= this.WriteOptions("folder", f.Id, f.TriggerDefaults)
        store.Write("phrases.dat", output)
    }

    static NormalizeTriggers(triggers, ids) {
        result := []
        for raw in triggers {
            trigger := PhraseModel.NormalizeTrigger(raw)
            this.RegisterId(ids, trigger.Id, "trigger")
            result.Push(trigger)
        }
        return result
    }
    static WriteTriggers(ownerType, ownerId, triggers) {
        output := ""
        for trigger in triggers {
            output .= this.Row("T", [trigger.Id, ownerType, ownerId, trigger.Kind,
                trigger.Value, trigger.Mode, trigger.Enabled ? "1" : "0"])
            output .= this.WriteOptions("trigger", trigger.Id, trigger.Options)
        }
        return output
    }
    static WriteOptions(ownerType, ownerId, values) {
        output := ""
        if values is Map {
            for key, value in values
                output .= this.Row("O", [ownerType, ownerId, key, String(value)])
        } else {
            for key, value in values.OwnProps()
                output .= this.Row("O", [ownerType, ownerId, key, String(value)])
        }
        return output
    }
    static Row(tag, cells) {
        line := tag
        for value in cells
            line .= "`t" SecureStore.Encode(String(value))
        return line "`n"
    }
    static FirstAutotext(triggers) {
        for trigger in triggers
            if trigger.Kind = "Autotext" && trigger.Enabled
                return trigger.Value
        return ""
    }
    static ParseBit(value) {
        if value != "0" && value != "1"
            throw Error("Invalid PB3 boolean value.")
        return value = "1"
    }
    static ParseInteger(value) {
        if !RegExMatch(value, "^\d+$")
            throw Error("Invalid PB3 integer value.")
        return Integer(value)
    }
    static FindById(records, id, property := "") {
        for record in records {
            candidate := property ? record.%property%.Id : record.Id
            if candidate = id
                return property ? record.%property% : record
        }
        return 0
    }
    static RegisterId(ids, id, kind) {
        if !id || ids.Has(id)
            throw Error("Missing or duplicate " kind " ID: " id)
        ids[id] := kind
    }
    static ValidateFolderTree(folders) {
        for origin in folders {
            seen := Map()
            current := origin
            while current.ParentId {
                if seen.Has(current.Id)
                    throw Error("Folder hierarchy contains a cycle.")
                seen[current.Id] := true
                current := this.FindById(folders, current.ParentId)
                if !current
                    throw Error("Folder hierarchy refers to a missing parent.")
            }
        }
    }
    static ExportCsv(phrases) {
        output := "Name,Abbreviation,Text,Tags,Favorite,AllowedApps`r`n"
        for p in phrases
            output .= this.CsvField(p.Name) "," this.CsvField(p.Abbr) "," this.CsvField(p.Text)
                . "," this.CsvField(p.Tags) "," (p.Favorite ? "true" : "false") ","
                . this.CsvField(p.Apps) "`r`n"
        return output
    }
    static CsvField(value) => Chr(34) StrReplace(value, Chr(34), Chr(34) Chr(34)) Chr(34)
    static AssertUnique(records, id, kind) {
        for record in records
            if record.Id = id
                throw Error("Duplicate " kind " ID: " id)
    }
}
