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
    static Encode(value) {
        data := IsObject(value) ? value : this.Bytes(value)
        size := 0
        if !data.Size
            return ""
        if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", data, "UInt", data.Size,
            "UInt", 0x40000001, "Ptr", 0, "UInt*", &size)
            throw OSError()
        out := Buffer(size * 2)
        if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", data, "UInt", data.Size,
            "UInt", 0x40000001, "Ptr", out, "UInt*", &size)
            throw OSError()
        return StrGet(out)
    }
    static Decode(text, asText := false) {
        if text = ""
            return asText ? "" : Buffer(0)
        size := 0
        if !DllCall("Crypt32\CryptStringToBinaryW", "Str", text, "UInt", 0,
            "UInt", 1, "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0)
            throw Error("Invalid saved data.")
        out := Buffer(size)
        if !DllCall("Crypt32\CryptStringToBinaryW", "Str", text, "UInt", 0,
            "UInt", 1, "Ptr", out, "UInt*", &size, "Ptr", 0, "Ptr", 0)
            throw OSError()
        return asText ? StrGet(out, size, "UTF-8") : out
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
