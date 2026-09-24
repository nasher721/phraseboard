#Requires AutoHotkey v2.0

class MacroForms {
    static Collect(fields, title := "PhraseBoard - Fill Details", targetHwnd := 0) {
        if !IsObject(fields) || fields.Length = 0
            return Map()

        ; If headless or automated test mode flag is set
        if InStr(A_Args.Length > 0 ? A_Args[1] : "", "headless")
            return this.DefaultValues(fields)

        formGui := Gui("+AlwaysOnTop +Owner -MinimizeBox", title)
        formGui.SetFont("s10", "Segoe UI")
        formGui.MarginX := 16
        formGui.MarginY := 12

        fieldControls := Map()
        submitted := false
        resultValues := Map()

        for f in fields {
            label := f.HasProp("Label") ? f.Label : f.Key
            defaultVal := f.HasProp("Default") ? f.Default : ""
            options := f.HasProp("Options") ? f.Options : []

            formGui.AddText("xm w380", label ":")

            if options.Length > 0 {
                ; Dropdown list
                chosen := 1
                for idx, opt in options {
                    if opt = defaultVal {
                        chosen := idx
                        break
                    }
                }
                ctrl := formGui.AddDropDownList("xm w380 Choose" chosen, options)
                fieldControls[f.Key] := {Control: ctrl, Type: "DropDownList"}
            } else if f.HasProp("Multiline") && f.Multiline {
                ctrl := formGui.AddEdit("xm w380 r4 WantTab", defaultVal)
                fieldControls[f.Key] := {Control: ctrl, Type: "Edit"}
            } else {
                ctrl := formGui.AddEdit("xm w380", defaultVal)
                fieldControls[f.Key] := {Control: ctrl, Type: "Edit"}
            }
        }

        btnInsert := formGui.AddButton("xm+210 w80 Default", "Insert")
        btnCancel := formGui.AddButton("x+10 w80", "Cancel")

        btnInsert.OnEvent("Click", (*) => OnSubmit())
        btnCancel.OnEvent("Click", (*) => OnCancel())
        formGui.OnEvent("Close", (*) => OnCancel())
        formGui.OnEvent("Escape", (*) => OnCancel())

        OnSubmit() {
            for key, item in fieldControls {
                if item.Type = "DropDownList" {
                    resultValues[key] := item.Control.Text
                } else {
                    resultValues[key] := item.Control.Value
                }
            }
            submitted := true
            formGui.Destroy()
        }

        OnCancel() {
            submitted := false
            formGui.Destroy()
        }

        formGui.Show("AutoSize Center")

        ; Wait until form is closed
        while WinExist("ahk_id " formGui.Hwnd)
            Sleep(25)

        if !submitted
            return {Cancelled: true}

        return resultValues
    }

    static DefaultValues(fields) {
        values := Map()
        for f in fields {
            key := f.HasProp("Key") ? f.Key : "field"
            defaultVal := f.HasProp("Default") ? f.Default : ""
            if defaultVal = "" && f.HasProp("Options") && f.Options.Length > 0
                defaultVal := f.Options[1]
            values[key] := defaultVal
        }
        return values
    }

    static Prompt(label, defaultVal := "") {
        ib := InputBox("Enter value for " label ":", "PhraseBoard Prompt", "w360 h130", defaultVal)
        if ib.Result = "Cancel"
            return {Cancelled: true, Value: ""}
        return {Cancelled: false, Value: ib.Value}
    }
}
