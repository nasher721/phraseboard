#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\PhraseLibrary.ahk
#Include ..\lib\FolderTree.ahk
#Include ..\lib\TriggerEngine.ahk
#Include ..\lib\SmartComplete.ahk
#Include ..\lib\FolderTriggerMenu.ahk

failures := []
Assert(StrSplit("field`t", "`t").Length = 2, "tab splitting preserves empty trailing library fields")

legacy := {Id: "legacy-1", Name: "Signature", Abbr: ";sig", Text: "Kind regards",
    Tags: "work, email", Favorite: true, Uses: 4, Apps: "WINWORD.EXE"}
phrase := PhraseModel.NormalizePhrase(legacy)
Assert(phrase.Id = "legacy-1" && phrase.Name = "Signature" && phrase.Text = "Kind regards"
    && phrase.Tags = "work, email" && phrase.Favorite && phrase.Uses = 4
    && phrase.Apps = "WINWORD.EXE", "legacy fields survive normalization")
Assert(phrase.Triggers.Length = 1 && phrase.Triggers[1].Kind = "Autotext"
    && phrase.Triggers[1].Value = ";sig", "legacy abbreviation becomes an autotext trigger")
Assert(phrase.FolderId = "", "legacy phrase defaults to root folder")
Assert(!phrase.AiPhrase, "legacy phrase defaults to AI phrase off")

sharedOne := PhraseModel.NormalizePhrase({Id: "shared-1", Name: "First", Text: "one",
    Triggers: [{Kind: "Autotext", Value: ";same"}]})
sharedTwo := PhraseModel.NormalizePhrase({Id: "shared-2", Name: "Second", Text: "two",
    Triggers: [{Kind: "Autotext", Value: ";same"}]})
Assert(PhraseModel.ValidatePhrase(sharedOne) && PhraseModel.ValidatePhrase(sharedTwo),
    "separate phrases may intentionally share an autotext trigger")
sharedOne.Favorite := false
sharedOne.Uses := 3
sharedTwo.Favorite := true
sharedTwo.Uses := 1
sharedThree := PhraseModel.NormalizePhrase({Id: "shared-3", Name: "Third", Text: "three",
    Triggers: [{Kind: "Autotext", Value: ";same"}]})
sharedThree.Uses := 10
sharedMatches := []
try sharedMatches := PhraseModel.FindPhrasesByTrigger("Autotext", ";same", [sharedOne, sharedTwo, sharedThree,
    PhraseModel.NormalizePhrase({Id: "different-kind", Name: "Regex", Text: "three",
        Triggers: [{Kind: "RegexAutotext", Value: ";same"}]})])
catch as err
    sharedMatches := []
Assert(sharedMatches.Length = 3 && sharedMatches[1].Id = "shared-2"
    && sharedMatches[2].Id = "shared-3" && sharedMatches[3].Id = "shared-1",
    "shared trigger lookup returns all exact matches ordered by favorite and usage")

enginePhrases := [
    PhraseModel.NormalizePhrase({Id: "engine-one", Name: "One", Text: "one",
        Triggers: [{Id: "engine-trigger-one", Kind: "Autotext", Value: ";shared"}]}),
    PhraseModel.NormalizePhrase({Id: "engine-two", Name: "Two", Text: "two",
        Triggers: [{Id: "engine-trigger-two", Kind: "Autotext", Value: ";shared"}]}),
    PhraseModel.NormalizePhrase({Id: "engine-disabled", Name: "Disabled", Text: "disabled",
        Triggers: [{Id: "engine-trigger-disabled", Kind: "Autotext", Value: ";shared", Enabled: false}]}),
    PhraseModel.NormalizePhrase({Id: "engine-limited", Name: "Limited", Text: "limited",
        Apps: "WINWORD.EXE", Triggers: [{Id: "engine-trigger-limited", Kind: "Autotext", Value: ";shared"}]})
]
engineMatches := TriggerEngine.Candidates("Autotext", ";shared", 0, enginePhrases, "winword.exe")
engineIds := Map()
for candidate in engineMatches
    engineIds[candidate.PhraseId] := candidate.TriggerId
