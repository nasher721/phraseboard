#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\PhraseBoardApp.ahk

if EnvGet("PHRASEBOARD_PARSE_ONLY") = "1"
    ExitApp(0)

results := []
original := ClipboardAll()
directory := A_Temp "\PhraseBoard-test-" A_TickCount
app := 0
host := 0
try {
    store := SecureStore(directory)
    legacyRow := "legacy-migration`t" SecureStore.Encode("Migrated phrase")
        . "`t" SecureStore.Encode(";legacy") "`t" SecureStore.Encode("From old storage")
        . "`t" SecureStore.Encode("migration,test") "`t1`t5`t" SecureStore.Encode("notepad.exe")
    store.Write("phrases.dat", legacyRow)
    Assert(PhraseLibrary.Load(store).Phrases[1].Text = "From old storage",
        "Legacy phrase file is readable before migration")
    secret := "Private test text - " Chr(0x03A9) "`nSecond line"
    store.Write("check.dat", secret)
    Assert(store.Read("check.dat") = secret, "DPAPI Unicode round trip")
    raw := FileRead(directory "\check.dat", "RAW")
    Assert(raw.Size > StrLen(secret), "Stored data is an encrypted binary blob")
    Assert(SecureStore.Decode(SecureStore.Encode(secret), true) = secret, "Base64 Unicode round trip")

    app := PhraseBoardApp(directory)
    app.RegisterShortcuts()
    Assert(app.Phrases.Length = 1 && app.Phrases[1].Favorite
        && app.Phrases[1].Tags = "migration,test" && app.Phrases[1].Apps = "notepad.exe",
        "App loads all legacy phrase metadata")
    app.SavePhrases()
    Assert(StrSplit(store.Read("phrases.dat"), "`n")[1] = "PB3",
        "Saving a migrated library writes the PB3 format")
    app.Phrases := []
    app.SavePhrases()
    app.RegisterPhrases()
    A_Clipboard := "First synthetic copy"
    Sleep(250)
    Assert(app.History.Length = 1, "Clipboard monitor captures a real Windows copy")
    A_Clipboard := "Second synthetic copy"
    Sleep(250)
    Assert(app.History.Length = 2, "Second copy retained")
    app.Capture()
    Assert(app.History.Length = 2, "Identical clipboard not duplicated")
    app.TogglePause()
    A_Clipboard := "Do not save this"
    Sleep(200)
    Assert(app.History.Length = 2, "Pause prevents capture")
    app.TogglePause()

    rich := SetRichClipboard("Bold sample", "{\rtf1\ansi\b Bold sample\b0}")
    Sleep(250)
    Assert(app.History[1].Text = "Bold sample", "Rich text captured with readable preview")
    savedRich := app.History[1]
    app.Search.Value := "bold"
    app.RefreshHistory()
    Assert(app.HistoryRows.Length = 1, "History search")
    app.TogglePin()
    Assert(savedRich.Pinned, "Pin persists")

    p := app.UpsertPhrase("Signature", ";pbsig", "Kind regards,`nExample User")
    Assert(app.Phrases.Length = 1, "Create phrase")
    shared := app.UpsertPhrase("Shared signature", ";pbsig", "Alternate signature")
    sharedMatches := PhraseModel.FindPhrasesByTrigger("Autotext", ";pbsig", app.Phrases)
    Assert(sharedMatches.Length = 2, "Shared autotext remains attached to every matching phrase")
    for index, phrase in app.Phrases
        if phrase.Id = shared.Id {
            app.Phrases.RemoveAt(index)
            break
        }
    app.SavePhrases()
    app.RegisterPhrases()
    app.UpsertPhrase("Signature", ";pbsig", "Updated signature", p.Id)
    Assert(app.Phrases.Length = 1 && app.Phrases[1].Text = "Updated signature", "Edit phrase without duplication")
    folder := {Id: "integration-folder", ParentId: "", Name: "Integration", CreatedAt: A_Now,
        Triggers: [], TriggerDefaults: Map("Mode", "Confirm")}
    app.Folders.Push(folder)
    savedPhrase := app.FindPhrase(p.Id)
    savedPhrase.Tags := "work,test"
    savedPhrase.Favorite := true
    savedPhrase.Uses := 6
    savedPhrase.Apps := "AutoHotkey64.exe"
    savedPhrase.FolderId := folder.Id
    savedPhrase.Triggers.Push(PhraseModel.NormalizeTrigger({Kind: "SmartComplete", Value: "signature",
        Mode: "Confirm", Options: Map("MinChars", "2")}))
    app.SavePhrases()
    Assert(app.ResolveTokens("{{date}}") = FormatTime(, "yyyy-MM-dd"), "Date token")

    restoredApp := PhraseBoardApp(directory, false)
    Assert(restoredApp.History.Length = 3 && restoredApp.History[1].Pinned, "Encrypted history survives reload with pin")
    reloadedPhrase := restoredApp.FindPhrase(p.Id)
    Assert(restoredApp.Phrases.Length = 1 && reloadedPhrase.Text = "Updated signature"
        && reloadedPhrase.Tags = "work,test" && reloadedPhrase.Favorite && reloadedPhrase.Uses = 6
        && reloadedPhrase.Apps = "AutoHotkey64.exe" && reloadedPhrase.FolderId = folder.Id
        && reloadedPhrase.Triggers.Length = 2 && reloadedPhrase.Triggers[2].Kind = "SmartComplete",
        "Phrase metadata, folder, and triggers survive encrypted reload")
    app.WriteClipboard(restoredApp.History[1].Data)
    Assert(GetRtf() = "{\rtf1\ansi\b Bold sample\b0}", "Exact RTF survives encrypted storage")
    restoredApp.Stop()
    ; Re-register so this live app owns hotstring callbacks after the restoredApp check.
    app.RegisterPhrases()

    host := Gui(, "PhraseBoard synthetic paste destination")
    host.SetFont("s11", "Segoe UI")
    inputCtrl := host.AddEdit("w600 r5 WantTab")
    DllCall("LoadLibrary", "Str", "Msftedit.dll", "Ptr")
    richEdit := host.AddCustom("ClassRICHEDIT50W w600 h120 +0x4 +0x10000")
    host.Show()
    WinActivate("ahk_id " host.Hwnd)
    WinWaitActive("ahk_id " host.Hwnd, , 2)
    inputCtrl.Focus()

    app.WriteClipboard("Previous clipboard")
    app.PasteValue("Plain " Chr(0x03A9) "`nline two", host.Hwnd)
    Assert(InStr(inputCtrl.Value, "Plain " Chr(0x03A9)) && InStr(inputCtrl.Value, "line two"), "Plain multiline paste into actual Windows edit control")
    Assert(A_Clipboard = "Previous clipboard", "Previous clipboard restored after paste")

    richEdit.Focus()
    app.PasteValue(savedRich.Data, host.Hwnd)
    Assert(InStr(ControlGetText(richEdit), "Bold sample"), "Original-format paste reaches RichEdit")
    SendMessage(0xB1, 0, 4, richEdit) ; EM_SETSEL
    clipFormat := Buffer(116, 0)
    NumPut("UInt", 116, clipFormat)
    SendMessage(0x43A, 1, clipFormat.Ptr, richEdit) ; EM_GETCHARFORMAT, SCF_SELECTION
    Assert(NumGet(clipFormat, 8, "UInt") & 1, "RichEdit receives bold formatting")

    inputCtrl.Value := ""
    inputCtrl.Focus()
    app.WriteClipboard(savedRich.Data)
    app.PasteCurrentPlain()
    Assert(inputCtrl.Value = "Bold sample", "Plain-paste shortcut path strips RTF")
    Assert(GetRtf() != "", "Plain paste restores original rich clipboard")

    inputCtrl.Value := ""
    inputCtrl.Focus()
    app.WriteClipboard("Previous clipboard")
    SetTimer(() => (A_Clipboard := "A newer user copy"), -250)
    app.PasteValue("Paste while user copies", host.Hwnd)
    Assert(A_Clipboard = "A newer user copy", "Concurrent user copy is never overwritten by restoration")

    inputCtrl.Value := ""
    inputCtrl.Focus()
    SendLevel(1)
    SendEvent("Sig")
    Sleep(150)
    Assert(app.SmartCompleter.Visible && app.SmartCompleter.QueryText = "Sig"
        && WinActive("ahk_id " host.Hwnd), "SmartComplete shows case-sensitive suggestions without taking target focus")
    SendEvent("n")
    Sleep(100)
    Assert(app.SmartCompleter.QueryText = "Sign", "SmartComplete narrows as more characters are typed")
    SendEvent("{Enter}")
    Sleep(200)
    SendLevel(0)
    Assert(inputCtrl.Value = "Updated signature", "SmartComplete acceptance replaces the query in the invoking app")

    inputCtrl.Value := ""
    inputCtrl.Focus()
    Hotstring("Reset")
    SendLevel(1)
    SendEvent(";pbsig ")
    Sleep(250)
    SendLevel(0)
    Assert(inputCtrl.Value = "Updated signature ", "Real keyboard abbreviation expansion preserves its ending space")

    inputCtrl.Value := ""
    inputCtrl.Focus()
    Hotstring("Reset")
    SendLevel(1)
    SendEvent(";pbsig,")
    Sleep(150)
    SendLevel(0)
    Assert(inputCtrl.Value = "Updated signature,", "Autotext preserves trailing punctuation")
    inputCtrl.Value := ""
    inputCtrl.Focus()
    Hotstring("Reset")
    SendLevel(1)
    SendEvent(";pbsig{Enter}")
    Sleep(150)
    SendLevel(0)
    Assert(InStr(inputCtrl.Value, "Updated signature`r`n"), "Autotext preserves an Enter terminator")
    inputCtrl.Value := ""
    inputCtrl.Focus()
    Hotstring("Reset")
    SendLevel(1)
    SendEvent(";pbsig{Tab}")
    Sleep(150)
    SendLevel(0)
    Assert(InStr(inputCtrl.Value, "Updated signature`t"), "Autotext preserves a Tab terminator")

    savedBody := app.FindPhrase(p.Id).Text
    savedTriggers := app.FindPhrase(p.Id).Triggers.Clone()
    caseTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "maxcase",
        Options: Map("CaseMode", "SmartCase")})
    wholeTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: ";whole",
        Options: Map("Position", "Entire")})
    trimTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: ";trim",
        Options: Map("RemoveTerminator", true)})
    pauseTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: ";pause", Mode: "AfterPause"})
    fastTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: ";fast", Mode: "WhileTypingFast"})
    app.FindPhrase(p.Id).Text := "maximum"
    for trigger in [caseTrigger, wholeTrigger, trimTrigger, pauseTrigger, fastTrigger]
        app.FindPhrase(p.Id).Triggers.Push(trigger)
    app.SavePhrases()
    app.RegisterPhrases()

    for casePair in [["maxcase", "maximum"], ["Maxcase", "Maximum"], ["MAXCASE", "MAXIMUM"]] {
        typedCase := casePair[1], expectedCase := casePair[2]
        inputCtrl.Value := ""
        inputCtrl.Focus()
        Hotstring("Reset")
        SendLevel(1)
        SendEvent(typedCase " ")
        Sleep(120)
        SendLevel(0)
        Assert(inputCtrl.Value = expectedCase " ", "SmartCase expansion conforms typed case: " typedCase)
    }
    inputCtrl.Value := ""
    inputCtrl.Focus()
    Hotstring("Reset")
    SendLevel(1)
    SendEvent("x;whole ")
    Sleep(120)
    SendLevel(0)
    Assert(inputCtrl.Value = "x;whole ", "entire-word boundary rejection restores the abbreviation and space")
    inputCtrl.Value := ""
    inputCtrl.Focus()
    Hotstring("Reset")
    SendLevel(1)
    SendEvent(";trim ")
    Sleep(120)
    SendLevel(0)
    Assert(inputCtrl.Value = "maximum", "RemoveTerminator omits only the selected trailing space")
    inputCtrl.Value := ""
    inputCtrl.Focus()
    Hotstring("Reset")
    SendLevel(1)
    SendEvent(";pause ")
    Sleep(350)
    SendLevel(0)
    Assert(inputCtrl.Value = "maximum ", "AfterPause mode waits before expanding")
    inputCtrl.Value := ""
    inputCtrl.Focus()
    Hotstring("Reset")
    SendLevel(1)
    SendEvent(";fast ")
    Sleep(120)
    SendLevel(0)
    Assert(inputCtrl.Value = "maximum ", "WhileTypingFast mode expands during rapid typing")
    inputCtrl.Value := ""
    inputCtrl.Focus()
    Hotstring("Reset")
    SendLevel(1)
    SendEvent(";fast")
    Sleep(350)
    SendEvent(" ")
    Sleep(100)
    SendLevel(0)
    Assert(inputCtrl.Value = ";fast ", "WhileTypingFast mode dismisses after a pause")

    app.FindPhrase(p.Id).Text := savedBody
    app.FindPhrase(p.Id).Triggers := savedTriggers
    app.SavePhrases()
    app.RegisterPhrases()
    inputCtrl.Value := ""
    inputCtrl.Focus()

    app.Show(1)
    app.Search.Value := "bold"
    app.RefreshHistory()
    Assert(app.Target = host.Hwnd, "Picker remembers original destination")
    app.PasteHistory(true)
    Assert(InStr(inputCtrl.Value, "Bold sample"), "History picker pastes to original destination")

    app.Show(2)
    app.EditPhrase(app.Phrases[1])
    editor := app.Editor
    editor["TriggerLines"].Value := "Autotext|;pbsig|Immediate|true`nSmartComplete|signature|Confirm|true"
    editor["Body"].Value := ""
    editor["Body"].Focus()
    Hotstring("Reset")
    SendLevel(1)
    SendEvent(";pbsig ")
    Sleep(200)
    SendLevel(0)
    Assert(editor["Body"].Value = ";pbsig ", "Abbreviations stay literal inside phrase editor")
    editor["Body"].Value := "Saved through the editor"
    ControlClick(editor["SavePhrase"])
    Sleep(200)
    Assert(app.Phrases[1].Text = "Saved through the editor" && app.Phrases[1].Triggers.Length = 2
        && app.Phrases[1].Triggers[2].Kind = "SmartComplete", "Phrase editor saves multiple typed triggers")
    app.TogglePause()
    restoredApp := PhraseBoardApp(directory, false)
    Assert(restoredApp.Paused, "Paused capture survives restart")
    Assert(restoredApp.Phrases[1].Text = "Saved through the editor", "GUI edits survive encrypted reload")
    restoredApp.Stop()
    app.TogglePause()
    app.Hide()

    app.MaxEntries := 3
    Loop 5 {
        app.WriteClipboard("Retention " A_Index)
        app.AddClip(A_Clipboard, ClipboardAll())
    }
    Assert(app.History.Length = 3, "Retention limit enforced")
    pinnedKept := false
    for clip in app.History
        if clip.Id = savedRich.Id
            pinnedKept := true
    Assert(pinnedKept, "Pinned clip survives retention")

    app.ClearHistory(false)
    Assert(app.History.Length = 0 && app.Phrases.Length = 1, "Clear history keeps phrase library")
    count := 0
    Loop Files directory "\*.clip"
        count += 1
    Assert(count = 0, "Clear history removes encrypted clip files")
    app.Hide()
    FileAppend("ALL " results.Length " INTEGRATION TESTS PASSED`n", "*")
    code := 0
} catch as err {
    FileAppend("FAIL: " err.Message "`n" err.Stack "`n", "*")
    code := 1
} finally {
    if IsObject(app) {
        app.Paused := true
        OnClipboardChange(app.ClipCallback, 0)
        SetTimer(app.CaptureCallback, 0)
        app.WriteClipboard(original)
    } else A_Clipboard := original
    if IsObject(host)
        host.Destroy()
}
ExitApp(code)

Assert(condition, name) {
    global results
    if !condition
        throw Error(name)
    results.Push(name)
    FileAppend("PASS: " name "`n", "*")
}
SetRichClipboard(text, rtf) {
    A_Clipboard := text
    clipFormat := DllCall("RegisterClipboardFormat", "Str", "Rich Text Format", "UInt")
    if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
        throw OSError()
    try {
        bytes := StrPut(rtf, "CP0")
        handle := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", bytes, "Ptr")
        ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
        StrPut(rtf, ptr, bytes, "CP0")
        DllCall("GlobalUnlock", "Ptr", handle)
        if !DllCall("SetClipboardData", "UInt", clipFormat, "Ptr", handle, "Ptr")
            throw OSError()
    } finally DllCall("CloseClipboard")
    return ClipboardAll()
}
GetRtf() {
    clipFormat := DllCall("RegisterClipboardFormat", "Str", "Rich Text Format", "UInt")
    if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
        throw OSError()
    try {
        handle := DllCall("GetClipboardData", "UInt", clipFormat, "Ptr")
        if !handle
            return ""
        ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
        try return StrGet(ptr, "CP0")
        finally DllCall("GlobalUnlock", "Ptr", handle)
    } finally DllCall("CloseClipboard")
}
