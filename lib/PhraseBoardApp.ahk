#Requires AutoHotkey v2.0
#Include PhraseLibrary.ahk
#Include FolderTree.ahk
#Include TriggerEngine.ahk
#Include SmartComplete.ahk
#Include FolderTriggerMenu.ahk
#Include MacroParser.ahk
#Include MacroForms.ahk
#Include MacroEngine.ahk
#Include HotkeyAdapter.ahk
#Include AiSettings.ahk
#Include AiService.ahk
#Include AiWorkflows.ahk
#Include RichText.ahk

class PhraseBoardApp {
    MaxEntries := 100
    MaxBytes := 32 * 1024 * 1024
    SmartCompleteMinChars := 3
    Theme := "Light"
    FontSize := 10
    Density := "Comfortable"
    HistorySort := "Newest first"
    PhraseSort := "Most used"
    MaxClipBytes := 2 * 1024 * 1024
    RetentionDays := 0
    ExcludedApps := ""
    CaptureNonText := false
    KeepOpenAfterPaste := false
    SkipLikelySecrets := false
    History := []
    Phrases := []
    Folders := []
    CurrentFolderId := ""
    ShowAllFolders := true
    FolderChoiceIds := []
    Bindings := []
    HistoryRows := []
    PhraseRows := []
    InternalSequence := -1
    Target := 0
    Paused := false
    Expansions := true
    Visible := false
    Pasting := false
    ExcludeNextCapture := false
    LastError := ""
    TypedWindow := 0
    TypedBuffer := ""
    LastInputTick := 0
    LastInputGap := 0
    PendingTrigger := 0
    PendingTimer := 0
    TypingHook := 0
    MonitoringStopped := false
    SmartPopupGui := 0
    SmartPopupList := 0
    AiKey := ""
    ExpansionAborted := false
    ExpansionError := ""
    AiUndoArmed := false
    ApplyingAi := false
    AiUndoHotkeyOn := false
    AiEditorHwnd := 0