Assert(engineMatches.Length = 3 && engineIds.Has("engine-one")
    && engineIds["engine-one"] = "engine-trigger-one" && engineIds.Has("engine-two"),
    "trigger candidates preserve shared phrase and trigger IDs")
Assert(TriggerEngine.Candidates("Autotext", ";shared", 0, enginePhrases, "notepad.exe").Length = 2,
    "candidate filtering excludes disabled and disallowed phrases")
Assert(TriggerEngine.Candidates("Autotext", "", 0, enginePhrases).Length = 0,
    "blank trigger cannot produce candidates")

maxAutotext := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "12345678901234567890123456789012"})
Assert(StrLen(maxAutotext.Value) = 32, "32-character autotext is accepted")
longAutotextRejected := false
try PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "123456789012345678901234567890123"})
catch as err
    longAutotextRejected := true
Assert(longAutotextRejected, "33-character autotext is rejected")

boundaryTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "max",
    Options: Map("Position", "Entire", "Before", "None", "After", "CharacterSet",
        "AfterChars", ".,#13#9")})
Assert(TriggerEngine.MatchesBoundary(boundaryTrigger, "xmax.", "x", ".").Matches = false,
    "entire-word autotext rejects a mid-word occurrence")
boundaryHit := TriggerEngine.MatchesBoundary(boundaryTrigger, "max.", "", ".")
Assert(boundaryHit.Matches && boundaryHit.Start = 1 && boundaryHit.Length = 3,
    "entire-word autotext returns its match range at valid boundaries")
Assert(TriggerEngine.MatchesBoundary(boundaryTrigger, "maxx", "", "x").Matches = false,
    "letter/number after-rule rejects an adjacent alphanumeric")
customBoundary := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "x",
    Options: Map("Position", "Start", "Before", "CharacterSet", "BeforeChars", " #13#9")})
Assert(TriggerEngine.MatchesBoundary(customBoundary, "`tx", "`t", "").Matches,
    "custom boundary character sets resolve ENTER and TAB tokens")
startTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "max", Options: Map("Position", "Start")})
endTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "max", Options: Map("Position", "End")})
middleTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "max", Options: Map("Position", "Middle")})
Assert(TriggerEngine.MatchesBoundary(startTrigger, " max", " ", "").Matches
    && !TriggerEngine.MatchesBoundary(startTrigger, "xmax", "x", "").Matches,
    "start position matches only at a word start")
Assert(TriggerEngine.MatchesBoundary(endTrigger, "max ", "", " ").Matches
    && !TriggerEngine.MatchesBoundary(endTrigger, "maxx", "", "x").Matches,
    "end position matches only at a word end")
Assert(TriggerEngine.MatchesBoundary(middleTrigger, "xmaxy", "x", "y").Matches
    && !TriggerEngine.MatchesBoundary(middleTrigger, " max ", " ", " ").Matches,
    "middle position requires word characters on both sides")
anyBefore := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "x", Options: Map("Before", "Any")})
alphaAfter := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "x",
    Options: Map("Position", "Middle", "After", "Alphanumeric")})
incremental := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "max",
    Options: Map("Before", "Incremental", "MinChars", 2)})
incrementalMatch := TriggerEngine.MatchesBoundary(incremental, "ma", "", "")
Assert(!TriggerEngine.MatchesBoundary(anyBefore, "x", "", "").Matches
    && TriggerEngine.MatchesBoundary(anyBefore, "!x", "!", "").Matches,
    "Any boundary requires a neighboring character")
Assert(TriggerEngine.MatchesBoundary(alphaAfter, "zx", "", "x").Matches
    && !TriggerEngine.MatchesBoundary(alphaAfter, "zx", "", ".").Matches,
    "Alphanumeric boundary accepts letters and digits only")
