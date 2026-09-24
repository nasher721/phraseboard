#Requires AutoHotkey v2.0

class FolderTree {
    __New(phrases, folders) {
        this.Phrases := phrases
        this.Folders := folders
    }
    Children(parentId) {
        items := []
        for folder in this.Folders
            if folder.ParentId = parentId
                items.Push({Type: "Folder", Item: folder})
        for phrase in this.Phrases
            if phrase.FolderId = parentId
                items.Push({Type: "Phrase", Item: phrase})
        return items
    }
    Path(folderId) {
        parts := []
        seen := Map()
        while folderId {
            if seen.Has(folderId)
                throw Error("Folder hierarchy contains a cycle.")
            seen[folderId] := true
            folder := this.FindFolder(folderId)
            if !folder
                throw Error("Folder does not exist: " folderId)
            parts.InsertAt(1, folder.Name)
            folderId := folder.ParentId
        }
        return FolderTree.Join(parts, "\")
    }
    Move(itemId, parentId) {
        if parentId && !this.FindFolder(parentId)
            throw Error("Destination folder does not exist.")
        folder := this.FindFolder(itemId)
        if folder {
            if itemId = parentId || (parentId && this.IsDescendant(parentId, itemId))
                throw Error("A folder cannot be moved into itself or its descendant.")
            folder.ParentId := parentId
            return folder
        }
        phrase := this.FindPhrase(itemId)
        if !phrase
            throw Error("Phrase or folder does not exist: " itemId)
        phrase.FolderId := parentId
        return phrase
    }
    Delete(folderId, reparentTo) {
        folder := this.FindFolder(folderId)
        if !folder
            throw Error("Folder does not exist: " folderId)
        if reparentTo = "" && folder.ParentId != ""
            reparentTo := folder.ParentId
        if reparentTo && !this.FindFolder(reparentTo)
            throw Error("Reparent destination does not exist.")
        if reparentTo = folderId || (reparentTo && this.IsDescendant(reparentTo, folderId))
            throw Error("Cannot reparent a folder into itself or its descendant.")
        for child in this.Folders
            if child.ParentId = folderId
                child.ParentId := reparentTo
        for phrase in this.Phrases
            if phrase.FolderId = folderId
                phrase.FolderId := reparentTo
        for index, candidate in this.Folders
            if candidate.Id = folderId {
                this.Folders.RemoveAt(index)
                return folder
            }
    }
    EffectiveDefaults(folderId) {
        defaults := Map()
        chain := []
        seen := Map()
        while folderId {
            if seen.Has(folderId)
                throw Error("Folder hierarchy contains a cycle.")
            seen[folderId] := true
            folder := this.FindFolder(folderId)
            if !folder
                throw Error("Folder does not exist: " folderId)
            chain.Push(folder)
            folderId := folder.ParentId
        }
        index := chain.Length
        while index {
            folder := chain[index]
            for key, value in folder.TriggerDefaults
                defaults[key] := value
            index -= 1
        }
        return defaults
    }
    FindFolder(id) {
        for folder in this.Folders
            if folder.Id = id
                return folder
        return 0
    }
    FindPhrase(id) {
        for phrase in this.Phrases
            if phrase.Id = id
                return phrase
        return 0
    }
    IsDescendant(folderId, ancestorId) {
        seen := Map()
        while folderId {
            if folderId = ancestorId
                return true
            if seen.Has(folderId)
                throw Error("Folder hierarchy contains a cycle.")
            seen[folderId] := true
            folder := this.FindFolder(folderId)
            if !folder
                return false
            folderId := folder.ParentId
        }
        return false
    }
    static Join(items, separator) {
        result := ""
        for index, item in items
            result .= (index = 1 ? "" : separator) item
        return result
    }
}
