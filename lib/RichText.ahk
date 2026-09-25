#Requires AutoHotkey v2.0

class RichText {
    static LoadedModule := 0
    static RtfFormat := 0

    static Init() {
        if !this.LoadedModule {
            this.LoadedModule := DllCall("LoadLibrary", "Str", "msftedit.dll", "Ptr")
            this.RtfFormat := DllCall("RegisterClipboardFormat", "Str", "Rich Text Format", "UInt")
        }
    }

    static OpenClipboardWithRetry(hwnd := 0, retries := 10) {
        if !hwnd
            hwnd := A_ScriptHwnd
        Loop retries {
            if DllCall("OpenClipboard", "Ptr", hwnd)
                return true
            Sleep(25)
        }
        return false
    }

    static EscapeRtf(str) {
        res := ""
        Loop Parse str {
            code := Ord(A_LoopField)
            if A_LoopField = "\"
                res .= "\\"
            else if A_LoopField = "{"
                res .= "\{"
            else if A_LoopField = "}"
                res .= "\}"
            else if A_LoopField = "`n"
                res .= "\par "
            else if A_LoopField = "`r"
                continue
            else if code > 127
                res .= "\u" (code > 32767 ? code - 65536 : code) "?"
            else
                res .= A_LoopField
        }
        return res
    }

    static RtfFromPlainText(plainText, fontName := "Segoe UI", ptSize := 10) {
        fs := Integer(ptSize * 2)
        escaped := this.EscapeRtf(plainText)
        return "{\rtf1\ansi\deff0 {\fonttbl {\f0 " fontName ";}}\f0\fs" fs " " escaped "}"
    }

    static BuildRichClip(plainText, rtfText) {
        this.Init()
        saved := ClipboardAll()
        if !this.OpenClipboardWithRetry()
            throw OSError()
        try {
            DllCall("EmptyClipboard")
            ; CF_UNICODETEXT = 13
            uBytes := StrPut(plainText, "UTF-16") * 2
            hUnicode := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", uBytes, "Ptr")
            pUnicode := DllCall("GlobalLock", "Ptr", hUnicode, "Ptr")
            StrPut(plainText, pUnicode, "UTF-16")
            DllCall("GlobalUnlock", "Ptr", hUnicode)
            DllCall("SetClipboardData", "UInt", 13, "Ptr", hUnicode)

            ; Rich Text Format
            bytes := StrPut(rtfText, "CP0")
            handle := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", bytes, "Ptr")
            ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
            StrPut(rtfText, ptr, bytes, "CP0")
            DllCall("GlobalUnlock", "Ptr", handle)
            DllCall("SetClipboardData", "UInt", this.RtfFormat, "Ptr", handle)
        } finally DllCall("CloseClipboard")
        richClip := ClipboardAll()
        A_Clipboard := saved
        return richClip
    }

    static ExtractRtfFromClip(clipData) {
        this.Init()
        if !clipData || (IsObject(clipData) && clipData.Size = 0)
            return ""
        saved := ClipboardAll()
        A_Clipboard := clipData
        rtf := ""
        if this.OpenClipboardWithRetry() {
            try {
                handle := DllCall("GetClipboardData", "UInt", this.RtfFormat, "Ptr")
                if handle {
                    ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
                    try rtf := StrGet(ptr, "CP0")
                    finally DllCall("GlobalUnlock", "Ptr", handle)
                }
            } finally DllCall("CloseClipboard")
        }
        A_Clipboard := saved
        return rtf
    }

    static GetRtf(reHwnd) {
        this.Init()
        saved := ClipboardAll()
        selStart := Buffer(4, 0), selEnd := Buffer(4, 0)
        SendMessage(0x00B0, selStart.Ptr, selEnd.Ptr, reHwnd) ; EM_GETSEL
        SendMessage(0x00B1, 0, -1, reHwnd) ; EM_SETSEL all
        SendMessage(0x0301, 0, 0, reHwnd) ; WM_COPY
        SendMessage(0x00B1, NumGet(selStart, "Int"), NumGet(selEnd, "Int"), reHwnd) ; restore sel

        rtf := ""
        if this.OpenClipboardWithRetry() {
            try {
                handle := DllCall("GetClipboardData", "UInt", this.RtfFormat, "Ptr")
                if handle {
                    ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
                    try rtf := StrGet(ptr, "CP0")
                    finally DllCall("GlobalUnlock", "Ptr", handle)
                }
            } finally DllCall("CloseClipboard")
        }
        A_Clipboard := saved
        return rtf
    }

