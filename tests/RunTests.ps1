$ErrorActionPreference = 'Stop'
$runtime = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
foreach ($name in @('smoke', 'model', 'macros', 'hotkeys', 'integration')) {
    $script = Join-Path $PSScriptRoot ($name + '.ahk')
    if (-not (Test-Path -LiteralPath $script)) { continue }
    $out = Join-Path $env:TEMP ('phraseboard-' + $name + '.out.log')
    $err = Join-Path $env:TEMP ('phraseboard-' + $name + '.err.log')
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
    if (Test-Path -LiteralPath $err) { Remove-Item -LiteralPath $err -Force }
    $process = Start-Process -FilePath $runtime -ArgumentList ('/ErrorStdOut "' + $script + '"') -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
    Get-Content -LiteralPath $out,$err -ErrorAction SilentlyContinue
    if ($process.ExitCode -ne 0) { throw "$name tests exited with code $($process.ExitCode)" }
    if (-not (Select-String -LiteralPath $out -SimpleMatch 'TESTS PASSED' -Quiet)) { throw "$name tests did not confirm success" }
}
