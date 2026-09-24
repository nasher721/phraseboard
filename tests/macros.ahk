#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\MacroParser.ahk
#Include ..\lib\MacroEngine.ahk

failures := []

; ----------------------------------------------------
; 1. MacroParser Unit Tests
; ----------------------------------------------------

p1 := MacroParser.Parse("Hello world")
Assert(p1.Nodes.Length = 1 && p1.Nodes[1].Type = "Literal" && p1.Nodes[1].Text = "Hello world",
    "parser parses plain text into literal node")

p2 := MacroParser.Parse("Before {{date}} After")
Assert(p2.Nodes.Length = 3 && p2.Nodes[2].Type = "Macro" && p2.Nodes[2].Name = "date",
    "parser extracts simple {{date}} macro node")

p3 := MacroParser.Parse("{{date:format=yyyy-MM-dd|offset=+3d}}")
Assert(p3.Nodes.Length = 1 && p3.Nodes[1].ParamMap["format"] = "yyyy-MM-dd" && p3.Nodes[1].ParamMap["offset"] = "+3d",
    "parser extracts key-value parameters")

p4 := MacroParser.Parse("{{random:one|two|three}}")
Assert(p4.Nodes.Length = 1 && p4.Nodes[1].Params.Length = 3 && p4.Nodes[1].Params[2].Value = "two",
    "parser extracts positional arguments split by pipe")

p5 := MacroParser.Parse("{{process:{{clipboard}},uppercase}}")
Assert(p5.Nodes.Length = 1 && p5.Nodes[1].Params.Length = 2 && InStr(p5.Nodes[1].Params[1].Value, "{{clipboard}}"),
    "parser preserves nested macro in parameter")

p6 := MacroParser.Parse("Escaped \{brace\} test")
Assert(p6.Nodes.Length = 1 && p6.Nodes[1].Text = "Escaped {brace} test",
    "parser handles escaped braces")

p7 := MacroParser.Parse("Incomplete {{broken macro")
Assert(p7.Errors.Length > 0 && (InStr(p7.Nodes[1].Text, "broken") || (p7.Nodes.Length > 1 && InStr(p7.Nodes[2].Text, "broken"))),
    "parser reports unclosed delimiter gracefully without crashing")

; ----------------------------------------------------
; 2. MacroEngine Evaluation Tests
; ----------------------------------------------------

ctx := MacroEngine.NewContext()
ctx.ClipboardText := "sample clip"

rDate := MacroEngine.Render("{{date:format=yyyy}}", ctx)
Assert(rDate.Text = FormatTime(, "yyyy"), "date macro formats year correctly")

rOff := MacroEngine.Render("{{date:format=yyyy-MM-dd|offset=+1d}}", ctx)
tomorrow := FormatTime(DateAdd(A_Now, 1, "Days"), "yyyy-MM-dd")
Assert(rOff.Text = tomorrow, "date macro computes day offset accurately")

rTime := MacroEngine.Render("{{time:format=yyyy}}", ctx)
Assert(rTime.Text = FormatTime(, "yyyy"), "time macro formats output")

rClip := MacroEngine.Render("Copied: {{clipboard}}", ctx)
Assert(rClip.Text = "Copied: sample clip", "clipboard macro inserts clipboard content")

rCur := MacroEngine.Render("Hi {{cursor}}there", ctx)
Assert(rCur.Text = "Hi there" && rCur.CursorOffset = 5, "cursor macro calculates caret offset")

; Random evaluation with injected seed
ctxRand := MacroEngine.NewContext()
ctxRand.RngSeed := 1
rRand := MacroEngine.Render("{{random:Apple|Banana|Cherry}}", ctxRand)
Assert(rRand.Text = "Banana" || rRand.Text = "Cherry" || rRand.Text = "Apple", "random macro chooses an alternative")

; Variables: set and get
rVar := MacroEngine.Render("{{set:user=Alice}}Hello {{get:user}}!", ctx)
Assert(rVar.Text = "Hello Alice!", "set and get macros store and retrieve scoped variables")

