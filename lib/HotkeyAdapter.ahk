#Requires AutoHotkey v2.0

class HotkeyAdapter {
    static RegisteredHotkeys := Map()

    static Normalize(keyStr) {
        keyStr := Trim(keyStr)
        if keyStr = ""
            return ""

        ; Check if already in AHK modifier prefix format (e.g. ^!s, #+v)
        if RegExMatch(keyStr, "^[#!\^+]+.+$")
            return keyStr

        ; Split by '+' or '-'
        parts := StrSplit(keyStr, ["+", "-"])
        ctrl := false
        alt := false
        shift := false
        win := false
        mainKey := ""

        for part in parts {
            p := StrLower(Trim(part))
            switch p {
                case "ctrl", "control":
                    ctrl := true
                case "alt", "option":
                    alt := true
                case "shift":
                    shift := true
                case "win", "windows", "cmd", "command":
                    win := true
                default:
                    mainKey := Trim(part)
            }
        }

        if mainKey = ""
            return ""

        prefix := ""
        if win
            prefix .= "#"
        if ctrl
            prefix .= "^"
        if alt
            prefix .= "!"
        if shift
            prefix .= "+"

        return prefix . mainKey
    }

    static Validate(keyStr) {
        ahkKey := this.Normalize(keyStr)
        if ahkKey = ""
            return {Valid: false, Message: "Enter a valid key combination (e.g. Ctrl+Alt+S).", AhkKey: ""}

        ; Disallow bare single characters without modifiers
        if !RegExMatch(ahkKey, "^[#!\^+]") {
            return {Valid: false, Message: "Hotkeys must include at least one modifier (Ctrl, Alt, Win, or Shift).", AhkKey: ahkKey}
        }

        ; Conflict warnings
        warning := this.CheckConflict(ahkKey)
        return {Valid: true, Warning: warning, AhkKey: ahkKey}
    }

    static CheckConflict(ahkKey) {
        k := StrLower(ahkKey)
        builtins := Map(
            "^+v", "PhraseBoard Clipboard History",
            "!+v", "PhraseBoard Paste Plain",
            "^!space", "PhraseBoard Phrases Library",
            "^!+h", "PhraseBoard Pause History"
        )
        if builtins.Has(k)
            return "Conflicts with built-in shortcut: " builtins[k]

        systemKeys := Map(
            "#r", "Windows Run",
            "#e", "File Explorer",
            "#d", "Show Desktop",
            "#l", "Lock Screen",
            "!f4", "Close Application",
            "^c", "System Copy",
            "^v", "System Paste",
            "^x", "System Cut",
            "^z", "System Undo",
            "^a", "Select All"
        )
        if systemKeys.Has(k)
            return "Warning: Conflicts with common system shortcut: " systemKeys[k]

        return ""
    }

    static Register(keyStr, callback) {
        ahkKey := this.Normalize(keyStr)
        if ahkKey = ""
            return false

        try {
            Hotkey(ahkKey, callback, "On")
            this.RegisteredHotkeys[ahkKey] := callback
            return true
        } catch as err {
            return false
        }
    }

    static Unregister(keyStr) {
        ahkKey := this.Normalize(keyStr)
        if ahkKey = ""
            return false

        if this.RegisteredHotkeys.Has(ahkKey) {
            try {
                Hotkey(ahkKey, "Off")
            }
            this.RegisteredHotkeys.Delete(ahkKey)
            return true
        }
        return false
    }

    static UnregisterAll() {
        for key, cb in this.RegisteredHotkeys {
            try Hotkey(key, "Off")
        }
        this.RegisteredHotkeys.Clear()
    }
}
