#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\HotkeyAdapter.ahk

failures := []

; 1. Normalization tests
Assert(HotkeyAdapter.Normalize("Ctrl+Alt+S") = "^!S", "Normalize converts Ctrl+Alt+S to ^!S")
Assert(HotkeyAdapter.Normalize("Win+Shift+1") = "#+1", "Normalize converts Win+Shift+1 to #+1")
Assert(HotkeyAdapter.Normalize("Command+Option+P") = "#!P", "Normalize maps Mac Command and Option to Win and Alt")
Assert(HotkeyAdapter.Normalize("^!space") = "^!space", "Normalize preserves AHK format")

; 2. Validation tests
v1 := HotkeyAdapter.Validate("Ctrl+Alt+P")
Assert(v1.Valid && v1.Warning = "", "Valid hotkey passes without warnings")

v2 := HotkeyAdapter.Validate("p")
Assert(!v2.Valid, "Bare key without modifiers is rejected")

v3 := HotkeyAdapter.Validate("Ctrl+Shift+V")
Assert(v3.Valid && InStr(v3.Warning, "PhraseBoard Clipboard History"), "Built-in shortcut produces conflict warning")

v4 := HotkeyAdapter.Validate("Win+R")
Assert(v4.Valid && InStr(v4.Warning, "Windows Run"), "System shortcut produces conflict warning")

; 3. Registration test
fired := false
cb := (*) => (fired := true)
registered := HotkeyAdapter.Register("^!F12", cb)
Assert(registered, "Can register hotkey with callback")
HotkeyAdapter.Unregister("^!F12")
Assert(!HotkeyAdapter.RegisteredHotkeys.Has("^!F12"), "Unregister removes hotkey from active registry")

if failures.Length {
    for failure in failures
        FileAppend("FAIL: " failure "`n", "*")
    ExitApp(1)
}
FileAppend("ALL HOTKEY TESTS PASSED`n", "*")
ExitApp(0)

Assert(condition, name) {
    global failures
    if condition
        FileAppend("PASS: " name "`n", "*")
    else
        failures.Push(name)
}