    static SetRtf(reHwnd, plainText, rtfText) {
        this.Init()
        if !rtfText {
            ControlSetText(plainText, reHwnd)
            return
        }
        saved := ClipboardAll()
        if !this.OpenClipboardWithRetry()
            throw OSError()
        try {
            DllCall("EmptyClipboard")
            uBytes := StrPut(plainText, "UTF-16") * 2
            hUnicode := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", uBytes, "Ptr")
            pUnicode := DllCall("GlobalLock", "Ptr", hUnicode, "Ptr")
            StrPut(plainText, pUnicode, "UTF-16")
            DllCall("GlobalUnlock", "Ptr", hUnicode)
            DllCall("SetClipboardData", "UInt", 13, "Ptr", hUnicode)

            bytes := StrPut(rtfText, "CP0")
            handle := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", bytes, "Ptr")
            ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
            StrPut(rtfText, ptr, bytes, "CP0")
            DllCall("GlobalUnlock", "Ptr", handle)
            DllCall("SetClipboardData", "UInt", this.RtfFormat, "Ptr", handle)
        } finally DllCall("CloseClipboard")

        SendMessage(0x00B1, 0, -1, reHwnd) ; EM_SETSEL all
        SendMessage(0x0302, 0, 0, reHwnd) ; WM_PASTE
        A_Clipboard := saved
    }

    static ToggleCharEffect(reHwnd, mask, effect) {
        cf := Buffer(116, 0)
        NumPut("UInt", 116, cf, 0)
        SendMessage(0x043A, 1, cf.Ptr, reHwnd) ; EM_GETCHARFORMAT, SCF_SELECTION
        currEffects := NumGet(cf, 8, "UInt")
        newEffects := (currEffects & effect) ? 0 : effect

        cfSet := Buffer(116, 0)
        NumPut("UInt", 116, cfSet, 0)
        NumPut("UInt", mask, cfSet, 4)
        NumPut("UInt", newEffects, cfSet, 8)
        SendMessage(0x0444, 1, cfSet.Ptr, reHwnd) ; EM_SETCHARFORMAT, SCF_SELECTION
    }

    static ToggleBold(reHwnd) => this.ToggleCharEffect(reHwnd, 1, 1)        ; CFM_BOLD = 1, CFE_BOLD = 1
    static ToggleItalic(reHwnd) => this.ToggleCharEffect(reHwnd, 2, 2)      ; CFM_ITALIC = 2, CFE_ITALIC = 2
    static ToggleUnderline(reHwnd) => this.ToggleCharEffect(reHwnd, 4, 4)   ; CFM_UNDERLINE = 4, CFE_UNDERLINE = 4
    static ToggleStrikeout(reHwnd) => this.ToggleCharEffect(reHwnd, 8, 8)   ; CFM_STRIKEOUT = 8, CFE_STRIKEOUT = 8

    static ToggleBullet(reHwnd) {
        pf := Buffer(188, 0)
        NumPut("UInt", 188, pf, 0)
        SendMessage(0x043D, 0, pf.Ptr, reHwnd) ; EM_GETPARAFORMAT
        isBullet := NumGet(pf, 8, "UShort") = 1

        pfSet := Buffer(188, 0)
        NumPut("UInt", 188, pfSet, 0)
        NumPut("UInt", 0x00000020, pfSet, 4) ; PFM_NUMBERING = 0x20
        NumPut("UShort", isBullet ? 0 : 1, pfSet, 8) ; wNumbering: 1 = bullet, 0 = none
        SendMessage(0x0447, 0, pfSet.Ptr, reHwnd) ; EM_SETPARAFORMAT
    }

    static SetColor(reHwnd, colorRef) {
        cfSet := Buffer(116, 0)
        NumPut("UInt", 116, cfSet, 0)
        NumPut("UInt", 0x40000000, cfSet, 4) ; CFM_COLOR
        NumPut("UInt", colorRef, cfSet, 20) ; crTextColor (0x00bbggrr)
        SendMessage(0x0444, 1, cfSet.Ptr, reHwnd)
    }

    static SetSize(reHwnd, ptSize) {
        cfSet := Buffer(116, 0)
        NumPut("UInt", 116, cfSet, 0)
        NumPut("UInt", 0x80000000, cfSet, 4) ; CFM_SIZE
        NumPut("Int", ptSize * 20, cfSet, 12) ; yHeight in twips
        SendMessage(0x0444, 1, cfSet.Ptr, reHwnd)
    }

    static ClearFormatting(reHwnd) {
        cfSet := Buffer(116, 0)
        NumPut("UInt", 116, cfSet, 0)
        NumPut("UInt", 0x4000000F, cfSet, 4) ; BOLD | ITALIC | UNDERLINE | STRIKEOUT | COLOR
        NumPut("UInt", 0, cfSet, 8)
        NumPut("UInt", 0, cfSet, 20)
        SendMessage(0x0444, 1, cfSet.Ptr, reHwnd)

        pfSet := Buffer(188, 0)
        NumPut("UInt", 188, pfSet, 0)
        NumPut("UInt", 0x00000020, pfSet, 4)
        NumPut("UShort", 0, pfSet, 8)
        SendMessage(0x0447, 0, pfSet.Ptr, reHwnd)
    }

    static ResolveRichMacros(rtf, tokenResolver) {
        result := ""
        pos := 1
        pattern := "(?:\\\{|\{){2}(.*?)(?:\\\}|\}){2}"
        while RegExMatch(rtf, pattern, &m, pos) {
            result .= SubStr(rtf, pos, m.Pos - pos)
            rawMacro := "{{" m[1] "}}"
            resolved := tokenResolver(rawMacro)
            result .= this.EscapeRtf(resolved)
            pos := m.Pos + m.Len
        }
        result .= SubStr(rtf, pos)
        return result
    }
}