Assert(incrementalMatch.Matches && incrementalMatch.Incremental
    && SmartComplete.Query("ma", [{Id: "inc", Name: "maximum", Text: "x"}], incremental.Options["MinChars"]).Length = 1,
    "incremental boundary offers narrowing SmartComplete suggestions after its minimum")
removeTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "max",
    Options: Map("RemoveTerminator", true)})
keepTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "max"})
Assert(TriggerEngine.TerminatorAction(removeTrigger, " ") = "Remove"
    && TriggerEngine.TerminatorAction(removeTrigger, ".") = "Remove"
    && TriggerEngine.TerminatorAction(removeTrigger, ",") = "Remove",
    "removable trailing space and punctuation are identified")
Assert(TriggerEngine.TerminatorAction(removeTrigger, Chr(13)) = "Keep"
    && TriggerEngine.TerminatorAction(removeTrigger, Chr(9)) = "Keep"
    && TriggerEngine.TerminatorAction(keepTrigger, " ") = "Keep",
    "Enter, Tab, and default terminators are preserved")
hotkeyWarnings := TriggerEngine.HotkeyWarnings("#r", [], "")
Assert(hotkeyWarnings.Length > 0, "likely Windows shortcut conflicts produce a folder-hotkey warning")
folderCandidates := TriggerEngine.FolderCandidates("^!F1", [
    PhraseModel.NormalizeFolder({Id: "hot-folder", Name: "Hot folder",
        Triggers: [{Kind: "Hotkey", Value: "^!F1"}]}),
    PhraseModel.NormalizeFolder({Id: "other-folder", Name: "Other folder",
        Triggers: [{Kind: "Hotkey", Value: "^!F2"}]})
])
Assert(folderCandidates.Length = 1 && folderCandidates[1].FolderId = "hot-folder",
    "folder hotkey candidates resolve exact folder registrations")
invalidMinCharsRejected := false
try PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "x", Options: Map("MinChars", 0)})
catch as err
    invalidMinCharsRejected := true
Assert(invalidMinCharsRejected, "invalid SmartComplete minimum character count is rejected")
invalidModeRejected := false
try PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "x", Mode: "PauseSometimes"})
catch as err
    invalidModeRejected := true
Assert(invalidModeRejected, "unsupported typed-trigger execution mode is rejected")

smartCaseTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "max",
    Options: Map("CaseMode", "SmartCase")})
Assert(TriggerEngine.ApplyCase("max", "maximum", smartCaseTrigger) = "maximum"
    && TriggerEngine.ApplyCase("Max", "maximum", smartCaseTrigger) = "Maximum"
    && TriggerEngine.ApplyCase("MAX", "maximum", smartCaseTrigger) = "MAXIMUM",
    "SmartCase mirrors lowercase, title-case, and uppercase input")
Assert(TriggerEngine.ApplyCase("mAx", "maximum", smartCaseTrigger) = "maximum",
    "SmartCase leaves mixed-case input unchanged")
Assert(TriggerEngine.ApplyCase("MAX", "maximum",
    PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "max"})) = "maximum",
    "Exact case mode does not transform replacement content")
upperCaseTrigger := PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: "MAX",
    Options: Map("CaseMode", "SmartCase")})
Assert(TriggerEngine.ApplyCase("MAX", "maximum", upperCaseTrigger) = "maximum",
    "SmartCase is disabled unless the saved autotext and content are lowercase")
caseConflictPhrases := [
    PhraseModel.NormalizePhrase({Id: "case-one", Name: "Case one", Text: "maximum",
        Triggers: [{Kind: "Autotext", Value: "max", Options: Map("CaseMode", "SmartCase")}]}),
    PhraseModel.NormalizePhrase({Id: "case-two", Name: "Case two", Text: "other",
        Triggers: [{Kind: "Autotext", Value: "MAX"}]})
]
Assert(TriggerEngine.ApplyCase("Max", "maximum", smartCaseTrigger, caseConflictPhrases) = "maximum",
    "SmartCase refuses case-variant trigger collisions")
