#Requires AutoHotkey v2.0
#Include PhraseModel.ahk

class SmartComplete {
    Visible := false
    TargetHwnd := 0
    QueryText := ""
    Results := []
    SelectedIndex := 0
    DismissReason := ""
    TypedText := ""

    AppendCharacter(character) {
        this.TypedText .= character
        if StrLen(this.TypedText) > 128
            this.TypedText := SubStr(this.TypedText, -127)
        return this.TypedText
    }

    Backspace() {
        if StrLen(this.TypedText)
            this.TypedText := SubStr(this.TypedText, 1, -1)
        return this.TypedText
    }

    ResetBuffer() {
        this.TypedText := ""
        return this.TypedText
    }

    static Query(text, phrases, minChars := 1) {
        results := []
        if minChars < 1
            minChars := 1
        if StrLen(text) < minChars
            return results
        ranked := []
        for phrase in phrases {
            position := 0
            lastStart := StrLen(phrase.Name) - StrLen(text) + 1
            if lastStart > 0
                Loop lastStart
                    if SubStr(phrase.Name, A_Index, StrLen(text)) == text {
                        position := A_Index
                        break
                    }
            if !position
                continue
            score := position = 1 ? 0 : 1
            at := ranked.Length + 1
            while at > 1 && score < ranked[at - 1].Score
                at -= 1
            ranked.InsertAt(at, {Phrase: phrase, Score: score})
        }
        for entry in ranked
            results.Push(entry.Phrase)
        return results
    }

    Show(targetHwnd, query, results) {
        this.TargetHwnd := targetHwnd
        this.QueryText := query
        this.Results := results
        this.SelectedIndex := results.Length ? 1 : 0
        this.DismissReason := ""
        this.Visible := results.Length > 0
        return this.Visible
    }

    MoveSelection(delta) {
        if !this.Visible || !this.Results.Length
            return 0
        this.SelectedIndex := Mod(this.SelectedIndex - 1 + delta, this.Results.Length) + 1
        return this.Results[this.SelectedIndex]
    }

    Accept() {
        if !this.Visible || !this.SelectedIndex
            return 0
        selected := this.Results[this.SelectedIndex]
        this.Dismiss("Accepted")
        return selected
    }

    Dismiss(reason := "Dismissed") {
        this.Visible := false
        this.DismissReason := reason
        return true
    }

    ContinueTyping(query, phrases, minChars := 1) {
        this.Dismiss("ContinuedTyping")
        return SmartComplete.Query(query, phrases, minChars)
    }
}
