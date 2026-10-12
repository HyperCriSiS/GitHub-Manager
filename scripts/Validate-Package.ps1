#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$main = Join-Path $root 'GitHub-Manager-v4.2.0.ps1'
$worker = Join-Path $root 'Modules/GitHubManager.BulkCleanup.Worker.ps1'
$controller = Join-Path $root 'Modules/GitHubManager.BulkCleanup.ps1'
$required = @($main,$worker,$controller)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Pflichtdatei fehlt: $path" }
}
$files = @(Get-ChildItem -Path $root -Recurse -File -Filter '*.ps1')
$failed = 0
foreach ($file in $files) {
    # Windows PowerShell 5.1 treats UTF-8 without BOM as the active ANSI code page.
    # Require a BOM for all PowerShell sources to avoid silent Unicode corruption.
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) {
        $failed++
        Write-Host ("ENCODING FEHLER: {0}: UTF-8 BOM fehlt." -f $file.FullName) -ForegroundColor Red
    }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $failed += $parseErrors.Count
        foreach ($err in $parseErrors) {
            Write-Host ("PARSER FEHLER: {0}:{1}:{2}: {3}" -f $file.Name, $err.Extent.StartLineNumber, $err.Extent.StartColumnNumber, $err.Message) -ForegroundColor Red
        }
    }
    else { Write-Host "PARSE OK: $($file.FullName.Substring($root.Length+1))" }
}
if ($failed -gt 0) { throw "$failed Parser-/Encoding-Fehler gefunden." }
$mainContent = Get-Content -LiteralPath $main -Raw -Encoding UTF8
foreach ($name in @('GitHubManager.Extensions.ps1','GitHubManager.Release.ps1',
                  'GitHubManager.Templates.ps1','GitHubManager.BulkCleanup.ps1')) {
    $path = Join-Path $root "Modules/$name"
    if (-not (Test-Path -LiteralPath $path)) { throw "Modul fehlt: $path" }
    if (-not $mainContent.Contains($name)) { throw "Modul ist im Bootstrap nicht eingebunden: $name" }
}
foreach ($needle in @('Initialize-BulkCleanupTab','Update-BulkRepositories', 'Assert-BulkWriteAllowed')) {
    if (-not $mainContent.Contains($needle)) { throw "GUI-Anbindung fehlt: $needle" }
}
$workerSource = Get-Content -LiteralPath $worker -Raw -Encoding UTF8
foreach ($needle in @('Get-BulkPages','Get-BulkCandidates','Invoke-BulkApi',
                      'KeepRuns','ProtectDefaultCache','DeleteReleaseTags', 'CancellationToken')) {
    if (-not $workerSource.Contains($needle)) { throw "Worker-Kontrakt fehlt: $needle" }
}
foreach ($launcher in @('Start-GitHub-Manager.cmd','Start-GitHub-Manager-Debug.cmd')) {
    $content = Get-Content -LiteralPath (Join-Path $root $launcher) -Raw
    if (-not $content.Contains('GitHub-Manager-v4.2.0.ps1')) { throw "Launcher $launcher verweist auf falsche Version." }
}
Write-Host ("PASS: {0} PowerShell-Dateien geparst, BOM und Paketverweise geprüft." -f $files.Count) -ForegroundColor Green
