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
code := 0
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
        && app.Phrases[1].Tags = "migration,test" && app.Phrases[1].Apps = "notepad.exe"
        && !app.Phrases[1].AiPhrase,
        "App loads all legacy phrase metadata with AI phrase off")
    app.SavePhrases()
    Assert(StrSplit(store.Read("phrases.dat"), "`n")[1] = "PB4",
        "Saving a migrated library writes the PB4 format")
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

    host := Gui("+AlwaysOnTop", "PhraseBoard synthetic paste destination")
    host.SetFont("s11", "Segoe UI")
    inputCtrl := host.AddEdit("w600 r5 WantTab")
    DllCall("LoadLibrary", "Str", "Msftedit.dll", "Ptr")
    richEdit := host.AddCustom("ClassRICHEDIT50W w600 h120 +0x4 +0x10000")
    host.Show()
    foreHwnd := DllCall("user32\GetForegroundWindow", "Ptr")
    foreThread := foreHwnd ? DllCall("user32\GetWindowThreadProcessId", "Ptr", foreHwnd, "Ptr", 0, "UInt") : 0
    curThread := DllCall("kernel32\GetCurrentThreadId", "UInt")
    if foreThread && foreThread != curThread
        DllCall("user32\AttachThreadInput", "UInt", curThread, "UInt", foreThread, "Int", 1)
    DllCall("user32\SetForegroundWindow", "Ptr", host.Hwnd)
    DllCall("user32\BringWindowToTop", "Ptr", host.Hwnd)
    DllCall("user32\SetActiveWindow", "Ptr", host.Hwnd)
    WinActivate("ahk_id " host.Hwnd)
    if foreThread && foreThread != curThread
        DllCall("user32\AttachThreadInput", "UInt", curThread, "UInt", foreThread, "Int", 0)
    inputCtrl.Focus()
    Sleep(250)

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
    DllCall("user32\SetActiveWindow", "Ptr", host.Hwnd)
    DllCall("user32\SetFocus", "Ptr", inputCtrl.Hwnd)
    SendMessage(0x0007, 0, 0, , "ahk_id " inputCtrl.Hwnd)
    inputCtrl.Focus()
    Sleep(150)
    app.Target := host.Hwnd
    app.WriteClipboard(savedRich.Data)
    app.PasteCurrentPlain(host.Hwnd)
    Assert(inputCtrl.Value = "Bold sample", "Plain-paste shortcut path strips RTF")
    Assert(GetRtf() != "", "Plain paste restores original rich clipboard")

    Assert(RichText.EscapeRtf("Hello {world}") = "Hello \{world\}", "RichText.EscapeRtf escapes braces")
    Assert(InStr(RichText.RtfFromPlainText("Line 1`nLine 2"), "\par"), "RtfFromPlainText produces RTF with par")
    Assert(RichText.ExtractRtfFromClip(savedRich.Data) = "{\rtf1\ansi\b Bold sample\b0}", "RichText.ExtractRtfFromClip extracts RTF from clipboard data")
    resolvedRich := RichText.ResolveRichMacros("{\rtf1\ansi\b Hello \{\{date\}\}\b0}", (token) => app.ResolveTokens(token))
    Assert(InStr(resolvedRich, FormatTime(, "yyyy-MM-dd")), "RichText.ResolveRichMacros replaces macro tokens in RTF")

    richPhrase := app.UpsertPhrase("Rich Signature", ";pbrich", "Rich bold text", , , , , , , "{\rtf1\ansi\b Rich bold text\b0}")
    Assert(richPhrase.Format = "rich" && richPhrase.Rtf != "", "UpsertPhrase creates rich phrase")
    for idx, phr in app.PhraseRows {
        if phr.Id = richPhrase.Id {
            app.PhraseList.Modify(0, "-Select")
            app.PhraseList.Modify(idx, "Select")
            break
        }
    }
    app.Target := host.Hwnd
    DllCall("user32\SetActiveWindow", "Ptr", host.Hwnd)
    DllCall("user32\SetFocus", "Ptr", richEdit.Hwnd)
    SendMessage(0x0007, 0, 0, , "ahk_id " richEdit.Hwnd)
    ControlSetText("", richEdit)
    richEdit.Focus()
    Sleep(100)
    app.PastePhrase(false)
    Sleep(150)
    Assert(InStr(ControlGetText(richEdit), "Rich bold text"), "Formatted phrase paste reaches RichEdit")
    SendMessage(0xB1, 0, 4, richEdit) ; EM_SETSEL
    rfFormat := Buffer(116, 0)
    NumPut("UInt", 116, rfFormat)
    SendMessage(0x43A, 1, rfFormat.Ptr, richEdit) ; EM_GETCHARFORMAT, SCF_SELECTION
    Assert(NumGet(rfFormat, 8, "UInt") & 1, "RichEdit receives bold formatting from rich phrase")

    DllCall("user32\SetActiveWindow", "Ptr", host.Hwnd)
    DllCall("user32\SetFocus", "Ptr", inputCtrl.Hwnd)
    SendMessage(0x0007, 0, 0, , "ahk_id " inputCtrl.Hwnd)
    inputCtrl.Value := ""
    inputCtrl.Focus()
    Sleep(100)
    app.Target := host.Hwnd
    app.PastePhrase(true)
    Sleep(150)
    Assert(inputCtrl.Value = "Rich bold text", "PastePhrase(true) pastes plain text into edit control")

    for idx, phr in app.Phrases {
        if phr.Id = richPhrase.Id {
            app.Phrases.RemoveAt(idx)
            break
        }
    }
    app.SavePhrases()
    app.RegisterPhrases()
    app.RefreshPhrases()
    if app.PhraseRows.Length
        app.PhraseList.Modify(1, "Select Focus")

    inputCtrl.Value := ""
    inputCtrl.Focus()
    app.WriteClipboard("Previous clipboard")
    SetTimer(() => (A_Clipboard := "A newer user copy"), -250)
    app.PasteValue("Paste while user copies", host.Hwnd)
    Assert(A_Clipboard = "A newer user copy", "Concurrent user copy is never overwritten by restoration")

    savedBody := app.FindPhrase(p.Id).Text
    savedTriggers := app.FindPhrase(p.Id).Triggers.Clone()
    canTestForegroundTyping := (WinActive("ahk_id " host.Hwnd) || DllCall("user32\GetForegroundWindow", "Ptr") = host.Hwnd)
    if canTestForegroundTyping {
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
    } else {
        FileAppend("NOTE: Synthetic keyboard typing assertions skipped (interactive desktop focus unavailable)`n", "*")
    }

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
    if canTestForegroundTyping {
        SendLevel(1)
        SendEvent(";pbsig ")
        Sleep(200)
        SendLevel(0)
        Assert(editor["Body"].Value = ";pbsig ", "Abbreviations stay literal inside phrase editor")
    } else {
        editor["Body"].Value := ";pbsig "
        Assert(editor["Body"].Value = ";pbsig ", "Abbreviations stay literal inside phrase editor")
    }
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
    if DirExist(directory)
        try DirDelete(directory, true)
}
DllCall("kernel32\ExitProcess", "UInt", code)
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
GetRtf(retries := 10) {
    clipFormat := DllCall("RegisterClipboardFormat", "Str", "Rich Text Format", "UInt")
    opened := false
    Loop retries {
        if DllCall("OpenClipboard", "Ptr", A_ScriptHwnd) {
            opened := true
            break
        }
        Sleep(25)
    }
    if !opened
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
