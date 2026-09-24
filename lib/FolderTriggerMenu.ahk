#Requires AutoHotkey v2.0
#Include FolderTree.ahk

class FolderTriggerMenu {
    __New(phrases, folders) {
        this.Tree := FolderTree(phrases, folders)
        this.CurrentFolderId := ""
        this.TargetHwnd := 0
        this.QueryText := ""
        this.Results := []
        this.SelectedIndex := 0
    }

    Open(folderId, targetHwnd := 0) {
        if folderId && !this.Tree.FindFolder(folderId)
            throw Error("Folder does not exist: " folderId)
        this.CurrentFolderId := folderId
        this.TargetHwnd := targetHwnd
        this.QueryText := ""
        this.SelectedIndex := 1
        return this.Search("")
    }

    Search(query) {
        this.QueryText := String(query)
        this.Results := []
        for child in this.Tree.Children(this.CurrentFolderId) {
            item := child.Item
            if query && !InStr(StrLower(item.Name), StrLower(query))
                continue
            this.Results.Push({Type: child.Type, Item: item})
        }
        this.SelectedIndex := this.Results.Length ? 1 : 0
        return this.Results
    }

    Select(itemId) {
        for result in this.Results {
            if result.Item.Id != itemId
                continue
            if result.Type = "Folder" {
                this.Open(result.Item.Id, this.TargetHwnd)
                return result
            }
            return result
        }
        throw Error("Menu item is not in the current folder: " itemId)
    }

    MoveUp() {
        if this.CurrentFolderId {
            folder := this.Tree.FindFolder(this.CurrentFolderId)
            if folder.ParentId {
                this.Open(folder.ParentId, this.TargetHwnd)
                return {Type: "Folder", Item: this.Tree.FindFolder(this.CurrentFolderId)}
            }
        }
        this.SelectedIndex := 0
        return {Type: "CreatePhrase", FolderId: this.CurrentFolderId}
    }
}
