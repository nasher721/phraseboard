$ErrorActionPreference = 'Stop'
$runtime = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
if (-not (Test-Path -LiteralPath $runtime)) { throw 'AutoHotkey v2 is required.' }
$destination = Join-Path $env:LOCALAPPDATA 'Programs\PhraseBoard'
New-Item -ItemType Directory -Path (Join-Path $destination 'lib') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PhraseBoard.ahk') -Destination $destination -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $destination -Force
foreach ($name in @('Storage.ahk', 'PhraseBoardApp.ahk')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "lib\$name") -Destination (Join-Path $destination 'lib') -Force
}
$shell = New-Object -ComObject WScript.Shell
foreach ($folder in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
    $shortcut = $shell.CreateShortcut((Join-Path $folder 'PhraseBoard.lnk'))
    $shortcut.TargetPath = $runtime
    $shortcut.Arguments = '"' + (Join-Path $destination 'PhraseBoard.ahk') + '"'
    $shortcut.WorkingDirectory = $destination
    $shortcut.Description = 'Encrypted clipboard history and text expansions'
    $shortcut.Save()
}
$appProcess = Start-Process -FilePath $runtime -ArgumentList ('"' + (Join-Path $destination 'PhraseBoard.ahk') + '"') -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 2
$appProcess.Refresh()
if ($appProcess.HasExited) { throw 'PhraseBoard exited unexpectedly after launch.' }
Write-Output "Installed: $destination"
Write-Output "Running process: $($appProcess.Id)"
Write-Output 'Desktop and Start menu shortcuts created. Automatic startup remains optional in Settings.'