caseCandidates := TriggerEngine.CandidatesForInput("MAX", 0, caseConflictPhrases)
Assert(caseCandidates.Length = 2 && caseCandidates[1].PhraseId = "case-one"
    && caseCandidates[2].PhraseId = "case-two",
    "typed SmartCase aliases include eligible phrases without activating exact-case variants")
Assert(TriggerEngine.SmartCaseWarnings(smartCaseTrigger, "Maximum", []).Length > 0
    && TriggerEngine.SmartCaseWarnings(smartCaseTrigger, "maximum", caseConflictPhrases).Length > 0,
    "SmartCase editor feedback explains uppercase body and case-collision restrictions")
warnings := TriggerEngine.ConflictWarnings({Kind: "Autotext", Value: "ok"}, caseConflictPhrases)
Assert(warnings.Length > 0, "short ordinary autotext receives a non-blocking warning")

suggestions := [
    PhraseModel.NormalizePhrase({Id: "suggest-a", Name: "Alpha note", Text: "a", Uses: 1}),
    PhraseModel.NormalizePhrase({Id: "suggest-b", Name: "note Alpha", Text: "b", Uses: 1}),
    PhraseModel.NormalizePhrase({Id: "suggest-c", Name: "alpha note", Text: "c", Uses: 1})
]
Assert(SmartComplete.Query("Al", suggestions, 3).Length = 0,
    "SmartComplete respects its configurable minimum character count")
smartResults := SmartComplete.Query("Al", suggestions, 2)
Assert(smartResults.Length = 2 && smartResults[1].Id = "suggest-a"
    && smartResults[2].Id = "suggest-b",
    "SmartComplete performs case-sensitive substring matching")
smartResults := SmartComplete.Query("note", suggestions, 2)
Assert(smartResults.Length = 3 && smartResults[1].Id = "suggest-b"
    && smartResults[2].Id = "suggest-a" && smartResults[3].Id = "suggest-c",
    "SmartComplete ranks prefix matches first and preserves stable ties")
smartState := SmartComplete()
smartState.Show(123, "note", smartResults)
Assert(smartState.AppendCharacter("A") = "A" && smartState.AppendCharacter("l") = "Al"
    && smartState.Backspace() = "A", "SmartComplete input state narrows and handles backspace")
smartState.ResetBuffer()
smartState.MoveSelection(1)
Assert(smartState.Accept().Id = "suggest-a", "SmartComplete arrow navigation and acceptance select the expected result")
smartState.Show(123, "note", smartResults)
smartState.Dismiss("Escape")
Assert(!smartState.Visible && smartState.DismissReason = "Escape", "SmartComplete Escape dismisses the popup state")
continued := smartState.ContinueTyping("note A", suggestions, 2)
Assert(continued.Length = 1 && continued[1].Id = "suggest-b"
    && smartState.DismissReason = "ContinuedTyping", "continued typing dismisses and reruns narrowing")
Assert(TriggerEngine.ModeDecision("Immediate", 999, 500) = "Fire"
    && TriggerEngine.ModeDecision("Confirm", 10, 500) = "Confirm"
    && TriggerEngine.ModeDecision("Confirm", 10, 500, true) = "Fire",
    "immediate and manually confirmed trigger modes are deterministic")
Assert(TriggerEngine.ModeDecision("AfterPause", 499, 500) = "Wait"
    && TriggerEngine.ModeDecision("AfterPause", 500, 500) = "Fire",
    "after-pause mode fires only after its threshold")
Assert(TriggerEngine.ModeDecision("WhileTypingFast", 50, 500) = "Suggest"
    && TriggerEngine.ModeDecision("WhileTypingFast", 500, 500) = "Dismiss",
    "fast-typing mode suggests while typing and dismisses on pause")