; Conditionals: if
rIf1 := MacroEngine.Render("{{if:premium,premium,VIP,Standard}}", ctx)
Assert(rIf1.Text = "VIP", "if macro returns true branch when equal")

rIf2 := MacroEngine.Render("{{if:guest,premium,VIP,Standard}}", ctx)
Assert(rIf2.Text = "Standard", "if macro returns false branch when not equal")

; Loops: each
rEach := MacroEngine.Render("{{each:x,A|B|C,[{{get:x}}]}}", ctx)
Assert(rEach.Text = "[A][B][C]", "each macro iterates bounded items")

; Post-processing: process
rProc := MacroEngine.Render("{{process:phraseboard,uppercase}}", ctx)
Assert(rProc.Text = "PHRASEBOARD", "process macro applies uppercase")

rProcTitle := MacroEngine.Render("{{process:hello world,titlecase}}", ctx)
Assert(rProcTitle.Text = "Hello World", "process macro applies titlecase")

; Safe arithmetic calc
rCalc1 := MacroEngine.Render("Total: {{calc:10 * 5 + 3}}", ctx)
Assert(rCalc1.Text = "Total: 53", "calc macro evaluates addition and multiplication")

rCalc2 := MacroEngine.Render("{{calc:(100 - 20) / 4}}", ctx)
Assert(rCalc2.Text = "20", "calc macro evaluates parenthesized expressions")

; Nested phrases
phrases := [
    {Id: "p-sub", Name: "Footer", Text: "Best regards,`nPhraseBoard Team"},
    {Id: "p-main", Name: "Greeting", Text: "Hello,`n`n{{phrase:Footer}}"}
]
ctxPhrases := MacroEngine.NewContext()
ctxPhrases.Phrases := phrases
rNested := MacroEngine.Render("{{phrase:Greeting}}", ctxPhrases)
Assert(InStr(rNested.Text, "Best regards") && InStr(rNested.Text, "PhraseBoard Team"),
    "phrase macro expands nested phrases recursively")

; Recursion cycle detection
cyclePhrases := [
    {Id: "cycle-1", Name: "One", Text: "{{phrase:Two}}"},
    {Id: "cycle-2", Name: "Two", Text: "{{phrase:One}}"}
]
ctxCycle := MacroEngine.NewContext()
ctxCycle.Phrases := cyclePhrases
rCycle := MacroEngine.Render("{{phrase:One}}", ctxCycle)
Assert(InStr(rCycle.Text, "cycle detected") || ctxCycle.Errors.Length > 0,
    "phrase recursion cycle is trapped safely")

; Form preflight values injection
ctxForm := MacroEngine.NewContext()
ctxForm.FormValues["client"] := "Acme Corp"
ctxForm.FormValues["project"] := "Expansion"
ctxForm.FormCollected := true ; simulated preflight
rForm := MacroEngine.Render("Client: {{client}}, Project: {{project}}", ctxForm)
Assert(rForm.Text = "Client: Acme Corp, Project: Expansion",
    "preflight form values populate template placeholders")

; Output limit enforcement
hugeText := "{{each:i,1|2|3|4|5|6|7|8|9|10,"
loop 500
    hugeText .= "lots of sample text to exceed limits "
hugeText .= "}}"
ctxLimit := MacroEngine.NewContext()
rLimit := MacroEngine.Render(hugeText, ctxLimit)
Assert(StrLen(rLimit.Text) <= MacroEngine.MaxOutputLength,
    "output length is capped at maximum allowed characters")

; ----------------------------------------------------
; Result Reporting
; ----------------------------------------------------

if failures.Length {
    for failure in failures
        FileAppend("FAIL: " failure "`n", "*")
    ExitApp(1)
}
FileAppend("ALL MACRO TESTS PASSED`n", "*")
ExitApp(0)

Assert(condition, name) {
    global failures
    if condition
        FileAppend("PASS: " name "`n", "*")
    else
        failures.Push(name)
}
