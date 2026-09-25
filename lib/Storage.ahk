#Requires AutoHotkey v2.0

class SecureStore {
    __New(directory) {
        this.Dir := directory
        DirCreate(directory)
    }
    static Bytes(text) {
        result := Buffer(StrPut(text, "UTF-8"))
        StrPut(text, result, "UTF-8")
        result.Size -= 1
        return result
    }
    static B64Chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    static B64Table := StrSplit("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    static B64Rev := SecureStore.InitB64Rev()

    static InitB64Rev() {
        m := Map()
        Loop Parse SecureStore.B64Chars
            m[Ord(A_LoopField)] := A_Index - 1
        m[Ord("=")] := 0
        return m
    }

    static Encode(value) {
        data := IsObject(value) ? value : this.Bytes(value)
        len := data.Size
        if !len
            return ""
        ptr := data.Ptr
        table := this.B64Table
        res := ""
        i := 0
        while i + 2 < len {
            b0 := NumGet(ptr, i, "UChar")
            b1 := NumGet(ptr, i + 1, "UChar")
            b2 := NumGet(ptr, i + 2, "UChar")
            res .= table[(b0 >> 2) + 1]
                . table[(((b0 & 3) << 4) | (b1 >> 4)) + 1]
                . table[(((b1 & 15) << 2) | (b2 >> 6)) + 1]
                . table[(b2 & 63) + 1]
            i += 3
        }
        if i < len {
            b0 := NumGet(ptr, i, "UChar")
            if i + 1 < len {
                b1 := NumGet(ptr, i + 1, "UChar")
                res .= table[(b0 >> 2) + 1]
                    . table[(((b0 & 3) << 4) | (b1 >> 4)) + 1]
                    . table[((b1 & 15) << 2) + 1]
                    . "="
            } else {
                res .= table[(b0 >> 2) + 1]
                    . table[((b0 & 3) << 4) + 1]
                    . "=="
            }
        }
        return res
    }

    static Decode(text, asText := false) {
        if text == ""
            return asText ? "" : Buffer(0)
        len := StrLen(text)
        while SubStr(text, -1) == "="
            text := SubStr(text, 1, -1)
        maxBytes := (len * 3) // 4 + 4
        outBuf := Buffer(maxBytes, 0)
        outPos := 0
        bits := 0
        bitCount := 0
        rev := this.B64Rev
        Loop Parse text {
            code := Ord(A_LoopField)
            if !rev.Has(code)
                continue
            val := rev[code]
            bits := (bits << 6) | val
            bitCount += 6
            if bitCount >= 8 {
                bitCount -= 8
                byte := (bits >> bitCount) & 0xFF
                NumPut("UChar", byte, outBuf, outPos)
                outPos += 1
            }
        }
        outBuf.Size := outPos
        return asText ? StrGet(outBuf.Ptr, outPos, "UTF-8") : outBuf
    }
    static Protect(data, decrypt := false) {
        offset := A_PtrSize = 8 ? 8 : 4
        input := Buffer(offset + A_PtrSize, 0)
        output := Buffer(offset + A_PtrSize, 0)
        NumPut("UInt", data.Size, input)
        NumPut("Ptr", data.Ptr, input, offset)
        ok := decrypt
            ? DllCall("Crypt32\CryptUnprotectData", "Ptr", input, "Ptr", 0, "Ptr", 0,
                "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr", output)
            : DllCall("Crypt32\CryptProtectData", "Ptr", input, "Str", "PhraseBoard",
                "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr", output)
        if !ok
            throw OSError()
        ptr := NumGet(output, offset, "Ptr")
        try {
            result := Buffer(NumGet(output, 0, "UInt"))
            DllCall("RtlMoveMemory", "Ptr", result, "Ptr", ptr, "UPtr", result.Size)
            return result
        } finally DllCall("LocalFree", "Ptr", ptr)
    }
    Write(name, text) {
        path := this.Dir "\" name
        data := SecureStore.Protect(SecureStore.Bytes(text))
        file := FileOpen(path ".tmp", "w")
        try file.RawWrite(data)
        finally file.Close()
        FileMove(path ".tmp", path, 1)
    }
    Read(name) {
        data := SecureStore.Protect(FileRead(this.Dir "\" name, "RAW"), true)
        return StrGet(data, data.Size, "UTF-8")
    }
    Delete(name) {
        path := this.Dir "\" name
        if FileExist(path)
            FileDelete(path)
    }
}