Assert(TriggerEngine.AdaptivePause([100, 120, 80], 200, 1000) = 300,
    "adaptive pause threshold scales with measured typing speed")
typingRate := TriggerEngine.TypingRate()
typingRate.Record(1000), typingRate.Record(1100), typingRate.Record(1220)
Assert(typingRate.Threshold(3, 200) = 330, "typing-rate threshold uses injected timestamp intervals")
Assert(typingRate.Evaluate("WhileTypingFast", 100) = "Suggest"
    && typingRate.Evaluate("WhileTypingFast", 500) = "Dismiss",
    "typing-rate evaluation is deterministic for injected elapsed time")


folder := PhraseModel.NormalizeFolder({Id: "root", Name: "Root",
    Triggers: [{Kind: "Hotkey", Value: "^!F1"}]})
Assert(folder.Triggers.Length = 1 && folder.Triggers[1].Kind = "Hotkey",
    "folder keeps its hotkey trigger")

folders := [
    {Id: "parent", ParentId: "", Name: "Parent", TriggerDefaults: Map("Mode", "Confirm")},
    {Id: "child", ParentId: "parent", Name: "Child", TriggerDefaults: Map()},
    {Id: "sibling", ParentId: "parent", Name: "Sibling", TriggerDefaults: Map("Mode", "Immediate")}
]
Assert(PhraseModel.ResolveFolderDefaults("child", folders, "Mode") = "Confirm",
    "child inherits nearest parent trigger default")
Assert(PhraseModel.ResolveFolderDefaults("sibling", folders, "Mode") = "Immediate",
    "child override does not change its sibling")

treePhrases := [
    {Id: "tree-phrase", Name: "Tree phrase", Text: "body", FolderId: "nested"},
    {Id: "direct-phrase", Name: "Direct phrase", Text: "body", FolderId: "nested"}
]
treeFolders := [
    {Id: "top", ParentId: "", Name: "Top", TriggerDefaults: Map("Mode", "Confirm")},
    {Id: "nested", ParentId: "top", Name: "Nested", TriggerDefaults: Map("Mode", "Immediate")},
    {Id: "child", ParentId: "nested", Name: "Child", TriggerDefaults: Map()}
]
tree := FolderTree(treePhrases, treeFolders)
Assert(tree.Path("child") = "Top\Nested\Child", "nested folder path is assembled from ancestors")
Assert(tree.Children("nested").Length = 3, "folder children include direct phrases and subfolders")
tree.Move("tree-phrase", "child")
Assert(treePhrases[1].FolderId = "child", "moving a phrase updates its parent folder")
tree.Delete("nested", "top")
Assert(!tree.FindFolder("nested") && tree.FindFolder("child").ParentId = "top"
    && treePhrases[1].FolderId = "child" && treePhrases[2].FolderId = "top",
    "folder deletion explicitly reparents direct phrases and child folders")
effective := tree.EffectiveDefaults("child")
Assert(effective["Mode"] = "Confirm", "folder defaults inherit up the surviving parent chain")
cycleRejected := false
try tree.Move("top", "child")
catch as err
    cycleRejected := true
Assert(cycleRejected, "folder moves that create a cycle are rejected")

menuPhrases := [{Id: "menu-phrase", Name: "Nested phrase", Text: "body", FolderId: "menu-child"}]
menuFolders := [
    {Id: "menu-top", ParentId: "", Name: "Top", Triggers: [], TriggerDefaults: Map()},
    {Id: "menu-nested", ParentId: "menu-top", Name: "Nested", Triggers: [], TriggerDefaults: Map()},
    {Id: "menu-child", ParentId: "menu-nested", Name: "Child", Triggers: [], TriggerDefaults: Map()}
]
folderMenu := FolderTriggerMenu(menuPhrases, menuFolders)
folderMenu.Open("menu-nested", 123)
menuResults := folderMenu.Search("Child")
Assert(menuResults.Length = 1 && menuResults[1].Item.Id = "menu-child",
    "folder trigger search stays scoped to the open folder")
