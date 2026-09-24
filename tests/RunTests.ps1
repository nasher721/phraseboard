$ErrorActionPreference = 'Stop'
$runtime = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
foreach ($name in @('smoke', 'integration')) {
    $script = Join-Path $PSScriptRoot ($name + '.ahk')
    if (-not (Test-Path -LiteralPath $script)) { continue }
    $out = Join-Path $env:TEMP ('phraseboard-' + $name + '.out.log')
    $err = Join-Path $env:TEMP ('phraseboard-' + $name + '.err.log')
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = $runtime
    $process.StartInfo.Arguments = '/ErrorStdOut "' + $script + '"'
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.WindowStyle = 'Hidden'
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.Start() | Out-Null
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id
        throw "$name test timed out"
    }
    $process.StandardOutput.ReadToEnd() | Set-Content -LiteralPath $out
    $process.StandardError.ReadToEnd() | Set-Content -LiteralPath $err
    Get-Content -LiteralPath $out,$err
    if ($process.ExitCode -ne 0) { throw "$name tests exited with code $($process.ExitCode)" }
    if (-not (Select-String -LiteralPath $out -SimpleMatch 'TESTS PASSED' -Quiet)) { throw "$name tests did not confirm success" }
}
