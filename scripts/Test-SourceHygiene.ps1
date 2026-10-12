#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem -Path $root -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and
    $_.FullName -notmatch '[\\/]out[\\/]'
})
$errors = New-Object System.Collections.Generic.List[string]
foreach ($file in $files) {
    $relative = $file.FullName.Substring($root.Length).TrimStart('\','/')
    if ($relative -match '(?i)(?:^|[\\/])(?:\.env(?:\..*)?|id_rsa|id_ed25519|[^\\/]+\.(?:p12|pfx|pem))$') {
        $errors.Add("Restricted file name: $relative")
        continue
    }
    if ($file.Extension -notin @('.ps1','.psm1','.psd1','.md','.yml','.yaml','.json','.cmd','.txt')) { continue }
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    if ($null -eq $content) { continue }
    $patterns = @(
        '(?i)\bgh[pousr]_[A-Za-z0-9_]{20,}\b',
        '(?i)\bgithub_pat_[A-Za-z0-9_]{20,}\b',
        '\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
        '-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----',
        '(?i)https?://[^/\s@]+:[^/\s@]+@'
    )
    foreach ($pattern in $patterns) {
        if ([regex]::IsMatch($content,$pattern)) {
            $errors.Add("Potential credential found in $relative. Do not print secret values.")
            break
        }
    }
}
if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host $message -ForegroundColor Red }
    throw ("Source hygiene check failed for {0} item(s)." -f $errors.Count)
}
Write-Host ("Source hygiene check passed for {0} files." -f $files.Count) -ForegroundColor Green