nestedSelection := folderMenu.Select("menu-child")
Assert(nestedSelection.Type = "Folder" && folderMenu.CurrentFolderId = "menu-child",
    "selecting a nested folder navigates into it")
folderMenu.MoveUp()
Assert(folderMenu.CurrentFolderId = "menu-nested", "folder trigger Up navigates to its parent")
folderMenu.Open("menu-top", 123)
createRow := folderMenu.MoveUp()
Assert(createRow.Type = "CreatePhrase" && createRow.FolderId = "menu-top",
    "folder trigger Up at root focuses create-phrase in the current folder")

blankRejected := false
try PhraseModel.NormalizeTrigger({Kind: "Autotext", Value: ""})
catch as err
    blankRejected := true
Assert(blankRejected, "blank trigger value is rejected")

kindRejected := false
try PhraseModel.NormalizeTrigger({Kind: "Shell", Value: "anything"})
catch as err
    kindRejected := true
Assert(kindRejected, "unsupported trigger kind is rejected")

dataDir := A_Temp "\PhraseBoard-model-" A_TickCount
DirCreate(dataDir)
store := SecureStore(dataDir)
try {
    legacyRow := "stored-legacy`t" SecureStore.Encode("Stored phrase")
        . "`t" SecureStore.Encode(";stored") "`t" SecureStore.Encode("Line one`nΩ line two")
        . "`t" SecureStore.Encode("imported,legacy") "`t1`t7`t"
        . SecureStore.Encode("WINWORD.EXE")
    store.Write("phrases.dat", legacyRow)
    legacyLibrary := PhraseLibrary.Load(store)
    loadedLegacy := legacyLibrary.Phrases[1]
    Assert(legacyLibrary.Phrases.Length = 1 && loadedLegacy.Id = "stored-legacy"
        && loadedLegacy.Name = "Stored phrase" && loadedLegacy.Abbr = ";stored"
        && loadedLegacy.Text = "Line one`nΩ line two" && loadedLegacy.Tags = "imported,legacy"
        && loadedLegacy.Favorite && loadedLegacy.Uses = 7 && loadedLegacy.Apps = "WINWORD.EXE",
        "legacy storage row preserves every phrase field")

    persistedPhrase := {Id: "pb3-phrase", Name: "Unicode phrase", Abbr: ";unicode",
        Text: "First line Ω`nSecond line", Tags: "team, test", Favorite: true, Uses: 9,
        Apps: "notepad.exe", FolderId: "pb3-folder",
        Triggers: [{Id: "pb3-trigger", Kind: "Autotext", Value: ";unicode",
            Mode: "Confirm", Enabled: true, Options: Map("MinChars", "3")},
            {Id: "pb3-inherited", Kind: "SmartComplete", Value: "unicode",
                Mode: "", Enabled: true, Options: Map()}]}
    persistedFolder := {Id: "pb3-folder", ParentId: "", Name: "Work",
        CreatedAt: "20260923", Triggers: [{Id: "folder-hotkey", Kind: "Hotkey",
            Value: "^!F1", Mode: "Immediate", Enabled: true, Options: Map("Key", "F1")}],
        TriggerDefaults: Map("Mode", "Confirm", "RemoveTerminator", "true")}
    rootPhrase := {Id: "pb3-root", Name: "Root phrase", Text: "root-level text"}
    PhraseLibrary.Save(store, [persistedPhrase, rootPhrase], [persistedFolder])
    pb3Text := store.Read("phrases.dat")
    Assert(StrSplit(pb3Text, "`n")[1] = "PB4", "new phrase libraries start with PB4 header")
    lines := StrSplit(pb3Text, "`n")
    reordered := "PB4`n"
    Loop lines.Length - 2
        if lines[lines.Length - A_Index]
            reordered .= lines[lines.Length - A_Index] "`n"
    store.Write("phrases.dat", reordered)
    beforeLoad := store.Read("phrases.dat")
    reloaded := PhraseLibrary.Load(store)
    Assert(store.Read("phrases.dat") = beforeLoad, "loading a PB4 library does not rewrite it")
    savedPhrase := 0
    savedRootPhrase := 0
    savedFolder := 0
    for candidate in reloaded.Phrases {
        if candidate.Id = "pb3-phrase"
            savedPhrase := candidate
        if candidate.Id = "pb3-root"
            savedRootPhrase := candidate
    }
    savedAutotext := 0
    inheritedTrigger := 0
    for trigger in savedPhrase.Triggers {
        if trigger.Id = "pb3-trigger"
            savedAutotext := trigger
        if trigger.Id = "pb3-inherited"
            inheritedTrigger := trigger
    }
    for candidate in reloaded.Folders
        if candidate.Id = "pb3-folder"
            savedFolder := candidate
    Assert(savedPhrase.Id = "pb3-phrase" && savedPhrase.Name = "Unicode phrase"
        && savedPhrase.Abbr = ";unicode" && savedPhrase.Text = "First line Ω`nSecond line"
        && savedPhrase.Tags = "team, test" && savedPhrase.Favorite && savedPhrase.Uses = 9
        && savedPhrase.Apps = "notepad.exe" && savedPhrase.FolderId = "pb3-folder",
        "PB3 phrase fields and Unicode/newline text round-trip")
    Assert(savedPhrase.Triggers.Length = 2 && savedAutotext.Id = "pb3-trigger"
        && savedAutotext.Value = ";unicode" && savedAutotext.Options["MinChars"] = "3",
        "PB3 trigger identity and options round-trip")
    Assert(inheritedTrigger.Mode = "", "PB3 preserves inherited trigger mode without an override")
    Assert(savedFolder.Triggers.Length = 1 && savedFolder.Triggers[1].Id = "folder-hotkey"
        && savedFolder.Triggers[1].Value = "^!F1"
        && savedFolder.TriggerDefaults["Mode"] = "Confirm"
        && savedFolder.TriggerDefaults["RemoveTerminator"] = "true",
        "PB3 folder trigger and inherited defaults round-trip")
    Assert(reloaded.Phrases.Length = 2 && savedRootPhrase.FolderId = "",
        "PB3 root-level phrases preserve an empty folder ID")
    Assert(!savedPhrase.AiPhrase && !savedRootPhrase.AiPhrase,
        "phrases saved without the AI flag stay unchecked")
    uncheckedOriginal := store.Read("phrases.dat")
    uncheckedRejected := false
    uncheckedMessage := ""
    try PhraseLibrary.Save(store, [{Id: "ai-off", Name: "Off", Text: "Hello {{ai:Summarize}}", AiPhrase: false}], [])
    catch as err {
        uncheckedRejected := true
        uncheckedMessage := err.Message
    }
    Assert(uncheckedRejected && uncheckedMessage = "Check AI phrase or remove the AI macro before saving."
        && store.Read("phrases.dat") = uncheckedOriginal,
        "an AI macro cannot be saved while AI phrase is off")
    blankMessage := ""
    try PhraseModel.ValidatePhrase({Id: "ai-blank", Name: "Blank", Text: "{{ai}}", AiPhrase: true})
    catch as err
        blankMessage := err.Message
    Assert(blankMessage = "AI macro requires an instruction.", "a blank AI macro is rejected on save")
    PhraseLibrary.Save(store, [{Id: "ai-on", Name: "On", Text: "Hello {{ai:Summarize|notes}}", AiPhrase: true}], [])
    aiLibrary := PhraseLibrary.Load(store)
    Assert(aiLibrary.Phrases.Length = 1 && aiLibrary.Phrases[1].AiPhrase
        && aiLibrary.Phrases[1].Text = "Hello {{ai:Summarize|notes}}",
        "PB4 round-trips an AI phrase")
    store.Write("phrases.dat", "PB3`n" PhraseLibrary.Row("P", ["pb3-old", "Old", "plain text", "", "0", "1", "", ""]))
    pb3Before := store.Read("phrases.dat")
    pb3Loaded := PhraseLibrary.Load(store)
    Assert(store.Read("phrases.dat") = pb3Before && !pb3Loaded.Phrases[1].AiPhrase,
        "PB3 libraries load as unchecked and are not rewritten")

    malformedCases := ["PB3`nX`tunknown", "PB3`nP`tbad", "PB3`nP`t"
        SecureStore.Encode("id") "`t" SecureStore.Encode("name") "`t"
        SecureStore.Encode("body") "`t" SecureStore.Encode("") "`t0`t0`t"
        SecureStore.Encode("") "`t" SecureStore.Encode("missing-folder")]
    for malformed in malformedCases {
        store.Write("phrases.dat", malformed)
        original := store.Read("phrases.dat")
        rejected := false
        try PhraseLibrary.Load(store)
        catch as err
            rejected := true
        Assert(rejected && store.Read("phrases.dat") = original,
            "malformed PB3 record is rejected without changing its encrypted source")
    }
    original := store.Read("phrases.dat")
    cyclicFolders := [
        {Id: "cycle-a", ParentId: "cycle-b", Name: "A", TriggerDefaults: Map()},
        {Id: "cycle-b", ParentId: "cycle-a", Name: "B", TriggerDefaults: Map()}
    ]
    cycleRejectedOnSave := false
    try PhraseLibrary.Save(store, [], cyclicFolders)
    catch as err
        cycleRejectedOnSave := true
    Assert(cycleRejectedOnSave && store.Read("phrases.dat") = original,
        "folder cycles are rejected before the encrypted library is overwritten")

    plainNorm := PhraseModel.NormalizePhrase({Id: "norm-plain", Name: "Plain", Text: "Just text"})
    Assert(plainNorm.Rtf = "" && plainNorm.Format = "text", "plain phrase normalizes with text format and blank RTF")

    sampleRtf := "{\rtf1\ansi\deff0 {\fonttbl {\f0 Segoe UI;}}\f0\fs24 Hello \b Rich\b0!}"
    richNorm := PhraseModel.NormalizePhrase({Id: "norm-rich", Name: "Rich", Text: "Hello Rich!", Rtf: sampleRtf})
    Assert(richNorm.Rtf = sampleRtf && richNorm.Format = "rich", "rich phrase normalizes with rich format and RTF content")

    oversizedRtf := "{\rtf1 "
    Loop 50001
        oversizedRtf .= "1234567890"
    oversizedRejected := false
    try PhraseModel.ValidatePhrase({Id: "oversized", Name: "Over", Text: "text", Rtf: oversizedRtf})
    catch as err
        oversizedRejected := InStr(err.Message, "500,000") > 0
    Assert(oversizedRejected, "oversized formatted phrase is rejected on validation")

    PhraseLibrary.Save(store, [richNorm], [])
    richReloaded := PhraseLibrary.Load(store)
    Assert(richReloaded.Phrases.Length = 1 && richReloaded.Phrases[1].Rtf = sampleRtf
        && richReloaded.Phrases[1].Format = "rich" && richReloaded.Phrases[1].Text = "Hello Rich!",
        "PB4 round-trips rich formatted text phrases")
} finally {
    if DirExist(dataDir)
        DirDelete(dataDir, true)
}

if failures.Length {
    for failure in failures
        FileAppend("FAIL: " failure "`n", "*")
    ExitApp(1)
}
FileAppend("ALL MODEL TESTS PASSED`n", "*")
ExitApp(0)

Assert(condition, name) {
    global failures
    if condition
        FileAppend("PASS: " name "`n", "*")
    else
        failures.Push(name)
}
