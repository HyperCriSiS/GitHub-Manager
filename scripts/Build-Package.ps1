#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root 'out'
}
& (Join-Path $PSScriptRoot 'Validate-Package.ps1')
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'Package validation failed.' }
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
}
$items = @('GitHub-Manager-v4.2.0.ps1','Modules','docs','scripts',
           'README.md','CONTRIBUTING.md','SECURITY.md','CHANGELOG-4.2.0.md',
           'Start-GitHub-Manager.cmd','Start-GitHub-Manager-Debug.cmd')
foreach ($item in $items) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $item))) {
        throw "Required package path missing: $item"
    }
}
$zip = Join-Path $OutputDirectory 'GitHub-Manager-v4.2.0-preview.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
$paths = @($items | ForEach-Object { Join-Path $root $_ })
Compress-Archive -LiteralPath $paths -DestinationPath $zip -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$checksum = "$hash  $(Split-Path -Leaf $zip)"
Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS') -Value $checksum -Encoding Ascii
Write-Host "Built $zip"
Write-Host $checksum
