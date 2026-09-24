#Requires AutoHotkey v2.0
#SingleInstance Force
#Include lib\PhraseBoardApp.ahk

try {
    Persistent
    app := PhraseBoardApp(EnvGet("LOCALAPPDATA") "\PhraseBoard")
    app.RegisterShortcuts()
    app.BuildTray()
    app.Show()
} catch as err {
    MsgBox("PhraseBoard could not start.`n`n" err.Message, "PhraseBoard", "Iconx")
    ExitApp(1)
}
