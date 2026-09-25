#Requires AutoHotkey v2.0

class Json {
    static MaxChars := 2000000
    static False := {__JsonBool: false}
    static True := {__JsonBool: true}

    static Encode(value) {
        if IsObject(value) && HasProp(value, "__JsonBool")
            return value.__JsonBool ? "true" : "false"
        if value is String
            return this.EncodeString(value)
        if value is Integer
            return String(value)
        if value is Float
            return RegExReplace(Format("{:.6f}", value), "\.?0+$")
        if value is Array
            return this.EncodeArray(value)
        if value is Map
            return this.EncodeMap(value)
        throw Error("Unsupported JSON value.")
    }

    static Decode(text) {
        if StrLen(text) > this.MaxChars
            throw Error("JSON payload is too large.")
        pos := 1
        value := this.ParseValue(text, &pos)
        this.Skip(text, &pos)
        if pos <= StrLen(text)
            throw Error("JSON has trailing data.")
        return value
    }

    static EncodeString(text) {
        out := Chr(34)
        loop parse text {
            code := Ord(A_LoopField)
            if A_LoopField = "\"
                out .= "\\"
            else if A_LoopField = Chr(34)
                out .= "\" Chr(34)
            else if code = 8
                out .= "\b"
            else if code = 9
                out .= "\t"
            else if code = 10
                out .= "\n"
            else if code = 12
                out .= "\f"
            else if code = 13
                out .= "\r"
            else if code < 32
                out .= Format("\u{:04x}", code)
            else
                out .= A_LoopField
        }
        return out Chr(34)
    }

    static EncodeArray(values) {
        out := ""
        for value in values
            out .= (out = "" ? "" : ",") this.Encode(value)
        return "[" out "]"
    }

    static EncodeMap(values) {
        out := ""
        for key, value in values {
            if !(key is String)
                throw Error("JSON object keys must be strings.")
            out .= (out = "" ? "" : ",") this.EncodeString(key) ":" this.Encode(value)
        }
        return "{" out "}"
    }

    static ParseValue(text, &pos) {
        this.Skip(text, &pos)
        if pos > StrLen(text)
            throw Error("JSON ended early.")
        ch := SubStr(text, pos, 1)
        if ch = Chr(34)
            return this.ParseString(text, &pos)
        if ch = "{"
            return this.ParseObject(text, &pos)
        if ch = "["
            return this.ParseArray(text, &pos)
        if ch = "t" || ch = "f" || ch = "n"
            return this.ParseLiteral(text, &pos)
        if ch = "-" || (ch >= "0" && ch <= "9")
            return this.ParseNumber(text, &pos)
        throw Error("Invalid JSON value.")
    }

    static ParseObject(text, &pos) {
        obj := Map()
        pos += 1
        this.Skip(text, &pos)
        if SubStr(text, pos, 1) = "}" {
            pos += 1
            return obj
        }
        loop {
            this.Skip(text, &pos)
            if SubStr(text, pos, 1) != Chr(34)
                throw Error("JSON object key must be a string.")
            key := this.ParseString(text, &pos)
            if obj.Has(key)
                throw Error("JSON object has a duplicate key.")
            this.Skip(text, &pos)
            if SubStr(text, pos, 1) != ":"
                throw Error("JSON object is missing a colon.")
            pos += 1
            obj[key] := this.ParseValue(text, &pos)
            this.Skip(text, &pos)
            ch := SubStr(text, pos, 1)
            if ch = "}" {
                pos += 1
                return obj
            }
            if ch != ","
                throw Error("JSON object is missing a comma.")
            pos += 1
        }
    }

    static ParseArray(text, &pos) {
        values := []
        pos += 1
        this.Skip(text, &pos)
        if SubStr(text, pos, 1) = "]" {
            pos += 1
            return values
        }
        loop {
            values.Push(this.ParseValue(text, &pos))
            this.Skip(text, &pos)
            ch := SubStr(text, pos, 1)
            if ch = "]" {
                pos += 1
                return values
            }
            if ch != ","
                throw Error("JSON array is missing a comma.")
            pos += 1
        }
    }

    static ParseString(text, &pos) {
        pos += 1
        out := ""
        while pos <= StrLen(text) {
            ch := SubStr(text, pos, 1)
            if ch = Chr(34) {
                pos += 1
                return out
            }
            if ch = "\" {
                pos += 1
                if pos > StrLen(text)
                    throw Error("JSON string has a bad escape.")
                esc := SubStr(text, pos, 1)
                if esc = Chr(34) || esc = "\" || esc = "/"
                    out .= esc
                else if esc = "b"
                    out .= Chr(8)
                else if esc = "f"
                    out .= Chr(12)
                else if esc = "n"
                    out .= "`n"
                else if esc = "r"
                    out .= "`r"
                else if esc = "t"
                    out .= "`t"
                else if esc = "u" {
                    hex := SubStr(text, pos + 1, 4)
                    if !RegExMatch(hex, "i)^[0-9a-f]{4}$")
                        throw Error("JSON string has a bad escape.")
                    out .= Chr(Integer("0x" hex))
                    pos += 4
                } else
                    throw Error("JSON string has a bad escape.")
            } else if Ord(ch) < 32
                throw Error("JSON string has a raw control character.")
            else
                out .= ch
            pos += 1
        }
        throw Error("JSON string ended early.")
    }

    static ParseLiteral(text, &pos) {
        for literal in ["true", "false", "null"] {
            if SubStr(text, pos, StrLen(literal)) = literal {
                pos += StrLen(literal)
                if literal = "true"
                    return true
                if literal = "false"
                    return false
                return ""
            }
        }
        throw Error("Invalid JSON literal.")
    }

    static ParseNumber(text, &pos) {
        start := pos
        if SubStr(text, pos, 1) = "-"
            pos += 1
        if SubStr(text, pos, 1) = "0"
            pos += 1
        else if RegExMatch(SubStr(text, pos, 1), "[1-9]") {
            while RegExMatch(SubStr(text, pos, 1), "\d")
                pos += 1
        } else
            throw Error("Invalid JSON number.")
        if SubStr(text, pos, 1) = "." {
            pos += 1
            if !RegExMatch(SubStr(text, pos, 1), "\d")
                throw Error("Invalid JSON number.")
            while RegExMatch(SubStr(text, pos, 1), "\d")
                pos += 1
        }
        if SubStr(text, pos, 1) = "e" || SubStr(text, pos, 1) = "E" {
            pos += 1
            if SubStr(text, pos, 1) = "+" || SubStr(text, pos, 1) = "-"
                pos += 1
            if !RegExMatch(SubStr(text, pos, 1), "\d")
                throw Error("Invalid JSON number.")
            while RegExMatch(SubStr(text, pos, 1), "\d")
                pos += 1
        }
        token := SubStr(text, start, pos - start)
        return InStr(token, ".") || InStr(token, "e") || InStr(token, "E") ? Float(token) : Integer(token)
    }

    static Skip(text, &pos) {
        while pos <= StrLen(text) && InStr(" `t`r`n", SubStr(text, pos, 1))
            pos += 1
    }
}