    __New(directory, capture := true) {
        RichText.Init()
        this.SmartCompleter := SmartComplete()
        this.TypingRate := TriggerEngine.TypingRate()
        this.Store := SecureStore(directory)
        this.Load()
        this.BuildGui()
        this.HotstringContext := ObjBindMethod(this, "CanExpand")
        this.FolderHotkeyContext := ObjBindMethod(this, "CanTriggerHotkey")
        this.TriggerEngine := TriggerEngine(this)
        this.RegisterPhrases()
        this.ClipCallback := ObjBindMethod(this, "ClipboardChanged")
        this.CaptureCallback := ObjBindMethod(this, "Capture")
        this.CaptureEnabled := capture
        if capture
            OnClipboardChange(this.ClipCallback)
    }
    NewId() => A_NowUTC "-" Format("{:012}", A_TickCount) "-" Random(100000, 999999)
    Seq() => DllCall("GetClipboardSequenceNumber", "UInt")
    Notify(message) {
        this.Status.Text := message
        this.LastError := message
    }
    Load() {
        if FileExist(this.Store.Dir "\preferences.dat") {
            try {
                prefs := StrSplit(this.Store.Read("preferences.dat"), "|")
                this.Paused := prefs[1] = "1"
                this.Expansions := prefs[2] = "1"
                this.RetentionDays := prefs.Length >= 3 ? Integer(prefs[3]) : 0
                this.ExcludedApps := prefs.Length >= 4 ? SecureStore.Decode(prefs[4], true) : ""
                this.CaptureNonText := prefs.Length >= 5 && prefs[5] = "1"
                this.KeepOpenAfterPaste := prefs.Length >= 6 && prefs[6] = "1"
                this.SkipLikelySecrets := prefs.Length >= 7 && prefs[7] = "1"
                this.Theme := prefs.Length >= 8 && prefs[8] = "Dark" ? "Dark" : "Light"
                this.FontSize := prefs.Length >= 9 && RegExMatch(prefs[9], "^\d+$")
                    ? Max(9, Min(14, Integer(prefs[9]))) : 10
                this.Density := prefs.Length >= 10 && prefs[10] = "Compact" ? "Compact" : "Comfortable"
                this.HistorySort := prefs.Length >= 11 && prefs[11] = "Oldest first" ? "Oldest first" : "Newest first"
                this.PhraseSort := prefs.Length >= 12 && prefs[12] = "A to Z" ? "A to Z"
                    : prefs.Length >= 12 && prefs[12] = "Favorites first" ? "Favorites first" : "Most used"
                this.MaxEntries := prefs.Length >= 13 && RegExMatch(prefs[13], "^\d+$")
                    ? Max(20, Min(1000, Integer(prefs[13]))) : 100
                this.MaxBytes := (prefs.Length >= 14 && RegExMatch(prefs[14], "^\d+$")
                    ? Max(8, Min(512, Integer(prefs[14]))) : 32) * 1024 * 1024
                this.SmartCompleteMinChars := prefs.Length >= 15 && RegExMatch(prefs[15], "^\d+$")
                    ? Max(1, Min(32, Integer(prefs[15]))) : 3
                this.AiSettings := AiSettings.Normalize({
                    Provider: prefs.Length >= 16 ? prefs[16] : "",
                    Endpoint: prefs.Length >= 17 ? SecureStore.Decode(prefs[17], true) : "",
                    Model: prefs.Length >= 18 ? SecureStore.Decode(prefs[18], true) : "",
                    Temperature: prefs.Length >= 19 ? prefs[19] : "",
                    MaxTokens: prefs.Length >= 20 ? prefs[20] : "",
                    TimeoutSec: prefs.Length >= 21 ? prefs[21] : ""
                })
            } catch {
                this.LastError := "Saved preferences could not be read. Defaults are in use."
            }
        }
        if !HasProp(this, "AiSettings")
            this.AiSettings := AiSettings.Default()
        if FileExist(this.Store.Dir "\ai-secrets.dat") {
            try this.AiKey := this.Store.Read("ai-secrets.dat")
            catch
                this.AiKey := ""
        }
        files := ""
        Loop Files this.Store.Dir "\*.clip"
            files .= A_LoopFileName "`n"
        for name in StrSplit(Sort(files, "R"), "`n") {
            if !name
                continue
            try {
                fields := StrSplit(this.Store.Read(name), "`n")
                if (fields[1] = "PB1" && fields.Length != 5) || (fields[1] = "PB2" && fields.Length != 6)
                    throw Error("Invalid clip record")
                if fields[1] != "PB1" && fields[1] != "PB2"
                    throw Error("Invalid clip record")
                kind := fields[1] = "PB2" ? fields[4] : "text"
                textIndex := fields[1] = "PB2" ? 5 : 4
                dataIndex := fields[1] = "PB2" ? 6 : 5
                clip := SecureStore.Decode(fields[dataIndex])
                if clip.Size > this.MaxClipBytes
                    throw Error("Clip too large")
                this.History.Push({Id: SubStr(name, 1, -5), Time: fields[2],
                    Pinned: fields[3] = "1", Kind: kind,
                    Text: SecureStore.Decode(fields[textIndex], true), Data: ClipboardAll(clip)})
            } catch {
                this.LastError := "Some saved history could not be read. Original files were left intact."
            }
        }
        try {
            library := PhraseLibrary.Load(this.Store)
            this.Phrases := library.Phrases
            this.Folders := library.Folders
        } catch as err {
            throw Error("Saved phrases could not be loaded. They have not been overwritten.", -1, err.Message)
        }
        this.ApplyRetention()
        this.TrimHistory()
    }
    SaveClip(item) {
        this.Store.Write(item.Id ".clip", "PB2`n" item.Time "`n" (item.Pinned ? 1 : 0)
            "`n" item.Kind "`n" SecureStore.Encode(item.Text) "`n" SecureStore.Encode(item.Data))
    }
    SavePhrases() {
        PhraseLibrary.Save(this.Store, this.Phrases, this.Folders)
    }
    TrimHistory() {
        total := 0
        for item in this.History
            total += item.Data.Size
        while this.History.Length > this.MaxEntries || total > this.MaxBytes {
            index := this.History.Length
            while index && this.History[index].Pinned
                index -= 1
            if !index
                break
            item := this.History[index]
            this.Store.Delete(item.Id ".clip")
            total -= item.Data.Size
            this.History.RemoveAt(index)
        }
    }
    ClipboardChanged(kind) {
        this.ExcludeNextCapture := this.IsExcludedApp()
        if (kind = 1 || this.CaptureNonText) && !this.Paused && this.Seq() != this.InternalSequence
            SetTimer(this.CaptureCallback, -100)
    }
    Capture(*) {
        if this.Paused || this.Seq() = this.InternalSequence
            return
        if this.ExcludeNextCapture
            return
        ; Respect the exclusion marker used by password managers.
        excluded := DllCall("RegisterClipboardFormat", "Str", "ExcludeClipboardContentFromMonitorProcessing", "UInt")
        if DllCall("IsClipboardFormatAvailable", "UInt", excluded)
            return
        try {
            before := this.Seq()
            text := A_Clipboard
            isFile := DllCall("IsClipboardFormatAvailable", "UInt", 15)
            isImage := !text && (DllCall("IsClipboardFormatAvailable", "UInt", 8)
                || DllCall("IsClipboardFormatAvailable", "UInt", 2)
                || DllCall("IsClipboardFormatAvailable", "UInt", 17))
            if !text && !(this.CaptureNonText && (isFile || isImage))
                return
            if StrLen(text) > 200000
                return
            if this.SkipLikelySecrets && this.LooksLikeSecret(text)
                return
            kind := isFile ? "files" : (isImage ? "image" : "text")
            if kind = "files"
                text := "File selection"
            else if kind = "image"
                text := "Image clipboard item"
            data := ClipboardAll()
            if before != this.Seq()
                return
            if data.Size > this.MaxClipBytes {
                this.Notify("This copy is larger than 2 MB and was not added to history.")
                return
            }
            this.AddClip(text, data, kind)
        } catch {
            this.Notify("Could not save this clipboard copy. Other saved items are still available.")
        }
    }
    AddClip(text, data, kind := "text") {
        for index, recent in this.History {
            if recent.Kind = kind && recent.Text = text && recent.Data.Size = data.Size
                && DllCall("msvcrt\memcmp", "Ptr", recent.Data, "Ptr", data, "UPtr", data.Size, "Int") = 0 {
                if index > 1 {
                    this.History.RemoveAt(index)
                    recent.Time := A_NowUTC
                    this.SaveClip(recent)
                    this.History.InsertAt(1, recent)
                    if this.Visible
                        this.RefreshHistory()
                }
                return recent
            }
        }
        item := {Id: this.NewId(), Time: A_NowUTC, Pinned: false, Kind: kind, Text: text, Data: data}
        this.SaveClip(item)
        this.History.InsertAt(1, item)
        this.TrimHistory()
        if this.Visible
            this.RefreshHistory()
        return item
    }
    RegisterShortcuts() {
        Hotkey("^+v", (*) => this.Show(1))
        Hotkey("!+v", (*) => this.PasteCurrentPlain())
        Hotkey("^!Space", (*) => this.Show(2))
        Hotkey("^!+h", (*) => this.TogglePause())
        HotIfWinActive("ahk_id " this.Window.Hwnd)
        Hotkey("^Enter", (*) => this.QuickPaste(true))
        Hotkey("Enter", (*) => this.QuickPaste(false))
        Hotkey("Down", (*) => this.MoveSelection(1))
        Hotkey("Up", (*) => this.MoveSelection(-1))
        Hotkey("^p", (*) => this.ToggleCurrentFavoriteOrPin())
        Hotkey("Delete", (*) => this.DeleteCurrentItem())
        HotIfWinActive()
        HotIf(ObjBindMethod(this, "SmartCompleteHotIf"))
        Hotkey("Up", (*) => this.MoveSmartCompleteSelection(-1))
        Hotkey("Down", (*) => this.MoveSmartCompleteSelection(1))
        Hotkey("Enter", (*) => this.AcceptSmartComplete())
        Hotkey("Escape", (*) => this.DismissSmartComplete("Escape"))
        HotIf()
        HotIf(ObjBindMethod(this, "FolderMenuHotIf"))
        Hotkey("Up", (*) => this.FolderMenuMove(-1))
        Hotkey("Down", (*) => this.FolderMenuMove(1))
        Hotkey("Enter", (*) => this.SelectFolderMenuRow())
        Hotkey("Escape", (*) => this.CloseFolderMenu())
        HotIf()
    }
    CanExpand(*) {
        if !this.Expansions || this.IsExcludedApp()
            return false
        return !this.IsInternalWindow(WinExist("A"))
    }
    CanSuggest(target := 0) {
        if !target
            target := WinExist("A")
        if !target || this.IsInternalWindow(target) || this.IsExcludedApp()
            return false
        return true
    }
    IsInternalWindow(target) {
        if !target
            return false
        for property in ["Window", "Editor", "FolderPopup", "SmartPopupGui"]
            if HasProp(this, property) && IsObject(this.%property%) {
                try {
                    if target = this.%property%.Hwnd
                        return true
                }
            }
        return false
    }
    CanTriggerHotkey(*) {
        target := WinExist("A")
        if !target || this.IsInternalWindow(target) || this.IsExcludedApp()
            return false
        return true
    }
    OpenFolderTrigger(key, *) {
        target := WinExist("A")
        candidates := TriggerEngine.FolderCandidates(key, this.Folders)
        if !candidates.Length
            return
        if candidates.Length = 1 {
            this.ShowFolderMenu(candidates[1].FolderId, target)
            return
        }
        choices := Menu()
        for candidate in candidates {
            folder := this.GetFolderTree().FindFolder(candidate.FolderId)
            choices.Add(this.FolderPathLabel(folder.Id),
                ObjBindMethod(this, "ShowFolderMenu", folder.Id, target))
        }
        choices.Show()
    }
    ShowFolderMenu(folderId, targetHwnd, *) {
        this.CloseFolderMenu()
        this.FolderMenuState := FolderTriggerMenu(this.Phrases, this.Folders)
        this.FolderMenuState.Open(folderId, targetHwnd)
        gui := this.FolderPopup := Gui("+Owner" this.Window.Hwnd " +ToolWindow", "PhraseBoard — " this.FolderPathLabel(folderId))
        gui.SetFont("s10", "Segoe UI")
        gui.AddText("xm", "Search this folder")
        this.FolderPopupSearch := gui.AddEdit("xm w390")
        this.FolderPopupSearch.OnEvent("Change", (*) => this.RefreshFolderMenu())
        this.FolderPopupList := gui.AddListView("xm w390 r9 -Multi -Hdr", ["Folder items"])
        this.FolderPopupList.OnEvent("DoubleClick", (ctrl, row) => this.SelectFolderMenuRow(row))
        gui.OnEvent("Close", (*) => this.CloseFolderMenu())
        gui.Show("w420")
        this.RefreshFolderMenu()
        this.FolderPopupSearch.Focus()
    }
    FolderMenuHotIf(*) => HasProp(this, "FolderPopup") && IsObject(this.FolderPopup)
        && WinActive("ahk_id " this.FolderPopup.Hwnd)
    RefreshFolderMenu(*) {
        if !HasProp(this, "FolderPopupList") || !IsObject(this.FolderPopupList)
            return
        this.FolderMenuRows := this.FolderMenuState.Search(this.FolderPopupSearch.Value)
        this.FolderPopupList.Delete()
        for row in this.FolderMenuRows
            this.FolderPopupList.Add("", row.Item.Name (row.Type = "Folder" ? "  ›" : ""))
        createRow := {Type: "CreatePhrase", FolderId: this.FolderMenuState.CurrentFolderId}
        this.FolderMenuRows.Push(createRow)
        this.FolderPopupList.Add("", "＋ Create new snippet here")
        if this.FolderMenuRows.Length
            this.FolderPopupList.Modify(1, "Select Vis")
    }
    FolderMenuMove(delta) {
        if !HasProp(this, "FolderPopupList") || !IsObject(this.FolderPopupList)
            return
        count := this.FolderMenuRows.Length
        selected := this.FolderPopupList.GetNext()
        if !selected
            selected := 1
        if delta < 0 && selected = 1 {
            folder := this.GetFolderTree().FindFolder(this.FolderMenuState.CurrentFolderId)
            if IsObject(folder) && folder.ParentId {
                this.FolderMenuState.MoveUp()
                this.RefreshFolderMenu()
                return
            }
            selected := count
        } else
            selected := Max(1, Min(count, selected + delta))
        this.FolderPopupList.Modify(selected, "Select Vis")
    }
    SelectFolderMenuRow(row := 0, *) {
        if !row && HasProp(this, "FolderPopupList")
            row := this.FolderPopupList.GetNext()
        if !row || row > this.FolderMenuRows.Length
            return
        selected := this.FolderMenuRows[row]
        if selected.Type = "CreatePhrase" {
            folderId := selected.FolderId
            this.CloseFolderMenu()
            this.EditPhrase(0, "", folderId)
        } else if selected.Type = "Folder" {
            this.FolderMenuState.Select(selected.Item.Id)
            this.FolderPopup.Title := "PhraseBoard — " this.FolderPathLabel(this.FolderMenuState.CurrentFolderId)
            this.RefreshFolderMenu()
        } else {
            target := this.FolderMenuState.TargetHwnd
            phraseId := selected.Item.Id
            this.CloseFolderMenu()
            this.InsertPhrase(phraseId, target)
        }
    }
    CloseFolderMenu(*) {
        if HasProp(this, "FolderPopup") && IsObject(this.FolderPopup) {
            try this.FolderPopup.Destroy()
            this.FolderPopup := 0
            this.FolderPopupList := 0
            this.FolderPopupSearch := 0
            this.FolderMenuRows := []
        }
    }
    EnsureTypingMonitor() {
        needed := false
        for phrase in this.Phrases
            for trigger in phrase.Triggers
                if trigger.Enabled && (trigger.Kind = "Autotext" || trigger.Kind = "SmartComplete")
                    needed := true
        if !needed {
            if HasProp(this, "TypingHook") {
                this.MonitoringStopped := true
                this.TypingHook.Stop()
                this.TypingHook := 0
            }
            return
        }
        if HasProp(this, "TypingHook") && IsObject(this.TypingHook) && this.TypingHook.InProgress
            return
        this.MonitoringStopped := false
        hook := this.TypingHook := InputHook("I1 L1023")
        hook.VisibleText := true
        hook.VisibleNonText := true
        hook.KeyOpt("{All}", "N")
        hook.OnChar := ObjBindMethod(this, "TypedCharacter")
        hook.OnKeyDown := ObjBindMethod(this, "TypedKeyDown")
        hook.OnEnd := ObjBindMethod(this, "TypingMonitorEnded")
        hook.Start()
    }
    TypingMonitorEnded(hook) {
        if !this.MonitoringStopped && IsObject(this.TypingHook) && hook = this.TypingHook {
            this.TypingHook := 0
            SetTimer(ObjBindMethod(this, "EnsureTypingMonitor"), -10)
        }
    }
    TypedCharacter(hook, character) {
        this.CancelPendingTrigger()
        target := WinExist("A")
        if target != this.TypedWindow {
            this.TypedWindow := target
            this.TypedBuffer := ""
            this.SmartCompleter.ResetBuffer()
            this.DismissSmartComplete("WindowChanged")
        }
        if !this.CanSuggest(target) {
            this.TypedBuffer := ""
            this.SmartCompleter.ResetBuffer()
            this.DismissSmartComplete("ExcludedWindow")
            return
        }
        timestamp := A_TickCount
        if this.LastInputTick
            this.LastInputGap := timestamp - this.LastInputTick
        this.LastInputTick := timestamp
        this.TypingRate.Record(timestamp)
        this.TypedBuffer .= character
        if StrLen(this.TypedBuffer) > 256
            this.TypedBuffer := SubStr(this.TypedBuffer, -255)
        this.SmartCompleter.AppendCharacter(character)
        this.UpdateSmartComplete(target)
    }
    TypedKeyDown(hook, vk, sc) {
        timestamp := A_TickCount
        if this.LastInputTick
            this.LastInputGap := timestamp - this.LastInputTick
        this.LastInputTick := timestamp
        this.TypingRate.Record(timestamp)
        key := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
        this.CancelPendingTrigger()
        if key = "Backspace" {
            if StrLen(this.TypedBuffer)
                this.TypedBuffer := SubStr(this.TypedBuffer, 1, -1)
            this.SmartCompleter.Backspace()
            this.UpdateSmartComplete(WinExist("A"))
        } else if key = "Escape" {
            this.DismissSmartComplete("Escape")
            this.SmartCompleter.ResetBuffer()
            this.TypedBuffer := ""
        } else if key = "Enter" || key = "Tab" {
            if !this.SmartCompleter.Visible {
                this.SmartCompleter.ResetBuffer()
                this.TypedBuffer := ""
            }
        }
    }
    CancelPendingTrigger() {
        if !HasProp(this, "PendingTrigger") || !IsObject(this.PendingTrigger)
            return false
        if HasProp(this, "PendingTimer") && IsObject(this.PendingTimer)
            SetTimer(this.PendingTimer, 0)
        pending := this.PendingTrigger
        this.PendingTrigger := 0
        this.PendingTimer := 0
        SendText(pending.Input pending.EndChar)
        return true
    }
    UpdateSmartComplete(target) {
        if !this.CanSuggest(target) || StrLen(this.SmartCompleter.TypedText) < this.SmartCompleteMinChars {
            this.DismissSmartComplete("NoMatch")
            return
        }
        eligible := []
        for phrase in this.Phrases {
            hasTrigger := false
            for trigger in phrase.Triggers
                if trigger.Enabled && trigger.Kind = "SmartComplete" {
                    hasTrigger := true
                    break
                }
            if hasTrigger && this.PhraseAllowedInTarget(phrase, target)
                eligible.Push(phrase)
        }
        results := SmartComplete.Query(this.SmartCompleter.TypedText, eligible, this.SmartCompleteMinChars)
        if !results.Length {
            this.DismissSmartComplete("NoMatch")
            return
        }
        this.SmartCompleter.Show(target, this.SmartCompleter.TypedText, results)
        this.RefreshSmartCompletePopup()
    }
    RefreshSmartCompletePopup() {
        if !this.SmartCompleter.Visible
            return
        if !HasProp(this, "SmartPopupGui") || !IsObject(this.SmartPopupGui) {
            popup := this.SmartPopupGui := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x08000000", "PhraseBoard suggestions")
            popup.BackColor := "FFFFFF"
            popup.SetFont("s10", "Segoe UI")
            this.SmartPopupList := popup.AddListView("w310 r6 -Hdr -Multi", ["Suggested phrases"])
            this.SmartPopupList.OnEvent("DoubleClick", (*) => this.AcceptSmartComplete())
        }
        this.SmartPopupList.Delete()
        for phrase in this.SmartCompleter.Results
            this.SmartPopupList.Add("", phrase.Name)
        if this.SmartCompleter.SelectedIndex
            this.SmartPopupList.Modify(this.SmartCompleter.SelectedIndex, "Select Vis")
        point := this.CaretScreenPosition(this.SmartCompleter.TargetHwnd)
        this.SmartPopupGui.Show("NA x" point.X " y" point.Y)
    }
    CaretScreenPosition(target) {
        try {
            threadId := DllCall("GetWindowThreadProcessId", "Ptr", target, "Ptr", 0, "UInt")
            info := Buffer(A_PtrSize = 8 ? 72 : 48, 0)
            NumPut("UInt", info.Size, info, 0)
            if DllCall("GetGUIThreadInfo", "UInt", threadId, "Ptr", info, "Int") {
                caretHwnd := NumGet(info, A_PtrSize * 6, "Ptr")
                rectOffset := A_PtrSize * 7
                if caretHwnd {
                    point := Buffer(8, 0)
                    NumPut("Int", NumGet(info, rectOffset, "Int"), point, 0)
                    NumPut("Int", NumGet(info, rectOffset + 4, "Int") + 18, point, 4)
                    if DllCall("ClientToScreen", "Ptr", caretHwnd, "Ptr", point, "Int")
                        return {X: NumGet(point, 0, "Int"), Y: NumGet(point, 4, "Int")}
                }
            }
        }
        try {
            WinGetPos(&x, &y, &width, &height, "ahk_id " target)
            return {X: x + 24, Y: y + Min(height, 120)}
        }
        return {X: 100, Y: 100}
    }
    SmartCompleteHotIf(*) => this.SmartCompleter.Visible
        && this.SmartCompleter.TargetHwnd && WinActive("ahk_id " this.SmartCompleter.TargetHwnd)
    MoveSmartCompleteSelection(delta) {
        if !this.SmartCompleter.Visible
            return
        this.SmartCompleter.MoveSelection(delta)
        this.RefreshSmartCompletePopup()
    }
    AcceptSmartComplete(*) {
        target := this.SmartCompleter.TargetHwnd
        query := this.SmartCompleter.QueryText
        phrase := this.SmartCompleter.Accept()
        if !IsObject(phrase)
            return
        this.DismissSmartComplete("Accepted")
        if target && WinExist("ahk_id " target) {
            WinActivate("ahk_id " target)
            WinWaitActive("ahk_id " target, , 1)
            if query
                SendEvent("{Backspace " StrLen(query) "}")
        }
        this.InsertPhrase(phrase.Id, target)
        this.SmartCompleter.ResetBuffer()
        this.TypedBuffer := ""
    }
    DismissSmartComplete(reason := "Dismissed") {
        if HasProp(this, "SmartCompleter")
            this.SmartCompleter.Dismiss(reason)
        if HasProp(this, "SmartPopupGui") && IsObject(this.SmartPopupGui)
            try this.SmartPopupGui.Hide()
    }
    Stop() {
        if this.CaptureEnabled
            OnClipboardChange(this.ClipCallback, 0)
        SetTimer(this.CaptureCallback, 0)
        this.TriggerEngine.Unregister()
        HotkeyAdapter.UnregisterAll()
        if HasProp(this, "TypingHook")
            try this.TypingHook.Stop()
        this.DismissSmartComplete("Stopped")
        this.Window.Destroy()
    }
    RegisterPhrases() {
        this.TriggerEngine.Register(this.Phrases, this.Folders)
        this.RegisterPhraseHotkeys()
        this.EnsureTypingMonitor()
    }
    RegisterPhraseHotkeys() {
        HotkeyAdapter.UnregisterAll()
        for phrase in this.Phrases {
            for trigger in phrase.Triggers {
                if trigger.Enabled && trigger.Kind = "Hotkey" && Trim(trigger.Value) {
                    phraseId := phrase.Id
                    targetTrigger := trigger
                    HotkeyAdapter.Register(trigger.Value, (*) => this.OnPhraseHotkey(phraseId, targetTrigger))
                }
            }
        }
    }
    OnPhraseHotkey(phraseId, trigger) {
        target := WinExist("A")
        if target = this.Window.Hwnd
            return
        this.InsertPhrase(phraseId, target, "Exact", "", "", trigger)
    }
    ExpandTrigger(inputMatch, *) {
        target := WinExist("A")
        endChar := A_EndChar
        typed := this.TypedBuffer
        if endChar && SubStr(typed, -1) == endChar
            typed := SubStr(typed, 1, -1)
        prefix := ""
        if StrLen(typed) >= StrLen(inputMatch)
            && SubStr(typed, -StrLen(inputMatch)) == inputMatch
            prefix := SubStr(typed, 1, StrLen(typed) - StrLen(inputMatch))
        typedText := prefix inputMatch
        candidates := []
        for candidate in TriggerEngine.CandidatesForInput(inputMatch, target, this.Phrases) {
            boundaryTrigger := {Value: inputMatch, Options: candidate.Trigger.Options}
            boundary := TriggerEngine.MatchesBoundary(boundaryTrigger, typedText, prefix, endChar)
            if boundary.Matches
                candidates.Push(candidate)
        }
        if !candidates.Length
        {
            SendText(inputMatch endChar)
            return
        }
        modes := []
        for candidate in candidates {
            phrase := TriggerEngine.FindPhrase(this.Phrases, candidate.PhraseId)
            modes.Push(this.EffectiveTriggerMode(phrase, candidate.Trigger))
        }
        mode := modes[1]
        if candidates.Length = 1 && mode = "AfterPause" {
            threshold := this.TypingRate.Threshold(5, 200)
            this.PendingTrigger := {Candidates: candidates, Target: target, Input: inputMatch,
                EndChar: endChar, Mode: mode}
            this.PendingTimer := ObjBindMethod(this, "FirePendingTrigger")
            SetTimer(this.PendingTimer, -threshold)
            return
        }
        if candidates.Length = 1 && mode = "WhileTypingFast" {
            threshold := this.TypingRate.Threshold(5, 200)
            if this.LastInputGap >= threshold {
                SendText(inputMatch endChar)
                return
            }
        }
        if candidates.Length = 1 && (mode = "Immediate" || mode = "WhileTypingFast") {
            candidate := candidates[1]
            this.InsertPhrase(candidate.PhraseId, target, "Exact", inputMatch, endChar, candidate.Trigger, inputMatch)
            return
        }
        this.ShowTriggerChooser(candidates, target, inputMatch, endChar)
    }
    EffectiveTriggerMode(phrase, trigger) {
        if trigger.Mode
            return this.CanonicalTriggerMode(trigger.Mode)
        if phrase.FolderId {
            defaults := this.GetFolderTree().EffectiveDefaults(phrase.FolderId)
            if defaults.Has("Mode") && defaults["Mode"]
                return this.CanonicalTriggerMode(defaults["Mode"])
        }
        return "Immediate"
    }
    FirePendingTrigger(*) {
        if !HasProp(this, "PendingTrigger") || !IsObject(this.PendingTrigger)
            return
        pending := this.PendingTrigger
        this.PendingTrigger := 0
        this.PendingTimer := 0
        if pending.Candidates.Length = 1 {
            candidate := pending.Candidates[1]
            this.InsertPhrase(candidate.PhraseId, pending.Target, "Exact", pending.Input,
                pending.EndChar, candidate.Trigger, pending.Input)
        } else
            this.ShowTriggerChooser(pending.Candidates, pending.Target, pending.Input, pending.EndChar)
    }
    ShowTriggerChooser(candidates, target, inputMatch, endChar) {
        menu := Menu()
        for candidate in candidates {
            phrase := TriggerEngine.FindPhrase(this.Phrases, candidate.PhraseId)
            menu.Add(phrase.Name, ObjBindMethod(this, "InsertPhrase", phrase.Id, target, "Exact",
                inputMatch, endChar, candidate.Trigger, inputMatch))
        }
        menu.Show()
    }
    InsertPhrase(id, targetHwnd, caseMode := "Exact", triggerValue := "", endChar := "", trigger := 0,
        inputMatch := "", *) {
        if targetHwnd && WinExist("ahk_id " targetHwnd)
            WinActivate("ahk_id " targetHwnd)
        for p in this.Phrases {
            if p.Id = id {
                if !this.PhraseAllowedInTarget(p, targetHwnd) {
                    SendText((triggerValue ? triggerValue : p.Abbr) endChar)
                    return
                }
                expandedSource := IsObject(trigger)
                    ? TriggerEngine.ApplyCase(inputMatch ? inputMatch : triggerValue, p.Text, trigger, this.Phrases)
                    : p.Text
                this.ExpansionAborted := false
                this.ExpansionError := ""
                expanded := this.ResolveTokens(expandedSource, p)
                if expanded = "" {
                    if this.ExpansionAborted {
                        this.ReportExpansionAbort()
                        return
                    }
                    if triggerValue
                        SendText(triggerValue endChar)
                    return
                }
                if targetHwnd && !WinActive("ahk_id " targetHwnd) {
                    this.Notify("Target window changed. Nothing was pasted.")
                    TrayTip("Target window changed. Nothing was pasted.", "PhraseBoard")
                    return
                }
                value := this.ExtractCursor(expanded)
                terminator := TriggerEngine.TerminatorAction(IsObject(trigger) ? trigger : {Options: Map()}, endChar) = "Keep"
                    ? endChar : ""
                if HasProp(p, "Rtf") && p.Rtf != "" {
                    resolvedRtf := RichText.ResolveRichMacros(p.Rtf, (token) => this.ResolveTokens(token, p))
                    richClip := RichText.BuildRichClip(value.Text, resolvedRtf)
                    this.PasteValue(richClip, targetHwnd ? targetHwnd : this.Target, value.Cursor)
                    if terminator
                        SendText(terminator)
                } else {
                    SendText(value.Text)
                    if terminator
                        SendText(endChar)
                    if value.Cursor
                        SendEvent("{Left " (value.Cursor + StrLen(terminator)) "}")
                }
                p.Uses += 1
                try SetTimer(ObjBindMethod(this, "SavePhrases"), -1000)
                return
            }
        }
    }
    ResolveTokens(text, phrase := 0) {
        if !InStr(text, "{{")
            return text
        ctx := MacroEngine.NewContext()
        ctx.ClipboardText := A_Clipboard
        ctx.TargetHwnd := this.Target ? this.Target : WinExist("A")
        ctx.Phrases := this.Phrases
        this.BindAiContext(ctx, IsObject(phrase) && HasProp(phrase, "AiPhrase") && phrase.AiPhrase)
        res := MacroEngine.Render(text, ctx)
        if res.Cancelled {
            this.ExpansionAborted := this.ResultIsAiAbort(res)
            this.ExpansionError := ""
            if this.ExpansionAborted && res.Errors.Length
                this.ExpansionError := res.Errors[1].Message
            return ""
        }
        for act in res.PostActions {
            try act()
        }
        if res.CursorOffset > 0 && StrLen(res.Text) >= res.CursorOffset {
            pos := StrLen(res.Text) - res.CursorOffset + 1
            return SubStr(res.Text, 1, pos - 1) . Chr(1) . SubStr(res.Text, pos)
        }
        return res.Text
    }
    ExtractCursor(text) {
        marker := Chr(1)
        position := InStr(text, marker)
        if !position
            return {Text: text, Cursor: 0}
        after := StrReplace(SubStr(text, position + 1), marker, "")
        before := SubStr(text, 1, position - 1)
        return {Text: before after, Cursor: StrLen(after)}
    }
    BindAiContext(ctx, aiPhrase) {
        ctx.CurrentAiPhrase := !!aiPhrase
        ctx.AiBudget := {Count: 0}
        ctx.AiGenerate := ObjBindMethod(this, "GenerateAi")
    }
    GenerateAi(request) {
        return AiService.Generate(request, this.AiSettings, this.AiKey, WinHttpTransport)
    }
    ResultIsAiAbort(res) {
        return HasProp(res, "AiAborted") && res.AiAborted
    }
    ReportExpansionAbort() {
        message := this.ExpansionError ? this.ExpansionError : "Nothing was pasted."
        this.Notify(message)
        TrayTip(message, "PhraseBoard")
    }
    PreviewTemplate(text, aiPhrase := false) {
        ctx := MacroEngine.NewContext()
        ctx.ClipboardText := A_Clipboard
        ctx.Phrases := this.Phrases
        ctx.FormCollected := true
        this.BindAiContext(ctx, aiPhrase)
        parsed := MacroParser.Parse(text)
        for node in parsed.Nodes {
            if node.Type = "Macro" && (node.Name = "prompt" || node.Name = "form") {
                for p in node.Params {
                    k := p.Key ? p.Key : p.Value
                    if k != "title" && !ctx.FormValues.Has(k)
                        ctx.FormValues[k] := "[" k "]"
                }
            }
        }
        res := MacroEngine.Render(text, ctx)
        previewText := res.Text
        if res.CursorOffset > 0 && StrLen(previewText) >= res.CursorOffset {
            pos := StrLen(previewText) - res.CursorOffset + 1
            previewText := SubStr(previewText, 1, pos - 1) . "|" . SubStr(previewText, pos)
        }
        msg := previewText
        if res.Errors.Length > 0 {
            msg .= "`n`n--- Macro Notes / Warnings ---"
            for err in res.Errors
                msg .= "`n- " err.Message
        }
        MsgBox(msg, "PhraseBoard Macro Preview")
    }
    IsExcludedApp() {
        if !Trim(this.ExcludedApps)
            return false
        try process := StrLower(WinGetProcessName(WinGetID("A")))
        catch
            return false
        for app in StrSplit(StrLower(this.ExcludedApps), ",") {
            app := Trim(app)
            if app = process || app = StrReplace(process, ".exe")
                return true
        }
        return false
    }
    PhraseAllowedInTarget(phrase, target := 0) {
        if !Trim(phrase.Apps)
            return true
        if !target
            target := WinExist("A")
        try process := StrLower(WinGetProcessName(target))
        catch
            return false
        for app in StrSplit(StrLower(phrase.Apps), ",") {
            app := Trim(app)
            if app = process || app = StrReplace(process, ".exe")
                return true
        }
        return false
    }
    ApplyRetention() {
        if this.RetentionDays <= 0
            return
        cutoff := DateAdd(A_NowUTC, -this.RetentionDays, "Days")
        index := this.History.Length
        while index >= 1 {
            item := this.History[index]
            if !item.Pinned && item.Time < cutoff {
                this.Store.Delete(item.Id ".clip")
                this.History.RemoveAt(index)
            }
            index -= 1
        }
    }
    LooksLikeSecret(text) {
        return RegExMatch(text, "i)\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")
            || RegExMatch(text, "\bgh[pousr]_[A-Za-z0-9_]{30,}\b")
            || RegExMatch(text, "\bgithub_pat_[A-Za-z0-9_]{30,}\b")
            || RegExMatch(text, "\bsk-[A-Za-z0-9_-]{20,}\b")
    }
    ValidatePhrase(name, abbr, text, exceptId := "") {
        if !Trim(name) || !text
            throw Error("Enter a phrase name and its text.")
        if StrLen(text) > 100000
            throw Error("Keep each phrase under 100,000 characters.")
        if abbr && !RegExMatch(abbr, "^[a-zA-Z0-9;._/-]{1,40}$")
            throw Error("Use 1-40 letters, numbers, or `; . _ / - for the abbreviation, with no spaces.")
    }
    UpsertPhrase(name, abbr, text, id := "", tags := Chr(1), apps := Chr(1), folderId := "", editedTriggers := 0, aiPhrase := false, rtf := Chr(1)) {
        this.ValidatePhrase(name, abbr, text, id)
        copy := this.Phrases.Clone()
        existing := this.FindPhrase(id)
        triggers := IsObject(editedTriggers) ? editedTriggers
            : (HasProp(existing, "Triggers") ? existing.Triggers.Clone() : [])
        targetFolder := id && HasProp(existing, "FolderId") ? existing.FolderId : folderId
        defaults := targetFolder ? this.GetFolderTree().EffectiveDefaults(targetFolder) : Map()
        inheritedMode := defaults.Has("Mode") ? "" : "Immediate"
        this.SyncLegacyAbbr(triggers, abbr, inheritedMode)
        targetRtf := rtf = Chr(1) ? (id && HasProp(existing, "Rtf") ? existing.Rtf : "") : String(rtf)
        item := {Id: id ? id : this.NewId(), Name: Trim(name),
            Abbr: PhraseModel.FirstAutotext(triggers), Text: text,
            Rtf: targetRtf, Format: targetRtf != "" ? "rich" : "text",
            Tags: tags = Chr(1) ? existing.Tags : Trim(tags),
            Favorite: existing.Favorite, Uses: existing.Uses,
            Apps: apps = Chr(1) ? existing.Apps : Trim(apps),
            FolderId: targetFolder, AiPhrase: !!aiPhrase, Triggers: triggers}
        PhraseModel.ValidatePhrase(item)
        found := false
        for index, p in this.Phrases {
            if p.Id = id {
                this.Phrases[index] := item
                found := true
                break
            }
        }
        if !found
            this.Phrases.Push(item)
        try this.SavePhrases()
        catch as err {
            this.Phrases := copy
            throw err
        }
        this.RegisterPhrases()
        this.RefreshPhrases()
        return item
    }
    SyncLegacyAbbr(triggers, abbr, mode := "Immediate") {
        for index, trigger in triggers {
            if trigger.Kind != "Autotext" || !trigger.Enabled
                continue
            if !abbr
                triggers.RemoveAt(index)
            else
                triggers[index] := {Id: trigger.Id, Kind: "Autotext", Value: abbr,
                    Mode: trigger.Mode, Enabled: trigger.Enabled, Options: trigger.Options}
            return
        }
        if abbr
            triggers.Push(PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: abbr, Mode: mode}))
    }
    FindPhrase(id) {
        for p in this.Phrases
            if p.Id = id
                return p
        return {Tags: "", Favorite: false, Uses: 0, Apps: ""}
    }
    WriteClipboard(value) {
        Critical("On")
        try {
            A_Clipboard := value
            this.InternalSequence := this.Seq()
        } finally Critical("Off")
    }
    PasteValue(value, target, cursorChars := 0) {
        if this.Pasting
            return
        if !target || !WinExist("ahk_id " target) || target = this.Window.Hwnd {
            this.Notify("Open your destination app, then use the PhraseBoard shortcut to paste there.")
            return
        }
        this.Pasting := true
        saved := 0
        writtenSequence := -1
        try {
            this.Window.Hide()
            this.Visible := false
            foreHwnd := DllCall("user32\GetForegroundWindow", "Ptr")
            foreThread := foreHwnd ? DllCall("user32\GetWindowThreadProcessId", "Ptr", foreHwnd, "Ptr", 0, "UInt") : 0
            curThread := DllCall("kernel32\GetCurrentThreadId", "UInt")
            if foreThread && foreThread != curThread
                DllCall("user32\AttachThreadInput", "UInt", curThread, "UInt", foreThread, "Int", 1)
            DllCall("user32\SetForegroundWindow", "Ptr", target)
            DllCall("user32\BringWindowToTop", "Ptr", target)
            WinActivate("ahk_id " target)
            if foreThread && foreThread != curThread
                DllCall("user32\AttachThreadInput", "UInt", curThread, "UInt", foreThread, "Int", 0)
            if !WinWaitActive("ahk_id " target, , 1) {
                if !WinExist("ahk_id " target)
                    throw Error("Could not activate the destination window.")
            }
            for key in ["Ctrl", "Alt", "Shift", "LWin", "RWin"]
                if !KeyWait(key, "T2")
                    throw Error("Release the modifier keys and try pasting again.")
            saved := ClipboardAll()
            this.WriteClipboard(value)
            writtenSequence := this.InternalSequence
            if !ClipWait(1)
                throw Error("The clipboard was unavailable.")
            SendEvent("^v")
            try {
                ctrlHwnd := DllCall("user32\GetFocus", "Ptr")
                if ctrlHwnd && !WinActive("ahk_id " target)
                    SendMessage(0x302, 0, 0, , "ahk_id " ctrlHwnd)
                else {
                    focused := ControlGetFocus("ahk_id " target)
                    if focused && !WinActive("ahk_id " target)
                        SendMessage(0x302, 0, 0, focused, "ahk_id " target)
                }
            }

            if cursorChars {
                Sleep(100)
                SendEvent("{Left " cursorChars "}")
                Sleep(600)
            } else Sleep(700)
        } catch as err {
            this.Notify(err.Message)
            TrayTip(err.Message, "PhraseBoard")
        } finally {
            ; Never overwrite something the user copied while the paste was running.
            if IsObject(saved) && this.Seq() = writtenSequence {
                try this.WriteClipboard(saved)
            }
            this.Pasting := false
            if this.KeepOpenAfterPaste
                this.Show(this.Tab.Value)
        }
    }
    PasteCurrentPlain(target := 0, *) {
        text := A_Clipboard
        if text {
            if !target && this.Target
                target := this.Target
            if !target
                target := WinExist("A")
            if target
                this.PasteValue(text, target)
        }
    }
    PasteHistory(plain := false, *) {
        item := this.SelectedClip()
        if IsObject(item) {
            if plain && item.Kind != "text"
                return
            this.PasteValue(plain ? item.Text : item.Data, this.Target)
        }
    }
    PastePhrase(plain := false, *) {
        p := this.SelectedPhrase()
        if IsObject(p) {
            if !this.PhraseAllowedInTarget(p, this.Target) {
                this.Notify("This phrase is limited to other apps.")
                return
            }
            this.ExpansionAborted := false
            this.ExpansionError := ""
            value := this.ResolveTokens(p.Text, p)
            if value = "" {
                if this.ExpansionAborted
                    this.ReportExpansionAbort()
                return
            }
            value := this.ExtractCursor(value)
            p.Uses += 1
            try this.SavePhrases()
            if !plain && HasProp(p, "Rtf") && p.Rtf != "" {
                resolvedRtf := RichText.ResolveRichMacros(p.Rtf, (token) => this.ResolveTokens(token, p))
                richClip := RichText.BuildRichClip(value.Text, resolvedRtf)
                this.PasteValue(richClip, this.Target, value.Cursor)
            } else {
                this.PasteValue(value.Text, this.Target, value.Cursor)
            }
        }
    }
    PasteQuoted(*) {
        item := this.SelectedClip()
        if IsObject(item)
            this.PasteValue(RegExReplace(item.Text, "(\R)", "$1> "), this.Target)
    }
    PasteSingleLine(*) {
        item := this.SelectedClip()
        if IsObject(item)
            this.PasteValue(RegExReplace(item.Text, "\R+", " "), this.Target)
    }
    BuildGui() {
        g := this.Window := Gui("+Resize +MinSize800x580", "PhraseBoard")
        this.Labels := []
        g.SetFont("s10", "Segoe UI")
        g.BackColor := "F5F7FA"
        this.AddLabel("x20 y15 w570 h25", "PhraseBoard  |  Copy once. Paste it your way.")
        this.KeepOpenCheck := g.AddCheckbox("x610 y15 w170 h25", "Keep picker open")
        this.KeepOpenCheck.Value := this.KeepOpenAfterPaste
        this.KeepOpenCheck.OnEvent("Click", (*) => this.ToggleKeepOpen())
        this.Tab := g.AddTab3("x15 y48 w770 h480", ["Clipboard", "Phrases", "Settings", "Customize"])
        this.Tab.OnEvent("Change", (*) => this.TabChanged())
        this.Tab.UseTab(1)
        this.Search := g.AddEdit("x30 y88 w555 h28")
        DllCall("SendMessage", "Ptr", this.Search.Hwnd, "UInt", 0x1501, "Ptr", 1, "Str", "Search clipboard history")
        this.Search.OnEvent("Change", (*) => this.RefreshHistory())
        this.PauseButton := g.AddButton("x595 y86 w170 h30", this.Paused ? "Resume history" : "Pause history")
        this.PauseButton.OnEvent("Click", (*) => this.TogglePause())
        this.HistoryList := g.AddListView("x30 y128 w735 h205 -Multi NoSortHdr", ["", "Copied (local)", "Text"])
        this.HistoryList.OnEvent("ItemSelect", (*) => this.PreviewHistory())
        this.HistoryList.OnEvent("DoubleClick", (*) => this.PasteHistory())
        this.Preview := g.AddEdit("x30 y345 w735 h112 ReadOnly Multi -Wrap")
        this.RichButton := g.AddButton("x30 y471 w175 h32 Default", "Paste original")
        this.RichButton.OnEvent("Click", (*) => this.PasteHistory())
        this.PlainButton := g.AddButton("x213 y471 w160 h32", "Paste plain text")
        this.PlainButton.OnEvent("Click", (*) => this.PasteHistory(true))
        this.QuoteButton := g.AddButton("x30 y510 w150 h28", "Paste as quote")
        this.QuoteButton.OnEvent("Click", (*) => this.PasteQuoted())
        this.SingleLineButton := g.AddButton("x188 y510 w170 h28", "Paste as one line")
        this.SingleLineButton.OnEvent("Click", (*) => this.PasteSingleLine())
        this.PinButton := g.AddButton("x383 y471 w80 h32", "Pin")
        this.PinButton.OnEvent("Click", (*) => this.TogglePin())
        this.DeleteButton := g.AddButton("x473 y471 w80 h32", "Delete")
        this.DeleteButton.OnEvent("Click", (*) => this.DeleteClip())
        this.ToPhraseButton := g.AddButton("x563 y471 w200 h32", "Save as phrase")
        this.ToPhraseButton.OnEvent("Click", (*) => this.ClipToPhrase())
        this.Tab.UseTab(2)
        this.PhraseSearch := g.AddEdit("x30 y88 w325 h28")
        DllCall("SendMessage", "Ptr", this.PhraseSearch.Hwnd, "UInt", 0x1501, "Ptr", 1, "Str", "Find a phrase or abbreviation")
        this.PhraseSearch.OnEvent("Change", (*) => this.RefreshPhrases())
        this.FolderChoice := g.AddDropDownList("x365 y88 w220", ["All phrases"])
        this.FolderChoice.OnEvent("Change", (*) => this.ChangeFolder())
        this.NewFolderButton := g.AddButton("x595 y86 w170 h30", "New folder")
        this.NewFolderButton.OnEvent("Click", (*) => this.CreateFolder())
        this.PhraseList := g.AddListView("x30 y128 w735 h205 -Multi NoSortHdr", ["Phrase", "Abbreviation"])
        this.PhraseList.OnEvent("ItemSelect", (*) => this.PreviewPhrase())
        this.PhraseList.OnEvent("DoubleClick", (*) => this.PastePhrase())
        this.PhraseList.OnEvent("ContextMenu", (ctrl, row, rightClick, x, y) => this.PhraseContextMenu(row, x, y))
        this.PhrasePreview := g.AddCustom("ClassRICHEDIT50W x30 y345 w735 h112 ReadOnly +0x50010804 +0x10000")
        this.InsertButton := g.AddButton("x30 y471 w160 h32", "Insert phrase")
        this.InsertButton.OnEvent("Click", (*) => this.PastePhrase())
        this.NewButton := g.AddButton("x200 y471 w130 h32", "New phrase")
        this.NewButton.OnEvent("Click", (*) => this.EditPhrase(0, "",
            this.ShowAllFolders ? "" : this.CurrentFolderId))
        this.EditButton := g.AddButton("x340 y471 w130 h32", "Edit phrase")
        this.EditButton.OnEvent("Click", (*) => this.EditSelected())
        this.RemoveButton := g.AddButton("x480 y471 w130 h32", "Delete phrase")
        this.RemoveButton.OnEvent("Click", (*) => this.DeletePhrase())
        this.FavoriteButton := g.AddButton("x620 y471 w145 h32", "Favorite")
        this.FavoriteButton.OnEvent("Click", (*) => this.ToggleFavorite())
        this.RenameFolderButton := g.AddButton("x30 y510 w150 h28", "Rename folder")
        this.RenameFolderButton.OnEvent("Click", (*) => this.RenameFolder())
        this.DeleteFolderButton := g.AddButton("x190 y510 w150 h28", "Delete folder")
        this.DeleteFolderButton.OnEvent("Click", (*) => this.DeleteFolder())
        this.FolderDefaultsButton := g.AddButton("x350 y510 w190 h28", "Folder trigger defaults")
        this.FolderDefaultsButton.OnEvent("Click", (*) => this.EditFolderDefaults())
        this.Tab.UseTab(3)
        this.AddLabel("x35 y92 w710 h100", "Ctrl+Shift+V   Clipboard history`nAlt+Shift+V     Paste current clipboard as plain text`nCtrl+Alt+Space   Phrase library`nDouble-click an item to paste it into the app you were using.")
        this.AddLabel("x35 y188 w710 h22", "AI sends text only for a checked AI phrase. The API key stays in its own encrypted file.")
        this.AiProviderChoice := g.AddDropDownList("x35 y212 w150", ["Ollama", "OpenAI-compatible"])
        this.AiProviderChoice.Value := this.AiSettings.Provider = "OpenAICompatible" ? 2 : 1
        this.AiEndpointEdit := g.AddEdit("x195 y212 w250 h24", this.AiSettings.Endpoint)
        DllCall("SendMessage", "Ptr", this.AiEndpointEdit.Hwnd, "UInt", 0x1501, "Ptr", 1, "Str", "Endpoint")
        this.AiModelEdit := g.AddEdit("x455 y212 w220 h24", this.AiSettings.Model)
        DllCall("SendMessage", "Ptr", this.AiModelEdit.Hwnd, "UInt", 0x1501, "Ptr", 1, "Str", "Model")
        this.AiTemperatureEdit := g.AddEdit("x35 y242 w90 h24", this.AiSettings.Temperature)
        DllCall("SendMessage", "Ptr", this.AiTemperatureEdit.Hwnd, "UInt", 0x1501, "Ptr", 1, "Str", "Temperature")
        this.AiTokensEdit := g.AddEdit("x135 y242 w90 h24", this.AiSettings.MaxTokens)
        DllCall("SendMessage", "Ptr", this.AiTokensEdit.Hwnd, "UInt", 0x1501, "Ptr", 1, "Str", "Max tokens")
        this.AiTimeoutEdit := g.AddEdit("x235 y242 w80 h24", this.AiSettings.TimeoutSec)
        DllCall("SendMessage", "Ptr", this.AiTimeoutEdit.Hwnd, "UInt", 0x1501, "Ptr", 1, "Str", "Timeout")
        this.AiKeyEdit := g.AddEdit("x325 y242 w200 h24 Password", "")
        DllCall("SendMessage", "Ptr", this.AiKeyEdit.Hwnd, "UInt", 0x1501, "Ptr", 1, "Str", this.AiKey ? "API key saved" : "API key")
        g.AddButton("x535 y240 w90 h26", "Test").OnEvent("Click", (*) => this.TestAiConnection())
        g.AddButton("x630 y240 w90 h26", "Save AI").OnEvent("Click", (*) => this.SaveAiSettings())
        this.AiStatus := this.AddLabel("x35 y268 w700 h22", "")
        this.ExpansionCheck := g.AddCheckbox("x35 y295 w650", "Enable abbreviation expansion (type abbreviation, then Space or Enter)")
        this.ExpansionCheck.Value := this.Expansions
        this.ExpansionCheck.OnEvent("Click", (*) => this.ToggleExpansions())
        this.SecretCheck := g.AddCheckbox("x35 y318 w650", "Skip copies that look like common API keys")
        this.SecretCheck.Value := this.SkipLikelySecrets
        this.SecretCheck.OnEvent("Click", (*) => this.ToggleSecretDetection())
        this.NonTextCheck := g.AddCheckbox("x35 y342 w700", "Save image and file copies (2 MB per item; may contain sensitive data)")
        this.NonTextCheck.Value := this.CaptureNonText
        this.NonTextCheck.OnEvent("Click", (*) => this.ToggleCaptureNonText())
        this.StartCheck := g.AddCheckbox("x35 y366 w650", "Start PhraseBoard when I sign in to Windows")
        this.StartCheck.Value := !!FileExist(A_Startup "\PhraseBoard.lnk")
        this.StartCheck.OnEvent("Click", (*) => this.SetStartup())
        this.AddLabel("x35 y394 w220 h24", "History retention days (0 = forever)")
        this.RetentionEdit := g.AddEdit("x260 y390 w70 h26", this.RetentionDays)
        this.RetentionEdit.OnEvent("LoseFocus", (*) => this.UpdateRetention())
        this.AddLabel("x35 y421 w700 h22", "Excluded apps (comma-separated process names)")
        this.ExcludedEdit := g.AddEdit("x35 y441 w700 h26", this.ExcludedApps)
        this.ExcludedEdit.OnEvent("LoseFocus", (*) => this.UpdateExcludedApps())
        clear := g.AddButton("x35 y470 w245 h32", "Clear all clipboard history...")
        clear.OnEvent("Click", (*) => this.ClearHistory())
        exportButton := g.AddButton("x300 y470 w150 h30", "Export phrases CSV")
        exportButton.OnEvent("Click", (*) => this.ExportPhrases())
        importButton := g.AddButton("x465 y470 w150 h30", "Import phrases CSV")
        importButton.OnEvent("Click", (*) => this.ImportPhrases())
        diagnosticsButton := g.AddButton("x630 y470 w130 h30", "Diagnostics")
        diagnosticsButton.OnEvent("Click", (*) => this.ShowDiagnostics())
        this.AddLabel("x35 y505 w275 h24", "SmartComplete minimum characters")
        this.SmartCompleteMinEdit := g.AddEdit("x315 y501 w55 h26", this.SmartCompleteMinChars)
        this.SmartCompleteMinEdit.OnEvent("LoseFocus", (*) => this.UpdateSmartCompleteMinChars())
        this.AddLabel("x390 y505 w365 h24", "Pause history: Ctrl+Alt+Shift+H · Trigger searches are case-sensitive.")
        this.Tab.UseTab(4)
        this.AddLabel("x35 y88 w700 h28", "Make PhraseBoard fit your screen and workflow. Changes save automatically.")
        this.AddLabel("x35 y135 w170 h24", "Color theme")
        this.ThemeChoice := g.AddDropDownList("x225 y130 w210", ["Light", "Dark"])
        this.ThemeChoice.Value := this.Theme = "Dark" ? 2 : 1
        this.ThemeChoice.OnEvent("Change", (*) => this.UpdateCustomization())
        this.AddLabel("x35 y180 w170 h24", "Text size")
        this.FontChoice := g.AddDropDownList("x225 y175 w210", ["9", "10", "11", "12", "13", "14"])
        this.FontChoice.Value := this.FontSize - 8
        this.FontChoice.OnEvent("Change", (*) => this.UpdateCustomization())
        this.AddLabel("x35 y225 w170 h24", "Layout density")
        this.DensityChoice := g.AddDropDownList("x225 y220 w210", ["Comfortable", "Compact"])
        this.DensityChoice.Value := this.Density = "Compact" ? 2 : 1
        this.DensityChoice.OnEvent("Change", (*) => this.UpdateCustomization())
        this.AddLabel("x35 y270 w170 h24", "Clipboard order")
        this.HistorySortChoice := g.AddDropDownList("x225 y265 w210", ["Newest first", "Oldest first"])
        this.HistorySortChoice.Value := this.HistorySort = "Oldest first" ? 2 : 1
        this.HistorySortChoice.OnEvent("Change", (*) => this.UpdateCustomization())
        this.AddLabel("x35 y315 w170 h24", "Phrase order")
        this.PhraseSortChoice := g.AddDropDownList("x225 y310 w210", ["Most used", "Favorites first", "A to Z"])
        this.PhraseSortChoice.Value := this.PhraseSort = "Favorites first" ? 2 : this.PhraseSort = "A to Z" ? 3 : 1
        this.PhraseSortChoice.OnEvent("Change", (*) => this.UpdateCustomization())
        this.AddLabel("x35 y370 w190 h24", "History item limit")
        this.EntryLimitEdit := g.AddEdit("x225 y365 w90 h26", this.MaxEntries)
        this.EntryLimitEdit.OnEvent("LoseFocus", (*) => this.UpdateCapacity())
        this.AddLabel("x350 y370 w175 h24", "Storage limit (MB)")
        this.StorageLimitEdit := g.AddEdit("x525 y365 w90 h26", this.MaxBytes // (1024 * 1024))
        this.StorageLimitEdit.OnEvent("LoseFocus", (*) => this.UpdateCapacity())
        this.AddLabel("x35 y415 w700 h46", "Limits accept 20–1,000 items and 8–512 MB. Pins stay protected from automatic cleanup.")
        resetCustomize := g.AddButton("x35 y475 w180 h32", "Restore defaults")
        resetCustomize.OnEvent("Click", (*) => this.ResetCustomization())
        this.CustomizeStatus := this.AddLabel("x235 y480 w500 h26", "Appearance applies immediately; ordering updates the lists.")
        this.Tab.UseTab()
        this.Status := g.AddText("x20 y542 w755 h35", this.LastError ? this.LastError : "Ready. Your clipboard history starts with your next copy.")
        this.Labels.Push(this.Status)
        g.OnEvent("Close", (*) => this.Hide())
        g.OnEvent("Escape", (*) => this.Hide())
        g.OnEvent("Size", ObjBindMethod(this, "Resize"))
        this.ApplyCustomization()
        this.RefreshFolderChoices()
        this.RefreshHistory()
        this.RefreshPhrases()
    }
    AddLabel(options, text) {
        control := this.Window.AddText(options, text)
        this.Labels.Push(control)
        return control
    }
    Resize(gui, state, width, height) {
        if state = -1
            return
        this.Tab.Move(, , width - 30, height - 100)
        this.Status.Move(, height - 40, width - 40)
        compact := this.Density = "Compact"
        for list in [this.HistoryList, this.PhraseList]
            list.Move(, , width - 65, Max(125, height - 375 + (compact ? 10 : 0)))
        this.Search.Move(, , width - 245)
        this.PauseButton.Move(width - 205)
        this.PhraseSearch.Move(, , width - 65)
        for preview in [this.Preview, this.PhrasePreview]
            preview.Move(, height - 235 + (compact ? 6 : 0), width - 65)
        for button in [this.RichButton, this.PlainButton, this.PinButton, this.DeleteButton,
            this.ToPhraseButton, this.InsertButton, this.NewButton, this.EditButton, this.RemoveButton, this.FavoriteButton]
            button.Move(, height - 109)
    }
    Show(tab := 1, *) {
        active := WinExist("A")
        if active && active != this.Window.Hwnd
            this.Target := active
        this.Tab.Choose(tab)
        this.TabChanged()
        this.Visible := true
        this.RefreshHistory()
        this.RefreshPhrases()
        this.Window.Show("w800 h580")
        (tab = 2 ? this.PhraseSearch : this.Search).Focus()
    }
    Hide() {
        this.Visible := false
        this.Window.Hide()
    }
    TabChanged() {
        this.RichButton.Opt(this.Tab.Value = 1 ? "+Default" : "-Default")
        this.InsertButton.Opt(this.Tab.Value = 2 ? "+Default" : "-Default")
    }
    RefreshHistory(*) {
        selected := this.SelectedClip()
        oldId := IsObject(selected) ? selected.Id : ""
        this.HistoryList.Delete()
        this.HistoryRows := []
        query := StrLower(this.Search.Value)
        sortedHistory := this.History.Clone()
        if this.HistorySort = "Oldest first" {
            Loop sortedHistory.Length {
                j := A_Index
                while j > 1 && sortedHistory[j].Time < sortedHistory[j - 1].Time {
                    swap := sortedHistory[j - 1]
                    sortedHistory[j - 1] := sortedHistory[j]
                    sortedHistory[j] := swap
                    j -= 1
                }
            }
        }
        for pinned in [true, false] {
            for item in sortedHistory {
                if item.Pinned != pinned || (query && !InStr(StrLower(item.Text), query))
                    continue
                this.HistoryRows.Push(item)
                localTime := DateAdd(item.Time, DateDiff(A_Now, A_NowUTC, "Seconds"), "Seconds")
                row := this.HistoryList.Add("", item.Pinned ? "*" : "", FormatTime(localTime, "MMM d HH:mm"),
                    SubStr(RegExReplace(item.Text, "\s+", " "), 1, 180))
                if item.Id = oldId
                    this.HistoryList.Modify(row, "Select Focus")
            }
        }
        this.HistoryList.ModifyCol(1, 30)
        this.HistoryList.ModifyCol(2, 125)
        this.HistoryList.ModifyCol(3, 555)
        if !this.HistoryList.GetNext() && this.HistoryRows.Length
            this.HistoryList.Modify(1, "Select Focus")
        this.PreviewHistory()
    }
    SelectedClip() {
        if !HasProp(this, "HistoryList")
            return 0
        row := this.HistoryList.GetNext()
        return row && row <= this.HistoryRows.Length ? this.HistoryRows[row] : 0
    }
    PreviewHistory(*) {
        item := this.SelectedClip()
        this.Preview.Value := IsObject(item) ? item.Text : "Copy some text to start your history."
        for button in [this.RichButton, this.PlainButton, this.PinButton, this.DeleteButton, this.ToPhraseButton, this.QuoteButton, this.SingleLineButton]
            button.Enabled := IsObject(item)
        this.PinButton.Text := IsObject(item) && item.Pinned ? "Unpin" : "Pin"
    }
    RefreshPhrases(*) {
        this.PhraseList.Delete()
        this.PhraseRows := []
        query := StrLower(this.PhraseSearch.Value)
        sorted := this.Phrases.Clone()
        Loop sorted.Length {
            j := A_Index
            shouldSwap := false
            if j > 1 {
                if this.PhraseSort = "A to Z"
                    shouldSwap := StrLower(sorted[j].Name) < StrLower(sorted[j - 1].Name)
                else if this.PhraseSort = "Favorites first"
                    shouldSwap := sorted[j].Favorite && !sorted[j - 1].Favorite
                else
                    shouldSwap := sorted[j].Favorite && !sorted[j - 1].Favorite
                        || sorted[j].Favorite = sorted[j - 1].Favorite && sorted[j].Uses > sorted[j - 1].Uses
            }
            while j > 1 && shouldSwap {
                swap := sorted[j - 1]
                sorted[j - 1] := sorted[j]
                sorted[j] := swap
                j -= 1
                shouldSwap := false
                if j > 1 {
                    if this.PhraseSort = "A to Z"
                        shouldSwap := StrLower(sorted[j].Name) < StrLower(sorted[j - 1].Name)
                    else if this.PhraseSort = "Favorites first"
                        shouldSwap := sorted[j].Favorite && !sorted[j - 1].Favorite
                    else
                        shouldSwap := sorted[j].Favorite && !sorted[j - 1].Favorite
                            || sorted[j].Favorite = sorted[j - 1].Favorite && sorted[j].Uses > sorted[j - 1].Uses
                }
            }
        }
        for p in sorted {
            if !this.PhraseAllowedInTarget(p, this.Target)
                continue
            if !this.ShowAllFolders && p.FolderId != this.CurrentFolderId
                continue
            if query && !InStr(StrLower(p.Name " " p.Abbr " " p.Text " " p.Tags), query)
                continue
            this.PhraseRows.Push(p)
            suffix := ""
            if p.Abbr {
                shared := PhraseModel.FindPhrasesByTrigger("Autotext", p.Abbr, this.Phrases)
                if shared.Length > 1
                    suffix := "  ↔ " shared.Length " phrases"
            }
            richBadge := (HasProp(p, "Rtf") && p.Rtf != "") ? "[Rich] " : ""
            this.PhraseList.Add("", (p.Favorite ? "★ " : "") p.Name, p.Abbr suffix "  " richBadge p.Tags)
        }
        this.PhraseList.ModifyCol(1, 490)
        this.PhraseList.ModifyCol(2, 220)
        if this.PhraseRows.Length
            this.PhraseList.Modify(1, "Select Focus")
        this.PreviewPhrase()
    }
    SelectedPhrase() {
        row := this.PhraseList.GetNext()
        return row && row <= this.PhraseRows.Length ? this.PhraseRows[row] : 0
    }
    PreviewPhrase(*) {
        p := this.SelectedPhrase()
        if IsObject(p) {
            if HasProp(p, "Rtf") && p.Rtf != ""
                RichText.SetRtf(this.PhrasePreview.Hwnd, p.Text, p.Rtf)
            else
                ControlSetText(p.Text, this.PhrasePreview)
        } else {
            ControlSetText("Create a phrase, for example `;sig for your signature.", this.PhrasePreview)
        }
        for button in [this.InsertButton, this.EditButton, this.RemoveButton]
            button.Enabled := IsObject(p)
        this.FavoriteButton.Enabled := IsObject(p)
        this.FavoriteButton.Text := IsObject(p) && p.Favorite ? "Unfavorite" : "Favorite"
    }
    TogglePause(*) {
        this.Paused := !this.Paused
        try this.SavePreferences()
        catch {
            this.Paused := !this.Paused
            this.Notify("Could not save the pause setting.")
            return
        }
        this.PauseButton.Text := this.Paused ? "Resume history" : "Pause history"
        this.Notify(this.Paused ? "History paused. New copies will not be saved." : "History resumed.")
    }
    SavePreferences() {
        this.Store.Write("preferences.dat", (this.Paused ? 1 : 0) "|" (this.Expansions ? 1 : 0)
            "|" this.RetentionDays "|" SecureStore.Encode(this.ExcludedApps)
            "|" (this.CaptureNonText ? 1 : 0) "|" (this.KeepOpenAfterPaste ? 1 : 0)
            "|" (this.SkipLikelySecrets ? 1 : 0) "|" this.Theme "|" this.FontSize "|" this.Density
            "|" this.HistorySort "|" this.PhraseSort "|" this.MaxEntries "|" (this.MaxBytes // (1024 * 1024))
            "|" this.SmartCompleteMinChars "|" AiSettings.PreferenceSuffix(this.AiSettings))
    }
    UpdateSmartCompleteMinChars(*) {
        value := Trim(this.SmartCompleteMinEdit.Value)
        if !RegExMatch(value, "^\d+$") || Integer(value) < 1 || Integer(value) > 32 {
            this.SmartCompleteMinEdit.Value := this.SmartCompleteMinChars
            this.Notify("SmartComplete minimum must be from 1 to 32 characters.")
            return
        }
        previous := this.SmartCompleteMinChars
        this.SmartCompleteMinChars := Integer(value)
        try this.SavePreferences()
        catch {
            this.SmartCompleteMinChars := previous
            this.SmartCompleteMinEdit.Value := previous
            this.Notify("Could not save SmartComplete settings.")
            return
        }
        this.Notify("SmartComplete minimum updated.")
    }
    PhraseContextMenu(row, x, y) {
        if row
            this.PhraseList.Modify(row, "Select")
        phrase := this.SelectedPhrase()
        if !IsObject(phrase)
            return
        menu := Menu()
        if HasProp(phrase, "Rtf") && phrase.Rtf != "" {
            menu.Add("Paste formatted phrase", (*) => this.PastePhrase(false))
            menu.Add("Paste as plain text", (*) => this.PastePhrase(true))
            menu.Add()
        }
        menu.Add("Edit phrase...", (*) => this.EditSelected())
        if phrase.Abbr
            menu.Add("Find phrases using this trigger", (*) => this.ShowTriggerMatches(phrase))
        menu.Show(x, y)
    }
    ShowTriggerMatches(phrase) {
        matches := PhraseModel.FindPhrasesByTrigger("Autotext", phrase.Abbr, this.Phrases)
        names := ""
        for match in matches
            names .= (names ? "`n" : "") "• " match.Name
        MsgBox("Trigger " phrase.Abbr " is used by:`n`n" names, "PhraseBoard trigger discovery")
    }
    RefreshFolderChoices() {
        if !HasProp(this, "FolderChoice")
            return
        labels := ["All phrases"]
        this.FolderChoiceIds := [""]
        for folder in this.Folders {
            labels.Push(this.FolderPathLabel(folder.Id))
            this.FolderChoiceIds.Push(folder.Id)
        }
        this.FolderChoice.Delete()
        this.FolderChoice.Add(labels)
        selected := 1
        if !this.ShowAllFolders {
            for index, id in this.FolderChoiceIds
                if id = this.CurrentFolderId
                    selected := index
        }
        this.FolderChoice.Choose(selected)
        this.RenameFolderButton.Enabled := !this.ShowAllFolders
        this.DeleteFolderButton.Enabled := !this.ShowAllFolders
        this.FolderDefaultsButton.Enabled := !this.ShowAllFolders
    }
    FolderPathLabel(folderId) {
        try return FolderTree(this.Phrases, this.Folders).Path(folderId)
        catch
            return folderId
    }
    ChangeFolder(*) {
        selected := this.FolderChoice.Value
        if !selected || selected > this.FolderChoiceIds.Length
            return
        this.ShowAllFolders := selected = 1
        this.CurrentFolderId := this.FolderChoiceIds[selected]
        this.RefreshFolderChoices()
        this.RefreshPhrases()
    }
    CreateFolder(*) {
        result := InputBox("Enter a name for the new folder.", "New phrase folder")
        if result.Result != "OK" || !Trim(result.Value)
            return
        snapshot := this.CloneFolders()
        this.Folders.Push({Id: this.NewId(), ParentId: this.ShowAllFolders ? "" : this.CurrentFolderId,
            Name: Trim(result.Value), CreatedAt: A_Now, Triggers: [], TriggerDefaults: Map()})
        try this.SavePhrases()
        catch as err {
            this.Folders := snapshot
            this.Notify("Could not save folder: " err.Message)
            return
        }
        this.CurrentFolderId := this.Folders[this.Folders.Length].Id
        this.ShowAllFolders := false
        this.RefreshFolderChoices()
        this.RefreshPhrases()
    }
    RenameFolder(*) {
        if this.ShowAllFolders
            return
        folder := this.GetFolderTree().FindFolder(this.CurrentFolderId)
        if !folder
            return
        result := InputBox("Enter the new folder name.", "Rename folder", , folder.Name)
        if result.Result != "OK" || !Trim(result.Value)
            return
        oldName := folder.Name
        folder.Name := Trim(result.Value)
        try this.SavePhrases()
        catch as err {
            folder.Name := oldName
            this.Notify("Could not save folder: " err.Message)
            return
        }
        this.RefreshFolderChoices()
    }
    EditFolderDefaults(*) {
        if this.ShowAllFolders
            return
        folder := this.GetFolderTree().FindFolder(this.CurrentFolderId)
        if !folder
            return
        inherited := this.GetFolderTree().EffectiveDefaults(folder.ParentId)
        effective := folder.TriggerDefaults.Has("Mode") ? this.CanonicalTriggerMode(folder.TriggerDefaults["Mode"])
            : (inherited.Has("Mode") ? inherited["Mode"] : "(none)")
        hotkey := ""
        for trigger in folder.Triggers
            if trigger.Kind = "Hotkey" && trigger.Enabled {
                hotkey := trigger.Value
                break
            }
        dialog := Gui("+Owner" this.Window.Hwnd, "Folder trigger settings")
        dialog.SetFont("s10", "Segoe UI")
        dialog.AddText("xm", "Folder hotkey (optional; e.g. ^!F1)")
        hotkeyEdit := dialog.AddEdit("xm w360", hotkey)
        dialog.AddText("xm", "Default execution mode; current effective value: " effective)
        modeChoice := dialog.AddDropDownList("xm w360",
            ["(inherit)", "Immediate", "Confirm", "AfterPause", "WhileTypingFast"])
        if folder.TriggerDefaults.Has("Mode") {
            selectedMode := this.CanonicalTriggerMode(folder.TriggerDefaults["Mode"])
            for index, label in ["(inherit)", "Immediate", "Confirm", "AfterPause", "WhileTypingFast"]
                if label = selectedMode
                    modeChoice.Choose(index)
        } else modeChoice.Choose(1)
        message := dialog.AddText("xm w360 r2 c9A6700", "")
        save := dialog.AddButton("xm w130 Default", "Save settings")
        save.OnEvent("Click", SaveFolderSettings)
        dialog.AddButton("x+10 w100", "Cancel").OnEvent("Click", (*) => dialog.Destroy())
        dialog.OnEvent("Escape", (*) => dialog.Destroy())
        dialog.Show("w400")
        SaveFolderSettings(*) {
            value := Trim(hotkeyEdit.Value)
            selected := modeChoice.Text
            if value {
                warnings := TriggerEngine.HotkeyWarnings(value, this.Folders, folder.Id)
                if warnings.Length {
                    message.Text := FolderTree.Join(warnings, " ")
                    if MsgBox(message.Text "`n`nSave this shortcut anyway?", "Folder shortcut warning", "YesNo Icon!") != "Yes"
                        return
                }
            }
            oldDefaults := folder.TriggerDefaults.Clone()
            oldTriggers := folder.Triggers.Clone()
            if selected = "(inherit)" {
                if folder.TriggerDefaults.Has("Mode")
                    folder.TriggerDefaults.Delete("Mode")
            } else folder.TriggerDefaults["Mode"] := selected
            preserved := []
            existingHotkey := 0
            for trigger in folder.Triggers {
                if trigger.Kind = "Hotkey" {
                    if !IsObject(existingHotkey)
                        existingHotkey := trigger
                    continue
                }
                preserved.Push(trigger)
            }
            if value {
                triggerId := IsObject(existingHotkey) && existingHotkey.Value == value ? existingHotkey.Id : ""
                preserved.Push(PhraseModel.NormalizeTrigger({Id: triggerId, Kind: "Hotkey", Value: value}))
            }
            folder.Triggers := preserved
            try {
                this.SavePhrases()
                this.RegisterPhrases()
                dialog.Destroy()
            } catch as err {
                folder.TriggerDefaults := oldDefaults
                folder.Triggers := oldTriggers
                this.Notify("Could not save folder trigger settings: " err.Message)
            }
        }
    }
    CanonicalTriggerMode(mode) {
        if mode = "Pause"
            return "AfterPause"
        if mode = "FastTyping"
            return "WhileTypingFast"
        return mode
    }
    DeleteFolder(*) {
        if this.ShowAllFolders
            return
        folder := this.GetFolderTree().FindFolder(this.CurrentFolderId)
        if !folder || MsgBox("Delete '" folder.Name "'? Its phrases and subfolders will move to its parent.",
            "PhraseBoard", "YesNo Icon!") != "Yes"
            return
        oldPhrases := this.ClonePhrases()
        oldFolders := this.CloneFolders()
        this.GetFolderTree().Delete(folder.Id, folder.ParentId)
        try this.SavePhrases()
        catch as err {
            this.Phrases := oldPhrases
            this.Folders := oldFolders
            this.Notify("Could not save folder deletion: " err.Message)
            return
        }
        this.CurrentFolderId := ""
        this.ShowAllFolders := true
        this.RefreshFolderChoices()
        this.RefreshPhrases()
    }
    GetFolderTree() => FolderTree(this.Phrases, this.Folders)
    ClonePhrases() {
        copy := []
        for phrase in this.Phrases
            copy.Push(PhraseModel.NormalizePhrase(phrase))
        return copy
    }
    CloneFolders() {
        copy := []
        for folder in this.Folders
            copy.Push(PhraseModel.NormalizeFolder(folder))
        return copy
    }
    UpdateCustomization(*) {
        previous := [this.Theme, this.FontSize, this.Density, this.HistorySort, this.PhraseSort]
        this.Theme := this.ThemeChoice.Text
        this.FontSize := Integer(this.FontChoice.Text)
        this.Density := this.DensityChoice.Text
        this.HistorySort := this.HistorySortChoice.Text
        this.PhraseSort := this.PhraseSortChoice.Text
        try {
            this.SavePreferences()
            this.ApplyCustomization()
            this.RefreshHistory()
            this.RefreshPhrases()
            this.CustomizeStatus.Text := "Saved. Your choices will be restored next time too."
        } catch {
            this.Theme := previous[1], this.FontSize := previous[2], this.Density := previous[3]
            this.HistorySort := previous[4], this.PhraseSort := previous[5]
            this.ThemeChoice.Value := this.Theme = "Dark" ? 2 : 1
            this.FontChoice.Value := this.FontSize - 8
            this.DensityChoice.Value := this.Density = "Compact" ? 2 : 1
            this.HistorySortChoice.Value := this.HistorySort = "Oldest first" ? 2 : 1
            this.PhraseSortChoice.Value := this.PhraseSort = "Favorites first" ? 2
                : this.PhraseSort = "A to Z" ? 3 : 1
            this.ApplyCustomization()
            this.Notify("Could not save customization settings.")
        }
    }
    ApplyCustomization() {
        dark := this.Theme = "Dark"
        this.Window.BackColor := dark ? "20242C" : "F5F7FA"
        textColor := dark ? "E7EAF0" : "20242C"
        controls := [this.Tab, this.KeepOpenCheck, this.Search, this.PauseButton, this.HistoryList,
            this.Preview, this.RichButton, this.PlainButton, this.QuoteButton, this.SingleLineButton,
            this.PinButton, this.DeleteButton, this.ToPhraseButton, this.PhraseSearch, this.PhraseList,
            this.PhrasePreview, this.InsertButton, this.NewButton, this.EditButton, this.RemoveButton,
            this.FavoriteButton, this.ExpansionCheck, this.SecretCheck, this.NonTextCheck, this.StartCheck,
            this.RetentionEdit, this.ExcludedEdit, this.ThemeChoice, this.FontChoice, this.DensityChoice,
            this.HistorySortChoice, this.PhraseSortChoice, this.EntryLimitEdit, this.StorageLimitEdit,
            this.Status, this.AiProviderChoice, this.AiEndpointEdit, this.AiModelEdit,
            this.AiTemperatureEdit, this.AiTokensEdit, this.AiTimeoutEdit, this.AiKeyEdit, this.AiStatus]
        for control in controls {
            try control.SetFont("s" this.FontSize " c" textColor, "Segoe UI")
            try control.Opt(dark ? "Background20242C" : "BackgroundF5F7FA")
        }
        for label in this.Labels {
            try label.SetFont("s" this.FontSize " c" textColor, "Segoe UI")
        }
        compact := this.Density = "Compact"
        listHeight := compact ? 215 : 205
        this.HistoryList.Move(,,, listHeight)
        this.PhraseList.Move(,,, listHeight)
        this.Preview.Move(, compact ? 351 : 345,, compact ? 88 : 112)
        this.PhrasePreview.Move(, compact ? 351 : 345,, compact ? 88 : 112)
    }
    UpdateCapacity(*) {
        entries := Trim(this.EntryLimitEdit.Value)
        megabytes := Trim(this.StorageLimitEdit.Value)
        if !RegExMatch(entries, "^\d{1,4}$") || !RegExMatch(megabytes, "^\d{1,3}$") {
            this.EntryLimitEdit.Value := this.MaxEntries
            this.StorageLimitEdit.Value := this.MaxBytes // (1024 * 1024)
            return
        }
        entries := Max(20, Min(1000, Integer(entries)))
        megabytes := Max(8, Min(512, Integer(megabytes)))
        oldEntries := this.MaxEntries, oldBytes := this.MaxBytes
        this.MaxEntries := entries, this.MaxBytes := megabytes * 1024 * 1024
        this.EntryLimitEdit.Value := entries, this.StorageLimitEdit.Value := megabytes
        try {
            this.SavePreferences()
            this.TrimHistory()
            this.RefreshHistory()
            this.CustomizeStatus.Text := "Saved. Limits apply immediately; pinned items remain protected."
        } catch {
            this.MaxEntries := oldEntries, this.MaxBytes := oldBytes
            this.EntryLimitEdit.Value := oldEntries
            this.StorageLimitEdit.Value := oldBytes // (1024 * 1024)
            this.Notify("Could not save history limits.")
        }
    }
    ResetCustomization(*) {
        this.ThemeChoice.Value := 1, this.FontChoice.Value := 2, this.DensityChoice.Value := 1
        this.HistorySortChoice.Value := 1, this.PhraseSortChoice.Value := 1
        this.EntryLimitEdit.Value := 100, this.StorageLimitEdit.Value := 32
        this.UpdateCustomization()
        this.UpdateCapacity()
    }
    ToggleExpansions(*) {
        previous := this.Expansions
        this.Expansions := !!this.ExpansionCheck.Value
        try this.SavePreferences()
        catch {
            this.Expansions := previous
            this.ExpansionCheck.Value := previous
            this.Notify("Could not save the expansion setting.")
            return
        }
        this.RegisterPhrases()
    }
    QuickPaste(plain := false) {
        if this.Tab.Value = 1
            this.PasteHistory(plain)
        else if this.Tab.Value = 2
            this.PastePhrase()
    }
    ToggleCurrentFavoriteOrPin() {
        if this.Tab.Value = 1
            this.TogglePin()
        else if this.Tab.Value = 2
            this.ToggleFavorite()
    }
    DeleteCurrentItem() {
        if this.Tab.Value = 1
            this.DeleteClip()
        else if this.Tab.Value = 2
            this.DeletePhrase()
    }
    MoveSelection(delta) {
        if this.Tab.Value > 2
            return
        list := this.Tab.Value = 1 ? this.HistoryList : this.PhraseList
        rows := this.Tab.Value = 1 ? this.HistoryRows : this.PhraseRows
        if !rows.Length
            return
        row := list.GetNext()
        row := row ? Max(1, Min(rows.Length, row + delta)) : 1
        list.Modify(row, "Select Focus")
        if this.Tab.Value = 1
            this.PreviewHistory()
        else
            this.PreviewPhrase()
    }
    UpdateRetention(*) {
        value := Trim(this.RetentionEdit.Value)
        if !RegExMatch(value, "^\d{1,4}$")
            return
        previous := this.RetentionDays
        this.RetentionDays := Integer(value)
        try {
            this.SavePreferences()
            this.ApplyRetention()
            this.RefreshHistory()
        } catch {
            this.RetentionDays := previous
            this.RetentionEdit.Value := previous
            this.Notify("Could not save the retention setting.")
        }
    }
    UpdateExcludedApps(*) {
        previous := this.ExcludedApps
        this.ExcludedApps := Trim(this.ExcludedEdit.Value)
        try this.SavePreferences()
        catch {
            this.ExcludedApps := previous
            this.ExcludedEdit.Value := previous
            this.Notify("Could not save the excluded app list.")
        }
    }
    ToggleFavorite(*) {
        p := this.SelectedPhrase()
        if !IsObject(p)
            return
        p.Favorite := !p.Favorite
        this.SavePhrases()
        this.RefreshPhrases()
    }
    ToggleCaptureNonText(*) {
        previous := this.CaptureNonText
        this.CaptureNonText := !!this.NonTextCheck.Value
        try this.SavePreferences()
        catch {
            this.CaptureNonText := previous
            this.NonTextCheck.Value := previous
            this.Notify("Could not save the image and file capture setting.")
        }
    }
    ToggleKeepOpen(*) {
        previous := this.KeepOpenAfterPaste
        this.KeepOpenAfterPaste := !!this.KeepOpenCheck.Value
        try this.SavePreferences()
        catch {
            this.KeepOpenAfterPaste := previous
            this.KeepOpenCheck.Value := previous
            this.Notify("Could not save the picker setting.")
        }
    }
    ToggleSecretDetection(*) {
        previous := this.SkipLikelySecrets
        this.SkipLikelySecrets := !!this.SecretCheck.Value
        try this.SavePreferences()
        catch {
            this.SkipLikelySecrets := previous
            this.SecretCheck.Value := previous
            this.Notify("Could not save the secret detection setting.")
        }
    }
    ShowDiagnostics(*) {
        target := "No destination selected"
        if this.Target {
            try {
                target := WinGetProcessName(this.Target)
            } catch {
                target := "Unavailable"
            }
        }
        MsgBox("Storage: " this.Store.Dir "`nHistory items: " this.History.Length
            "`nPhrases: " this.Phrases.Length "`nHistory: " (this.Paused ? "paused" : "recording")
            "`nPhrase expansion: " (this.Expansions ? "enabled" : "disabled")
            "`nDestination: " target "`nLast status: " (this.LastError ? this.LastError : "Ready"),
            "PhraseBoard diagnostics")
    }
    CsvField(value) => Chr(34) StrReplace(value, Chr(34), Chr(34) Chr(34)) Chr(34)
    ExportPhrases(*) {
        path := FileSelect("S16", , "Export PhraseBoard phrases", "CSV files (*.csv)")
        if !path
            return
        output := PhraseLibrary.ExportCsv(this.Phrases)
        try {
            file := FileOpen(path, "w", "UTF-8-RAW")
            try file.Write(output)
            finally file.Close()
            this.Notify("Phrase library exported.")
        } catch {
            this.Notify("Could not export phrases to that file.")
        }
    }
    ParseCSV(source) {
        rows := [], row := [], field := "", quoted := false
        i := 1
        while i <= StrLen(source) {
            ch := SubStr(source, i, 1)
            if quoted {
                if ch = Chr(34) {
                    if SubStr(source, i + 1, 1) = Chr(34) {
                        field .= Chr(34)
                        i += 1
                    } else quoted := false
                } else field .= ch
            } else if ch = Chr(34)
                quoted := true
            else if ch = "," {
                row.Push(field), field := ""
            } else if ch = "`n" || ch = "`r" {
                if ch = "`r" && SubStr(source, i + 1, 1) = "`n"
                    i += 1
                row.Push(field), field := ""
                if row.Length > 1 || row[1] != ""
                    rows.Push(row)
                row := []
            } else field .= ch
            i += 1
        }
        if quoted
            throw Error("The CSV file has an unfinished quoted field.")
        row.Push(field)
        if row.Length > 1 || row[1] != ""
            rows.Push(row)
        return rows
    }
    ImportPhrases(*) {
        path := FileSelect("1", , "Import PhraseBoard phrases", "CSV files (*.csv)")
        if !path
            return
        previous := this.Phrases.Clone()
        try {
            csv := FileRead(path, "UTF-8")
            if SubStr(csv, 1, 1) = Chr(0xFEFF)
                csv := SubStr(csv, 2)
            rows := this.ParseCSV(csv)
            imported := 0
            for i, row in rows {
                if i = 1 {
                    if StrLower(row[1]) != "name"
                        throw Error("The first CSV column must be Name.")
                    continue
                }
                while row.Length < 6
                    row.Push("")
                if !Trim(row[1]) || !row[3]
                    continue
                duplicate := false
                for existing in this.Phrases
                    if row[2] && StrLower(existing.Abbr) = StrLower(row[2])
                        duplicate := true
                if duplicate
                    continue
                this.ValidatePhrase(row[1], row[2], row[3])
                this.Phrases.Push({Id: this.NewId(), Name: row[1], Abbr: row[2], Text: row[3],
                    Tags: row[4], Favorite: StrLower(row[5]) = "true" || row[5] = "1",
                    Uses: 0, Apps: row[6]})
                imported += 1
            }
            this.SavePhrases()
            this.RegisterPhrases()
            this.RefreshPhrases()
            this.Notify("Imported " imported " phrase" (imported = 1 ? "" : "s") ". Duplicate abbreviations were skipped.")
        } catch as err {
            this.Phrases := previous
            try this.RegisterPhrases()
            this.RefreshPhrases()
            this.Notify("Phrase import failed: " err.Message)
        }
    }
    TogglePin(*) {
        item := this.SelectedClip()
        if !IsObject(item)
            return
        count := 0
        for clip in this.History
            count += clip.Pinned ? 1 : 0
        if !item.Pinned && count >= 20 {
            this.Notify("Unpin an item first. You can pin up to 20 items.")
            return
        }
        item.Pinned := !item.Pinned
        try this.SaveClip(item)
        catch {
            item.Pinned := !item.Pinned
            this.Notify("Could not save the pin change.")
        }
        this.RefreshHistory()
    }
    DeleteClip(*) {
        item := this.SelectedClip()
        if !IsObject(item)
            return
        try {
            this.Store.Delete(item.Id ".clip")
            for index, clip in this.History
                if clip.Id = item.Id {
                    this.History.RemoveAt(index)
                    break
                }
            this.RefreshHistory()
        } catch {
            this.Notify("Could not delete this saved item.")
        }
    }
    ClearHistory(confirm := true, *) {
        if confirm && MsgBox("Delete all saved clipboard history, including pinned items? Phrases are kept.",
            "Clear history", "YesNo Icon!") != "Yes"
            return
        SetTimer(this.CaptureCallback, 0)
        try {
            Loop Files this.Store.Dir "\*.clip"
                FileDelete(A_LoopFileFullPath)
            this.History := []
            this.RefreshHistory()
            this.Notify("Saved history cleared. The current Windows clipboard was not changed.")
        } catch {
            this.Notify("Some history files could not be deleted.")
        }
    }
    EditSelected(*) {
        p := this.SelectedPhrase()
        if IsObject(p)
            this.EditPhrase(p)
    }
    ClipToPhrase(*) {
        item := this.SelectedClip()
        if IsObject(item) && item.Kind = "text" {
            clipRtf := RichText.ExtractRtfFromClip(item.Data)
            this.EditPhrase(0, item.Text, "", clipRtf)
        }
    }
    ReadAiForm() {
        provider := this.AiProviderChoice.Text = "OpenAI-compatible" ? "OpenAICompatible" : "Ollama"
        settings := AiSettings.Validate({
            Provider: provider,
            Endpoint: this.AiEndpointEdit.Value,
            Model: this.AiModelEdit.Value,
            Temperature: this.AiTemperatureEdit.Value,
            MaxTokens: this.AiTokensEdit.Value,
            TimeoutSec: this.AiTimeoutEdit.Value
        })
        key := Trim(this.AiKeyEdit.Value)
        if key = "" && AiSettings.SameKeyTarget(settings, this.AiSettings)
            key := this.AiKey
        return {Settings: settings, Key: key}
    }
    SaveAiSettings(*) {
        try {
            form := this.ReadAiForm()
            this.AiSettings := form.Settings
            this.AiKey := form.Key
            this.SavePreferences()
            if Trim(this.AiKey) = ""
                this.Store.Delete("ai-secrets.dat")
            else
                this.Store.Write("ai-secrets.dat", this.AiKey)
            this.AiKeyEdit.Value := ""
            this.AiStatus.Text := "AI settings saved."
        } catch as err {
            this.AiStatus.Text := AiSettings.Redact(err.Message, this.AiKey)
        }
    }
    TestAiConnection(*) {
        try {
            form := this.ReadAiForm()
            result := AiService.Generate({Kind: "test", Input: "", Instruction: ""},
                form.Settings, form.Key, WinHttpTransport)
            this.AiStatus.Text := result.Ok ? "Connection succeeded." : result.Error
        } catch as err {
            this.AiStatus.Text := AiSettings.Redact(err.Message, this.AiKey)
        }
    }
    NoteEditorTyping() {
        if this.ApplyingAi
            return
        this.AiUndoArmed := false
        this.SetAiUndoHotkey(false)
    }
    ClearAiUndo(*) {
        this.SetAiUndoHotkey(false)
        this.AiUndo := []
        this.AiUndoArmed := false
        this.AiEditorHwnd := 0
    }
    ClosePhraseEditor(editor) {
        this.ClearAiUndo()
        try editor.Destroy()
    }
    SetAiUndoHotkey(enabled) {
        if !this.AiEditorHwnd
            return
        HotIfWinActive("ahk_id " this.AiEditorHwnd)
        try {
            if enabled && !this.AiUndoHotkeyOn {
                Hotkey("^z", ObjBindMethod(this, "UndoAiEdit"), "On")
                this.AiUndoHotkeyOn := true
            } else if !enabled && this.AiUndoHotkeyOn {
                Hotkey("^z", "Off")
                this.AiUndoHotkeyOn := false
            }
        } catch {
            this.AiUndoHotkeyOn := false
        }
        HotIfWinActive()
    }
    UndoAiEdit(*) {
        if !this.AiUndoArmed || !this.AiUndo.Length
            return
        entry := this.AiUndo.Pop()
        this.ApplyingAi := true
        this.AiEditorName.Value := entry.Name
        this.AiEditorBody.Value := entry.Body
        this.ApplyingAi := false
        this.AiUndoArmed := this.AiUndo.Length > 0
        if !this.AiUndoArmed
            this.SetAiUndoHotkey(false)
    }
    RememberAiEdit() {
        if !HasProp(this, "AiUndo") || !IsObject(this.AiUndo)
            this.AiUndo := []
        this.AiUndo.Push({Name: this.AiEditorName.Value, Body: this.AiEditorBody.Value})
        this.AiUndoArmed := true
        this.SetAiUndoHotkey(true)
    }
    EditSelection(edit) {
        start := 0
        end := 0
        DllCall("SendMessage", "Ptr", edit.Hwnd, "UInt", 0xB0, "UInt*", &start, "UInt*", &end)
        return {Start: start, End: end}
    }
    EditRawText(edit) {
        length := DllCall("SendMessage", "Ptr", edit.Hwnd, "UInt", 0x000E, "Ptr", 0, "Ptr", 0, "Ptr")
        if length < 0
            length := 0
        buf := Buffer((length + 1) * 2, 0)
        DllCall("SendMessage", "Ptr", edit.Hwnd, "UInt", 0x000D, "Ptr", length + 1, "Ptr", buf)
        return StrGet(buf, length, "UTF-16")
    }
    AskText(title, label) {
        holder := {Accepted: false, Result: ""}
        g := Gui("+AlwaysOnTop +Owner" this.AiEditorHwnd, title)
        g.SetFont("s10", "Segoe UI")
        g.AddText("xm", label)
        edit := g.AddEdit("xm w460")
        g.AddButton("xm w90 Default", "Send").OnEvent("Click", (*) => this.AcceptTextDialog(holder, edit, g))
        g.AddButton("x+10 w90", "Cancel").OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.Show()
        WinWaitClose("ahk_id " g.Hwnd)
        return holder.Accepted ? Trim(holder.Result) : ""
    }
    AcceptTextDialog(holder, edit, gui) {
        holder.Accepted := true
        holder.Result := edit.Value
        gui.Destroy()
    }
    AskInstruction() {
        holder := {Choice: 0}
        g := Gui("+AlwaysOnTop +Owner" this.AiEditorHwnd, "Improve text")
        g.SetFont("s10", "Segoe UI")
        g.AddText("xm", "Preset")
        preset := g.AddDropDownList("xm w220", ["Shorten", "Clarify", "Fix grammar", "Custom"])
        preset.Choose(1)
        g.AddText("xm", "Custom instruction")
        custom := g.AddEdit("xm w460")
        g.AddButton("xm w90 Default", "Send").OnEvent("Click", (*) => this.AcceptInstructionDialog(holder, preset, custom, g))
        g.AddButton("x+10 w90", "Cancel").OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.Show()
        WinWaitClose("ahk_id " g.Hwnd)
        return holder.Choice
    }
    AcceptInstructionDialog(holder, preset, custom, gui) {
        holder.Choice := {Preset: preset.Text, Custom: custom.Value}
        gui.Destroy()
    }
    AskKeep(title, text) {
        holder := {Kept: false}
        g := Gui("+AlwaysOnTop +Owner" this.AiEditorHwnd, title)
        g.SetFont("s10", "Segoe UI")
        g.AddEdit("xm w520 r12 ReadOnly", text)
        g.AddButton("xm w90 Default", "Keep").OnEvent("Click", (*) => this.AcceptKeepDialog(holder, g))
        g.AddButton("x+10 w90", "Discard").OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.Show()
        WinWaitClose("ahk_id " g.Hwnd)
        return holder.Kept
    }
    AcceptKeepDialog(holder, gui) {
        holder.Kept := true
        gui.Destroy()
    }
    GeneratePhraseDraft(name, body, errorLabel) {
        description := this.AskText("Generate phrase", "Describe the phrase")
        if description = ""
            return
        result := AiService.Generate({Kind: "generate", Input: description, Instruction: ""},
            this.AiSettings, this.AiKey, WinHttpTransport)
        if !result.Ok {
            errorLabel.Text := result.Error
            return
        }
        try draft := AiWorkflows.ParseGenerated(result.Text)
        catch as err {
            errorLabel.Text := err.Message
            return
        }
        if !this.AskKeep("Keep this generated phrase?", draft.Name "`n`n" draft.Body)
            return
        this.RememberAiEdit()
        this.ApplyingAi := true
        name.Value := draft.Name
        body.Value := draft.Body
        this.ApplyingAi := false
        errorLabel.Text := ""
    }
    ImprovePhraseSelection(body, errorLabel) {
        choice := this.AskInstruction()
        if !IsObject(choice)
            return
        try instruction := AiWorkflows.PresetInstruction(choice.Preset, choice.Custom)
        catch as err {
            errorLabel.Text := err.Message
            return
        }
        sel := this.EditSelection(body)
        whole := sel.Start = sel.End
        raw := this.EditRawText(body)
        start := whole ? 0 : AiWorkflows.ValueOffset(raw, sel.Start)
        end := whole ? StrLen(body.Value) : AiWorkflows.ValueOffset(raw, sel.End)
        source := whole ? body.Value : SubStr(body.Value, start + 1, end - start)
        result := AiService.Generate({Kind: "improve", Instruction: instruction, Input: source},
            this.AiSettings, this.AiKey, WinHttpTransport)
        if !result.Ok {
            errorLabel.Text := result.Error
            return
        }
        if !this.AskKeep("Keep this improved text?", result.Text)
            return
        this.RememberAiEdit()
        this.ApplyingAi := true
        body.Value := AiWorkflows.ApplyReplacement(body.Value, start, end, result.Text)
        this.ApplyingAi := false
        errorLabel.Text := ""
    }
    EditPhrase(item := 0, initialText := "", folderId := "", initialRtf := "") {
        if HasProp(this, "Editor") {
            this.ClearAiUndo()
            try this.Editor.Destroy()
        }
        e := this.Editor := Gui("+Owner" this.Window.Hwnd, IsObject(item) ? "Edit phrase" : "New phrase")
        e.SetFont("s10", "Segoe UI")
        e.AddText("xm", "Name")
        name := e.AddEdit("xm w560 vName", IsObject(item) ? item.Name : "")
        e.AddText("xm", "Abbreviation (optional, e.g. `;sig). Follow it with Space or Enter to expand.")
        abbr := e.AddEdit("xm w560 vAbbr", IsObject(item) ? item.Abbr : "")
        e.AddText("xm", "Tokens: {{date}}, {{time}}, {{clipboard}}, {{prompt:label}}, {{cursor}}")
        e.AddText("xm", "Tags (comma-separated)")
        tags := e.AddEdit("xm w560", IsObject(item) ? item.Tags : "")
        e.AddText("xm", "Allowed apps (comma-separated process names; blank means any app)")
        apps := e.AddEdit("xm w560", IsObject(item) ? item.Apps : "")
        e.AddText("xm", "Folder")
        folderIds := [""]
        folderLabels := ["(Root)"]
        for folder in this.Folders {
            folderIds.Push(folder.Id)
            folderLabels.Push(this.FolderPathLabel(folder.Id))
        }
        folderChoice := e.AddDropDownList("xm w560", folderLabels)
        selectedFolder := IsObject(item) ? item.FolderId : folderId
        for index, candidateId in folderIds
            if candidateId = selectedFolder
                folderChoice.Choose(index)
        modeHint := "no folder default"
        if selectedFolder {
            folderDefaults := this.GetFolderTree().EffectiveDefaults(selectedFolder)
            if folderDefaults.Has("Mode")
                modeHint := folderDefaults["Mode"]
        }
        e.AddText("xm", "Triggers — Kind|Value|Mode (Immediate/Confirm/AfterPause/WhileTypingFast)|Enabled; Autotext may add Case|Position|Before|BeforeChars|After|AfterChars|RemoveTerminator|MinChars")
        triggerText := e.AddEdit("xm w560 r5 WantTab vTriggerLines",
            this.TriggerLines(IsObject(item) ? item.Triggers : [], selectedFolder))
        warningLabel := e.AddText("xm w560 r2 c9A6700", "")
        aiCheck := e.AddCheckbox("xm", "AI phrase")
        aiCheck.Value := IsObject(item) && HasProp(item, "AiPhrase") && item.AiPhrase
        e.AddText("xm w560", "Checking this box allows Generate, Improve, and {{ai}} to send text. There is no extra prompt.")
        e.AddText("xm", "Phrase Body")
        richCheck := e.AddCheckbox("x+12 yp", "Rich text (formatted)")
        hasInitialRtf := (IsObject(item) && HasProp(item, "Rtf") && item.Rtf != "") || (initialRtf != "")
        richCheck.Value := hasInitialRtf
        insertMacroBtn := e.AddButton("x+100 yp-4 w140 h26", "+ Insert Macro...")

        boldBtn := e.AddButton("xm yp+30 w32 h24", "B")
        boldBtn.SetFont("bold")
        italicBtn := e.AddButton("x+4 yp w32 h24", "I")
        italicBtn.SetFont("italic")
        underlineBtn := e.AddButton("x+4 yp w32 h24", "U")
        underlineBtn.SetFont("underline")
        strikeBtn := e.AddButton("x+4 yp w32 h24", "S")
        strikeBtn.SetFont("strike")
        bulletBtn := e.AddButton("x+4 yp w50 h24", "• List")
        colorBtn := e.AddButton("x+4 yp w56 h24", "Color")
        clearBtn := e.AddButton("x+4 yp w50 h24", "Clear")
        e.SetFont("s10", "Segoe UI")

        colorMenu := Menu()
        colorMenu.Add("Black", (*) => (richBody.Focus(), RichText.SetColor(richBody.Hwnd, 0x000000)))
        colorMenu.Add("Blue", (*) => (richBody.Focus(), RichText.SetColor(richBody.Hwnd, 0xD02000)))
        colorMenu.Add("Red", (*) => (richBody.Focus(), RichText.SetColor(richBody.Hwnd, 0x0000D0)))
        colorMenu.Add("Green", (*) => (richBody.Focus(), RichText.SetColor(richBody.Hwnd, 0x008000)))
        colorMenu.Add("Purple", (*) => (richBody.Focus(), RichText.SetColor(richBody.Hwnd, 0x800080)))
        colorMenu.Add("Orange", (*) => (richBody.Focus(), RichText.SetColor(richBody.Hwnd, 0x0080FF)))
        colorMenu.Add("Gray", (*) => (richBody.Focus(), RichText.SetColor(richBody.Hwnd, 0x707070)))
        colorBtn.OnEvent("Click", (*) => colorMenu.Show())

        body := e.AddEdit("xm yp+30 w560 r12 WantTab vBody", IsObject(item) ? item.Text : initialText)
        body.GetPos(&bx, &by, &bw, &bh)
        richBody := e.AddCustom("ClassRICHEDIT50W x" bx " y" by " w" bw " h" bh " +0x4 +0x1000 +0x10000")

        startingRtf := (IsObject(item) && HasProp(item, "Rtf") && item.Rtf != "") ? item.Rtf : initialRtf
        if startingRtf
            RichText.SetRtf(richBody.Hwnd, IsObject(item) ? item.Text : initialText, startingRtf)
        else
            ControlSetText(IsObject(item) ? item.Text : initialText, richBody)

        SyncRichControls(*) {
            isRich := !!richCheck.Value
            for btn in [boldBtn, italicBtn, underlineBtn, strikeBtn, bulletBtn, colorBtn, clearBtn]
                btn.Enabled := isRich
            if isRich {
                if body.Visible {
                    ControlSetText(body.Value, richBody)
                    body.Visible := false
                    richBody.Visible := true
                    richBody.Focus()
                }
            } else {
                if richBody.Visible {
                    body.Value := ControlGetText(richBody)
                    richBody.Visible := false
                    body.Visible := true
                    body.Focus()
                }
            }
        }
        richCheck.OnEvent("Click", SyncRichControls)

        boldBtn.OnEvent("Click", (*) => (richBody.Focus(), RichText.ToggleBold(richBody.Hwnd), NoteBodyChange()))
        italicBtn.OnEvent("Click", (*) => (richBody.Focus(), RichText.ToggleItalic(richBody.Hwnd), NoteBodyChange()))
        underlineBtn.OnEvent("Click", (*) => (richBody.Focus(), RichText.ToggleUnderline(richBody.Hwnd), NoteBodyChange()))
        strikeBtn.OnEvent("Click", (*) => (richBody.Focus(), RichText.ToggleStrikeout(richBody.Hwnd), NoteBodyChange()))
        bulletBtn.OnEvent("Click", (*) => (richBody.Focus(), RichText.ToggleBullet(richBody.Hwnd), NoteBodyChange()))
        clearBtn.OnEvent("Click", (*) => (richBody.Focus(), RichText.ClearFormatting(richBody.Hwnd), NoteBodyChange()))

        if hasInitialRtf {
            body.Visible := false
            richBody.Visible := true
        } else {
            richBody.Visible := false
            body.Visible := true
            for btn in [boldBtn, italicBtn, underlineBtn, strikeBtn, bulletBtn, colorBtn, clearBtn]
                btn.Enabled := false
        }
        macroMenu := Menu()
        macroMenu.Add("Date (YYYY-MM-DD)", (*) => InsertMacroText("{{date}}"))
        macroMenu.Add("Date (Custom format)", (*) => InsertMacroText("{{date:format=yyyy-MM-dd}}"))
        macroMenu.Add("Date (Offset +7 days)", (*) => InsertMacroText("{{date:format=yyyy-MM-dd|offset=+7d}}"))
        macroMenu.Add("Time (HH:mm)", (*) => InsertMacroText("{{time}}"))
        macroMenu.Add("Clipboard text", (*) => InsertMacroText("{{clipboard}}"))
        macroMenu.Add("Cursor position", (*) => InsertMacroText("{{cursor}}"))
        macroMenu.Add("Input prompt", (*) => InsertMacroText("{{prompt:Field Name|default=}}"))
        macroMenu.Add("Interactive Form...", (*) => InsertMacroText("{{form:title=Details|name=Name|notes=Notes}}"))
        macroMenu.Add("Nested phrase", (*) => InsertMacroText("{{phrase:Phrase Name}}"))
        macroMenu.Add("Random alternative", (*) => InsertMacroText("{{random:Option A|Option B|Option C}}"))
        macroMenu.Add("Variable (Set & Get)", (*) => InsertMacroText("{{set:var=value}}{{get:var}}"))
        macroMenu.Add("Conditional (If/Else)", (*) => InsertMacroText("{{if:condition,expected,ThenText,ElseText}}"))
        macroMenu.Add("Loop (Each)", (*) => InsertMacroText("{{each:item,A|B|C,• {{get:item}}`n}}"))
        macroMenu.Add("Transform (Uppercase)", (*) => InsertMacroText("{{process:text,uppercase}}"))
        macroMenu.Add("Math calculation", (*) => InsertMacroText("{{calc:100 * 1.15}}"))
        macroMenu.Add("AI instruction", (*) => InsertMacroText("{{ai:instruction|{{clipboard}}}}"))
        insertMacroBtn.OnEvent("Click", (*) => macroMenu.Show())
        if !aiCheck.Value
            macroMenu.Disable("AI instruction")

        InsertMacroText(str) {
            targetCtrl := richCheck.Value ? richBody : body
            targetCtrl.Focus()
            DllCall("user32\SendMessageW", "Ptr", targetCtrl.Hwnd, "UInt", 0xC2, "Ptr", 1, "WStr", str)
            NoteBodyChange()
        }
        triggerText.OnEvent("Change", (*) => UpdateTriggerWarnings())
        body.OnEvent("Change", NoteBodyChange)
        name.OnEvent("Change", (*) => this.NoteEditorTyping())
        errorLabel := e.AddText("xm w560 r2 cB42318", "")
        generateButton := e.AddButton("xm w110", "Generate")
        improveButton := e.AddButton("x+8 w110", "Improve")
        previewButton := e.AddButton("x+8 w130", "Preview result")
        generateButton.Enabled := aiCheck.Value
        improveButton.Enabled := aiCheck.Value
        aiCheck.OnEvent("Click", SyncAiControls)
        generateButton.OnEvent("Click", (*) => this.GeneratePhraseDraft(name, richCheck.Value ? richBody : body, errorLabel))
        improveButton.OnEvent("Click", (*) => this.ImprovePhraseSelection(richCheck.Value ? richBody : body, errorLabel))
        previewButton.OnEvent("Click", (*) => this.PreviewTemplate(richCheck.Value ? ControlGetText(richBody) : body.Value, aiCheck.Value))
        saveButton := e.AddButton("xm w130 Default vSavePhrase", "Save phrase")
        saveButton.OnEvent("Click", SavePhraseClick)
        e.AddButton("x+10 w100", "Cancel").OnEvent("Click", (*) => this.ClosePhraseEditor(e))
        e.OnEvent("Escape", (*) => this.ClosePhraseEditor(e))
        e.OnEvent("Close", (*) => this.ClosePhraseEditor(e))
        this.AiUndo := []
        this.AiEditorHwnd := e.Hwnd
        this.AiEditorName := name
        this.AiEditorBody := body
        SyncAiControls()
        UpdateTriggerWarnings()
        e.Show()
        SyncAiControls(*) {
            enabled := !!aiCheck.Value
            generateButton.Enabled := enabled
            improveButton.Enabled := enabled
            try {
                if enabled
                    macroMenu.Enable("AI instruction")
                else
                    macroMenu.Disable("AI instruction")
            }
        }
        SavePhraseClick(*) {
            try {
                chosenFolder := folderIds[folderChoice.Value]
                editedTriggers := this.ParseTriggerLines(triggerText.Value,
                    IsObject(item) ? item.Triggers : [], chosenFolder)
                editedAbbr := PhraseModel.FirstAutotext(editedTriggers)
                priorAbbr := IsObject(item) ? item.Abbr : ""
                if Trim(abbr.Value) != priorAbbr
                    editedAbbr := Trim(abbr.Value)
                saveText := richCheck.Value ? ControlGetText(richBody) : body.Value
                saveRtf := richCheck.Value ? RichText.GetRtf(richBody.Hwnd) : ""
                this.UpsertPhrase(name.Value, editedAbbr, saveText, IsObject(item) ? item.Id : "",
                    tags.Value, apps.Value, chosenFolder, editedTriggers, aiCheck.Value, saveRtf)
                this.RefreshFolderChoices()
                this.ClosePhraseEditor(e)
            } catch as err {
                errorLabel.Text := err.Message
            }
        }
        NoteBodyChange(*) {
            UpdateTriggerWarnings()
            this.NoteEditorTyping()
        }
        UpdateTriggerWarnings(*) {
            warnings := []
            try draftTriggers := this.ParseTriggerLines(triggerText.Value,
                IsObject(item) ? item.Triggers : [], selectedFolder)
            catch {
                warningLabel.Text := ""
                return
            }
            otherPhrases := []
            for candidate in this.Phrases
                if !IsObject(item) || candidate.Id != item.Id
                    otherPhrases.Push(candidate)
            draft := {Id: IsObject(item) ? item.Id : "draft", Triggers: draftTriggers}
            otherPhrases.Push(draft)
            currentBodyText := richCheck.Value ? ControlGetText(richBody) : body.Value
            for trigger in draftTriggers
                if trigger.Kind = "Autotext" {
                    for warning in TriggerEngine.ConflictWarnings(trigger, otherPhrases)
                        warnings.Push(warning)
                    for warning in TriggerEngine.SmartCaseWarnings(trigger, currentBodyText, otherPhrases)
                        warnings.Push(warning)
                }
            warningLabel.Text := warnings.Length ? "Warning: " FolderTree.Join(warnings, " ") : ""
        }
    }
    TriggerLines(triggers, folderId := "") {
        text := ""
        defaults := folderId ? this.GetFolderTree().EffectiveDefaults(folderId) : Map()
        for trigger in triggers {
            mode := defaults.Has("Mode") && trigger.Mode = defaults["Mode"] ? "" : trigger.Mode
            line := trigger.Kind . "|" . trigger.Value . "|" . mode . "|" . (trigger.Enabled ? "true" : "false")
            if trigger.Kind = "Autotext" {
                options := trigger.Options
                line .= "|" . (options.Has("CaseMode") ? options["CaseMode"] : "Exact")
                    . "|" . (options.Has("Position") ? options["Position"] : "Start")
                    . "|" . (options.Has("Before") ? options["Before"] : "None")
                    . "|" . (options.Has("BeforeChars") ? options["BeforeChars"] : "")
                    . "|" . (options.Has("After") ? options["After"] : "None")
                    . "|" . (options.Has("AfterChars") ? options["AfterChars"] : "")
                    . "|" . (options.Has("RemoveTerminator") && options["RemoveTerminator"] ? "true" : "false")
                    . "|" . (options.Has("MinChars") ? options["MinChars"] : "1")
            }
            text .= (text ? "`n" : "") line
        }
        return text
    }
    ParseTriggerLines(text, existing, folderId := "") {
        triggers := []
        lines := StrSplit(StrReplace(text, "`r", ""), "`n")
        for index, line in lines {
            if !Trim(line)
                continue
            fields := StrSplit(line, "|")
            if fields.Length != 4 && fields.Length != 12
                throw Error("Use Kind|Value|Mode|Enabled; Autotext may append eight option fields.")
            enabled := StrLower(Trim(fields[4]))
            if enabled != "true" && enabled != "false"
                throw Error("Trigger Enabled must be true or false.")
            prior := 0
            for candidate in existing
                if candidate.Kind = Trim(fields[1]) && candidate.Value = Trim(fields[2]) {
                    prior := candidate
                    break
                }
            if !prior && index <= existing.Length && existing[index].Kind = Trim(fields[1])
                prior := existing[index]
            id := IsObject(prior) ? prior.Id : ""
            options := IsObject(prior) ? prior.Options : Map()
            if fields.Length = 12 {
                caseMode := Trim(fields[5])
                position := Trim(fields[6])
                before := Trim(fields[7])
                after := Trim(fields[9])
                removeTerminator := StrLower(Trim(fields[11]))
                minChars := Trim(fields[12])
                if caseMode != "Exact" && caseMode != "SmartCase"
                    throw Error("Autotext Case must be Exact or SmartCase.")
                if !RegExMatch(position, "^(Start|End|Middle|Entire)$")
                    throw Error("Autotext Position must be Start, End, Middle, or Entire.")
                if !RegExMatch(before, "^(None|Any|Alphanumeric|CharacterSet|Incremental)$")
                    throw Error("Autotext Before rule is invalid.")
                if !RegExMatch(after, "^(None|Any|Alphanumeric|CharacterSet|Incremental)$")
                    throw Error("Autotext After rule is invalid.")
                if removeTerminator != "true" && removeTerminator != "false"
                    throw Error("RemoveTerminator must be true or false.")
                if !RegExMatch(minChars, "^\d+$") || Integer(minChars) < 1 || Integer(minChars) > 32
                    throw Error("MinChars must be from 1 to 32.")
                options["CaseMode"] := caseMode
                options["Position"] := position
                options["Before"] := before
                options["BeforeChars"] := fields[8]
                options["After"] := after
                options["AfterChars"] := fields[10]
                options["RemoveTerminator"] := removeTerminator = "true"
                options["MinChars"] := Integer(minChars)
            }
            mode := Trim(fields[3])
            triggers.Push(PhraseModel.NormalizeTrigger({Id: id, Kind: Trim(fields[1]),
                Value: Trim(fields[2]), Mode: mode, Enabled: enabled = "true", Options: options}))
        }
        return triggers
    }
    DeletePhrase(*) {
        p := this.SelectedPhrase()
        if !IsObject(p) || MsgBox("Delete phrase '" p.Name "'?", "PhraseBoard", "YesNo") != "Yes"
            return
        old := this.Phrases.Clone()
        for index, item in this.Phrases
            if p.Id = item.Id {
                this.Phrases.RemoveAt(index)
                break
            }
        try this.SavePhrases()
        catch {
            this.Phrases := old
            this.Notify("Could not save phrase deletion.")
            return
        }
        this.RegisterPhrases()
        this.RefreshPhrases()
    }
    SetStartup(*) {
        path := A_Startup "\PhraseBoard.lnk"
        try {
            if this.StartCheck.Value
                FileCreateShortcut(A_AhkPath, path, A_ScriptDir, '"' A_ScriptFullPath '"', "PhraseBoard clipboard and phrases")
            else if FileExist(path)
                FileDelete(path)
        } catch {
            this.StartCheck.Value := !!FileExist(path)
            this.Notify("Could not change the startup shortcut.")
        }
    }
    BuildTray() {
        A_IconTip := "PhraseBoard - clipboard and phrases"
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Clipboard history", (*) => this.Show(1))
        A_TrayMenu.Add("Phrases", (*) => this.Show(2))
        A_TrayMenu.Add("Pause / resume history", (*) => this.TogglePause())
        A_TrayMenu.Add("Settings", (*) => this.Show(3))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Exit PhraseBoard", (*) => ExitApp())
        A_TrayMenu.Default := "Clipboard history"
    }
}
