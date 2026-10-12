function Invoke-GhApiBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateSet("POST", "PUT", "PATCH", "DELETE")]
        [string]$Method = "POST",

        [Parameter(Mandatory)]
        [object]$Body,

        [switch]$AllowEmpty
    )

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("github-manager-body-{0}.json" -f [guid]::NewGuid().ToString("N"))

    try {
        $json = $Body | ConvertTo-Json -Depth 40 -Compress
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempFile, $json, $utf8NoBom)

        $arguments = @(
            "api",
            "--method", $Method,
            "-H", "Accept: application/vnd.github+json",
            "-H", "X-GitHub-Api-Version: $script:ApiVersion",
            "--input", $tempFile,
            $Endpoint
        )

        $text = Invoke-Gh -Arguments $arguments -AllowEmpty
        if ([string]::IsNullOrWhiteSpace([string]$text)) {
            if ($AllowEmpty) { return $null }
            return $null
        }

        try {
            $parsed = ConvertFrom-Json -InputObject $text
            Write-FlattenedJsonResult -Value $parsed
        }
        catch {
            return $text
        }
    }
    finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Escape-GitHubPath {
    param([Parameter(Mandatory)][string]$Path)

    return (($Path -split '/') | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
}

function Get-RepositoryDefaultBranchName {
    param([Parameter(Mandatory)][string]$RepositoryName)

    $repo = Invoke-GhApiJson -Endpoint "repos/$RepositoryName"
    if ($null -eq $repo -or [string]::IsNullOrWhiteSpace([string]$repo.default_branch)) {
        throw "Der Standardbranch von $RepositoryName konnte nicht ermittelt werden."
    }

    return [string]$repo.default_branch
}

function Get-RepositoryFileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][string]$Path,
        [string]$Ref,
        [switch]$AllowMissing
    )

    $encodedPath = Escape-GitHubPath -Path $Path
    $endpoint = "repos/$RepositoryName/contents/$encodedPath"
    if (-not [string]::IsNullOrWhiteSpace($Ref)) {
        $endpoint += "?ref=$([System.Uri]::EscapeDataString($Ref))"
    }

    try {
        $file = Invoke-GhApiJson -Endpoint $endpoint
    }
    catch {
        if ($AllowMissing -and $_.Exception.Message -match '(?i)404|not found') {
            return $null
        }
        throw
    }

    if ($null -eq $file) { return $null }

    $content = ""
    if (-not [string]::IsNullOrWhiteSpace([string]$file.content)) {
        $base64 = ([string]$file.content) -replace '\s', ''
        $bytes = [Convert]::FromBase64String($base64)
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    return [pscustomobject]@{
        Path    = [string]$file.path
        Sha     = [string]$file.sha
        Content = $content
        HtmlUrl = [string]$file.html_url
    }
}

function Set-RepositoryFileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$CommitMessage,
        [string]$Branch,
        [string]$Sha
    )

    $encodedPath = Escape-GitHubPath -Path $Path
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $body = [ordered]@{
        message = $CommitMessage
        content = [Convert]::ToBase64String($bytes)
    }

    if (-not [string]::IsNullOrWhiteSpace($Branch)) { $body.branch = $Branch }
    if (-not [string]::IsNullOrWhiteSpace($Sha)) { $body.sha = $Sha }

    return Invoke-GhApiBody -Endpoint "repos/$RepositoryName/contents/$encodedPath" -Method PUT -Body $body
}

function New-RepositoryBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][string]$BranchName,
        [Parameter(Mandatory)][string]$BaseBranch
    )

    $encodedBase = [System.Uri]::EscapeDataString($BaseBranch)
    $baseRef = Invoke-GhApiJson -Endpoint "repos/$RepositoryName/git/ref/heads/$encodedBase"
    if ($null -eq $baseRef -or $null -eq $baseRef.object -or [string]::IsNullOrWhiteSpace([string]$baseRef.object.sha)) {
        throw "Basis-Commit für Branch '$BaseBranch' konnte nicht ermittelt werden."
    }

    $body = [ordered]@{
        ref = "refs/heads/$BranchName"
        sha = [string]$baseRef.object.sha
    }

    return Invoke-GhApiBody -Endpoint "repos/$RepositoryName/git/refs" -Method POST -Body $body
}

function Update-VersionText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Version
    )

    $updated = $Content
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $fileName = [System.IO.Path]::GetFileName($Path).ToLowerInvariant()

    if ($extension -eq ".json" -or $fileName -eq "package.json" -or $fileName -eq "manifest.json") {
        $pattern = '(?m)("version"\s*:\s*")[^"]+("\s*[,}])'
        if ($updated -notmatch $pattern) {
            throw "In '$Path' wurde kein JSON-Versionseintrag gefunden."
        }
        return [regex]::Replace($updated, $pattern, ('$1' + $Version + '$2'), 1)
    }

    if ($extension -eq ".toml") {
        $pattern = '(?m)^(\s*version\s*=\s*["''])[^"'']+(["'']\s*)$'
        if ($updated -match $pattern) {
            return [regex]::Replace($updated, $pattern, ('$1' + $Version + '$2'), 1)
        }
    }

    if ($extension -eq ".csproj" -or $extension -eq ".props") {
        $pattern = '(?i)(<Version>)[^<]+(</Version>)'
        if ($updated -match $pattern) {
            return [regex]::Replace($updated, $pattern, ('$1' + $Version + '$2'), 1)
        }
    }

    $pythonPattern = '(?m)^(\s*__version__\s*=\s*["''])[^"'']+(["'']\s*)$'
    if ($updated -match $pythonPattern) {
        return [regex]::Replace($updated, $pythonPattern, ('$1' + $Version + '$2'), 1)
    }

    throw "Für '$Path' wurde kein unterstützter Versionseintrag gefunden. Unterstützt werden JSON, TOML, .csproj/.props und __version__."
}
