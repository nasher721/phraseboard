#Requires AutoHotkey v2.0
#Include ..\lib\PhraseBoardApp.ahk
directory := A_Temp "\PhraseBoard-smoke-" A_TickCount
app := 0
code := 0
try {
    store := SecureStore(directory)
    folders := [
        {Id: "smoke-parent", ParentId: "", Name: "Work", CreatedAt: A_Now,
            Triggers: [], TriggerDefaults: Map("Mode", "Confirm")},
        {Id: "smoke-child", ParentId: "smoke-parent", Name: "Personal", CreatedAt: A_Now,
            Triggers: [], TriggerDefaults: Map()}
    ]
    phrases := [{Id: "smoke-phrase", Name: "Sample", Text: "body", FolderId: "smoke-child",
        Triggers: [
            {Id: "smoke-trigger", Kind: "SmartComplete", Value: "sample", Mode: "Confirm"},
            {Id: "smoke-autotext", Kind: "Autotext", Value: ";sample", Mode: "Immediate",
                Options: Map("CaseMode", "SmartCase", "Position", "Entire", "Before", "CharacterSet",
                    "BeforeChars", " #9", "After", "CharacterSet", "AfterChars", " .",
                    "RemoveTerminator", true, "MinChars", 2)}
        ]}]
    PhraseLibrary.Save(store, phrases, folders)
    app := PhraseBoardApp(directory, false)
    if app.FolderPathLabel("smoke-child") != "Work\Personal"
        throw Error("Nested folder controls did not load their hierarchy.")
    inheritedLine := app.TriggerLines(app.Phrases[1].Triggers, "smoke-child")
    parsed := app.ParseTriggerLines(inheritedLine, app.Phrases[1].Triggers, "smoke-child")
    if parsed[1].Mode != ""
        throw Error("Folder-inherited mode was not kept as a non-override.")
    if parsed[2].Options["CaseMode"] != "SmartCase" || parsed[2].Options["Position"] != "Entire"
        || !parsed[2].Options["RemoveTerminator"] || parsed[2].Options["MinChars"] != 2
        || parsed[2].Options["BeforeChars"] != " #9"
        throw Error("Autotext trigger options did not round-trip through the editor.")
    app.EnsureTypingMonitor()
    app.TypedKeyDown(app.TypingHook, 0x41, 0x1E)
    app.TypedCharacter(app.TypingHook, "a")
    app.Stop()
    FileAppend("STARTUP TESTS PASSED`n", "*")
} catch as err {
    if IsObject(app)
        try app.Stop()
    FileAppend(err.Message "`n" err.Stack "`n", "*")
    code := 1
} finally {
    if DirExist(directory)
        DirDelete(directory, true)
}
ExitApp(code)
