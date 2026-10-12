function Clear-ReleaseData {
    $script:State.Releases = @()
    $script:State.Tags = @()
    if ($null -ne $releaseGrid) { $releaseGrid.Rows.Clear() }
    if ($null -ne $releaseCurrentLabel) { $releaseCurrentLabel.Text = "Noch nicht geladen." }
}

function Get-SemVerInfo {
    param([string]$Tag)

    if ([string]::IsNullOrWhiteSpace($Tag)) { return $null }
    $match = [regex]::Match($Tag.Trim(), '^(?<prefix>v?)(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(?:-(?<pre>alpha|beta|rc)(?:[.-]?(?<n>\d+))?)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $null }

    $n = 0
    if ($match.Groups['n'].Success) { [void][int]::TryParse($match.Groups['n'].Value, [ref]$n) }

    return [pscustomobject]@{
        Tag    = $Tag
        Prefix = $match.Groups['prefix'].Value
        Major  = [int]$match.Groups['major'].Value
        Minor  = [int]$match.Groups['minor'].Value
        Patch  = [int]$match.Groups['patch'].Value
        Pre    = $match.Groups['pre'].Value.ToLowerInvariant()
        Number = $n
    }
}

function Format-SemVerTag {
    param([object]$Info, [string]$Pre = "", [int]$Number = 0)
    $tag = "{0}{1}.{2}.{3}" -f $Info.Prefix, $Info.Major, $Info.Minor, $Info.Patch
    if (-not [string]::IsNullOrWhiteSpace($Pre)) { $tag += "-$Pre.$Number" }
    return $tag
}

function Get-SemVerSortKey {
    param([Parameter(Mandatory)][object]$Info)

    $preWeight = switch ([string]$Info.Pre) {
        'alpha' { 0 }
        'beta'  { 1 }
        'rc'    { 2 }
        default { 3 }
    }

    # Zahlen werden mit fester Breite formatiert, damit Sort-Object die
    # SemVer-Reihenfolge unabhängig von der Reihenfolge der GitHub-API erhält.
    return ('{0:D10}.{1:D10}.{2:D10}.{3:D2}.{4:D10}' -f [int]$Info.Major,[int]$Info.Minor,[int]$Info.Patch,$preWeight,[int]$Info.Number)
}

function Get-ReleaseBaseSemVer {
    $semantic = @(
        foreach ($tag in @($script:State.Tags)) {
            $parsed = Get-SemVerInfo -Tag ([string]$tag)
            if ($null -ne $parsed) { $parsed }
        }
    )

    if ($semantic.Count -eq 0) {
        return [pscustomobject]@{ Prefix = 'v'; Major = 0; Minor = 0; Patch = 0; Pre = ''; Number = 0; Tag = 'v0.0.0' }
    }

    return @($semantic | Sort-Object @{ Expression={ Get-SemVerSortKey -Info $_ }; Descending=$true })[0]
}

function Get-LatestStableSemVer {
    $stable = @(
        foreach ($tag in @($script:State.Tags)) {
            $parsed = Get-SemVerInfo -Tag ([string]$tag)
            if ($null -ne $parsed -and [string]::IsNullOrWhiteSpace($parsed.Pre)) { $parsed }
        }
    )
    if ($stable.Count -gt 0) {
        return @($stable | Sort-Object @{ Expression={ Get-SemVerSortKey -Info $_ }; Descending=$true })[0]
    }
    return Get-ReleaseBaseSemVer
}

function Get-VersionSuggestion {
    param([ValidateSet('Patch','Minor','Major','Beta','RC','Stable')][string]$Kind)

    $current = Get-ReleaseBaseSemVer
    $stable = Get-LatestStableSemVer
    $prefix = if ([string]::IsNullOrWhiteSpace($current.Prefix)) { 'v' } else { $current.Prefix }

    switch ($Kind) {
        'Patch' {
            return "$prefix$($stable.Major).$($stable.Minor).$($stable.Patch + 1)"
        }
        'Minor' {
            return "$prefix$($stable.Major).$($stable.Minor + 1).0"
        }
        'Major' {
            return "$prefix$($stable.Major + 1).0.0"
        }
        'Beta' {
            if ($current.Pre -eq 'beta') {
                return "$prefix$($current.Major).$($current.Minor).$($current.Patch)-beta.$($current.Number + 1)"
            }
            if ($current.Pre -in @('alpha','rc')) {
                if ($current.Pre -eq 'alpha') { return "$prefix$($current.Major).$($current.Minor).$($current.Patch)-beta.1" }
            }
            return "$prefix$($stable.Major).$($stable.Minor + 1).0-beta.1"
        }
        'RC' {
            if ($current.Pre -eq 'rc') {
                return "$prefix$($current.Major).$($current.Minor).$($current.Patch)-rc.$($current.Number + 1)"
            }
            if ($current.Pre -in @('alpha','beta')) {
                return "$prefix$($current.Major).$($current.Minor).$($current.Patch)-rc.1"
            }
            return "$prefix$($stable.Major).$($stable.Minor + 1).0-rc.1"
        }
        'Stable' {
            if (-not [string]::IsNullOrWhiteSpace($current.Pre)) {
                return "$prefix$($current.Major).$($current.Minor).$($current.Patch)"
            }
            return "$prefix$($stable.Major).$($stable.Minor).$($stable.Patch + 1)"
        }
    }
}

function Get-VersionCoreFromTag {
    param([string]$Tag)
    $parsed = Get-SemVerInfo -Tag $Tag
    if ($null -eq $parsed) { return ($Tag -replace '^v','') }
    return "$($parsed.Major).$($parsed.Minor).$($parsed.Patch)"
}

function Update-ReleaseTitleFromTag {
    $newTag = $releaseTagTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($newTag)) { return }

    $title = $newTag
    if ($script:State.Releases.Count -gt 0) {
        $latest = $script:State.Releases[0]
        $oldTag = [string]$latest.tagName
        $oldTitle = [string]$latest.name
        if (-not [string]::IsNullOrWhiteSpace($oldTitle)) {
            if (-not [string]::IsNullOrWhiteSpace($oldTag) -and $oldTitle.Contains($oldTag)) {
                $title = $oldTitle.Replace($oldTag, $newTag)
            }
            elseif ($oldTitle -match 'v?\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)(?:[.-]?\d+)?)?') {
                $title = [regex]::Replace($oldTitle, 'v?\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)(?:[.-]?\d+)?)?', $newTag, 1)
            }
        }
    }

    $releaseTitleTextBox.Text = $title
    $releaseFileVersionTextBox.Text = Get-VersionCoreFromTag -Tag $newTag
    $releasePrereleaseCheckBox.Checked = ($newTag -match '(?i)-(alpha|beta|rc)(?:[.-]?\d+)?$')
}

function Set-ReleaseVersionSuggestion {
    param([string]$Kind)
    $releaseTagTextBox.Text = Get-VersionSuggestion -Kind $Kind
    Update-ReleaseTitleFromTag
}

function Load-ReleaseData {
    try {
        $repositoryName = Get-SelectedRepositoryName
        Set-Status "Lade Releases und Tags ..."
        $form.UseWaitCursor = $true
        $releaseGrid.Rows.Clear()

        $releaseArgs = @('release','list','--repo',$repositoryName,'--limit','100','--json','tagName,name,isDraft,isPrerelease,isLatest,publishedAt,createdAt,isImmutable')
        try {
            $releases = @(Invoke-GhJson -Arguments $releaseArgs)
        }
        catch {
            $releaseArgs = @('release','list','--repo',$repositoryName,'--limit','100','--json','tagName,name,isDraft,isPrerelease,isLatest,publishedAt,createdAt')
            $releases = @(Invoke-GhJson -Arguments $releaseArgs)
        }

        $tags = @(Invoke-GhApiJson -Endpoint "repos/$repositoryName/tags?per_page=100" -Paginate -Slurp | Where-Object { $null -ne $_.name } | ForEach-Object { [string]$_.name })
        $script:State.Releases = @($releases)
        $script:State.Tags = @($tags)

        foreach ($release in $releases) {
            $published = if (-not [string]::IsNullOrWhiteSpace([string]$release.publishedAt)) { Convert-ToLocalDateText $release.publishedAt } else { Convert-ToLocalDateText $release.createdAt }
            $immutable = if ($null -ne $release.PSObject.Properties['isImmutable']) { [bool]$release.isImmutable } else { $false }
            $idx = $releaseGrid.Rows.Add(
                $published,
                [string]$release.tagName,
                [string]$release.name,
                [bool]$release.isPrerelease,
                [bool]$release.isDraft,
                [bool]$release.isLatest,
                $immutable
            )
            $releaseGrid.Rows[$idx].Tag = $release
        }

        $latestTag = if ($tags.Count -gt 0) { $tags[0] } else { '–' }
        $latestRelease = if ($releases.Count -gt 0) { [string]$releases[0].tagName } else { '–' }
        $releaseCurrentLabel.Text = "Neuester Tag: $latestTag   ·   Neuester Release: $latestRelease   ·   Releases: $($releases.Count)"

        $repoObj = Get-SelectedRepositoryObject
        $defaultBranch = if ($null -ne $repoObj.defaultBranchRef) { [string]$repoObj.defaultBranchRef.name } else { '' }
        if ([string]::IsNullOrWhiteSpace($defaultBranch)) { $defaultBranch = Get-RepositoryDefaultBranchName -RepositoryName $repositoryName }
        $releaseTargetTextBox.Text = $defaultBranch

        if ([string]::IsNullOrWhiteSpace($releaseTagTextBox.Text)) {
            Set-ReleaseVersionSuggestion -Kind 'Patch'
        }

        Set-Status "Release-Daten geladen."
    }
    catch {
        Set-Status "Release-Daten konnten nicht geladen werden."
        Show-Error -Title "Release-Daten konnten nicht geladen werden" -ErrorObject $_
    }
    finally {
        $form.UseWaitCursor = $false
    }
}

function Add-ReleaseAssets {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Title = "Release-Dateien auswählen"
    try {
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            foreach ($file in $dialog.FileNames) {
                if (-not $releaseAssetsListBox.Items.Contains($file)) { [void]$releaseAssetsListBox.Items.Add($file) }
            }
        }
    }
    finally { $dialog.Dispose() }
}

function Remove-ReleaseAssets {
    $selected = @($releaseAssetsListBox.SelectedItems)
    foreach ($item in $selected) { $releaseAssetsListBox.Items.Remove($item) }
}

function Get-ReleaseVersionPaths {
    return @(
        $releaseVersionPathsTextBox.Lines |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Detect-ReleaseVersionPaths {
    try {
        $repositoryName = Get-SelectedRepositoryName
        $branch = $releaseTargetTextBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($branch)) {
            $branch = Get-RepositoryDefaultBranchName -RepositoryName $repositoryName
            $releaseTargetTextBox.Text = $branch
        }

        Set-Status "Erkenne Versionsdateien ..."
        $root = @(Invoke-GhApiJson -Endpoint "repos/$repositoryName/contents?ref=$([System.Uri]::EscapeDataString($branch))")
        $paths = New-Object System.Collections.ArrayList

        foreach ($candidate in @('package.json','manifest.json','pyproject.toml','Cargo.toml','Directory.Build.props')) {
            if (@($root | Where-Object { [string]$_.name -eq $candidate -and [string]$_.type -eq 'file' }).Count -gt 0) {
                [void]$paths.Add($candidate)
            }
        }

        foreach ($item in @($root | Where-Object { [string]$_.type -eq 'file' -and [string]$_.name -match '\.(csproj|props)$' })) {
            if (-not $paths.Contains([string]$item.path)) { [void]$paths.Add([string]$item.path) }
        }

        # Python-Projekte legen die Version oft in einer __init__.py ab. Eine
        # rekursive Repository-Suche wäre unnötig teuer; bekannte Root-Pfade
        # werden deshalb nur geprüft, wenn sie existieren.
        foreach ($candidate in @('__init__.py','src/__init__.py')) {
            try {
                $file = Get-RepositoryFileContent -RepositoryName $repositoryName -Path $candidate -Ref $branch -AllowMissing
                if ($null -ne $file -and $file.Content -match '(?m)^\s*__version__\s*=') {
                    if (-not $paths.Contains($candidate)) { [void]$paths.Add($candidate) }
                }
            }
            catch { }
        }

        if ($paths.Count -eq 0) {
            $releaseVersionPathsTextBox.Clear()
            Set-Status "Keine unterstützte Versionsdatei automatisch erkannt."
            [void][System.Windows.Forms.MessageBox]::Show(
                $form,
                "Im Root des Zielbranches wurde keine unterstützte Versionsdatei erkannt. Du kannst die Pfade weiterhin manuell eintragen.",
                "Keine Versionsdatei erkannt",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }

        $releaseVersionPathsTextBox.Lines = @($paths)
        Set-Status "$($paths.Count) Versionsdatei(en) erkannt."
    }
    catch {
        Set-Status "Versionsdateien konnten nicht erkannt werden."
        Show-Error -Title "Versionsdateien konnten nicht erkannt werden" -ErrorObject $_
    }
}

function Create-ReleaseVersionPullRequest {
    try {
        $repositoryName = Get-SelectedRepositoryName
        $tag = $releaseTagTextBox.Text.Trim()
        $fileVersion = $releaseFileVersionTextBox.Text.Trim()
        $baseBranch = $releaseTargetTextBox.Text.Trim()
        $paths = @(Get-ReleaseVersionPaths)

        if ([string]::IsNullOrWhiteSpace($tag)) { throw "Gib zuerst den neuen Release-Tag an." }
        if ([string]::IsNullOrWhiteSpace($fileVersion)) { throw "Gib die Version für die Versionsdateien an." }
        if ([string]::IsNullOrWhiteSpace($baseBranch)) { throw "Gib den Zielbranch an." }
        if ($paths.Count -eq 0) { throw "Trage mindestens eine Versionsdatei ein." }

        $safeTag = ($tag -replace '[^A-Za-z0-9._-]', '-')
        $branch = "release/$safeTag-$((Get-Date).ToString('yyyyMMddHHmmss'))"
        Set-Status "Erstelle Release-Branch $branch ..."
        [void](New-RepositoryBranch -RepositoryName $repositoryName -BranchName $branch -BaseBranch $baseBranch)

        foreach ($path in $paths) {
            Set-Status "Aktualisiere $path ..."
            $file = Get-RepositoryFileContent -RepositoryName $repositoryName -Path $path -Ref $baseBranch
            if ($null -eq $file) { throw "Versionsdatei '$path' wurde nicht gefunden." }
            $updated = Update-VersionText -Path $path -Content $file.Content -Version $fileVersion
            [void](Set-RepositoryFileContent -RepositoryName $repositoryName -Path $path -Content $updated -CommitMessage "chore(release): set version $fileVersion" -Branch $branch -Sha $file.Sha)
        }

        $body = "Automatisch vom GitHub Manager vorbereitet.`r`n`r`nRelease: $tag`r`nVersionsdateien: $($paths -join ', ')"
        $prUrl = Invoke-Gh -Arguments @('pr','create','--repo',$repositoryName,'--base',$baseBranch,'--head',$branch,'--title',"chore(release): $tag",'--body',$body)
        $prUrl = ([string]$prUrl).Trim()
        Set-Status "Release-PR wurde erstellt."

        [void][System.Windows.Forms.MessageBox]::Show(
            $form,
            "Der Release-PR wurde erstellt. Merge ihn zuerst. Danach Release-Daten neu laden und den Release aus dem gemergten Stand erstellen.`r`n`r`n$prUrl",
            "Release-PR erstellt",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        if (-not [string]::IsNullOrWhiteSpace($prUrl)) { Start-Process $prUrl }
    }
    catch {
        Set-Status "Release-PR konnte nicht erstellt werden."
        Show-Error -Title "Release-PR konnte nicht erstellt werden" -ErrorObject $_
    }
}

function Create-GitHubRelease {
    try {
        $repositoryName = Get-SelectedRepositoryName
        $tag = $releaseTagTextBox.Text.Trim()
        $title = $releaseTitleTextBox.Text.Trim()
        $target = $releaseTargetTextBox.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($tag)) { throw "Gib einen Release-Tag an." }
        if ([string]::IsNullOrWhiteSpace($target)) { throw "Gib einen Zielbranch oder Commit an." }
        if ([string]::IsNullOrWhiteSpace($title)) { $title = $tag }

        $kind = if ($releaseDraftCheckBox.Checked) { 'Draft' } elseif ($releasePrereleaseCheckBox.Checked) { 'Pre-Release' } else { 'Release' }
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $form,
            "$kind '$title' mit Tag '$tag' aus '$target' in $repositoryName erstellen?",
            "Release erstellen",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $args = @('release','create',$tag,'--repo',$repositoryName,'--target',$target,'--title',$title)
        if ($releaseGenerateNotesCheckBox.Checked) { $args += '--generate-notes' }
        if ($releaseDraftCheckBox.Checked) { $args += '--draft' }
        if ($releasePrereleaseCheckBox.Checked) { $args += '--prerelease' }
        if ($releaseFailNoCommitsCheckBox.Checked) { $args += '--fail-on-no-commits' }
        if ($releaseVerifyTagCheckBox.Checked) { $args += '--verify-tag' }

        switch ($releaseLatestComboBox.SelectedIndex) {
            1 { $args += '--latest' }
            2 { $args += '--latest=false' }
        }

        try {
            # gh release create kann ohne Notes-Option interaktiv werden. Die GUI
            # muss vollständig nicht-interaktiv bleiben. Eigene Notizen werden
            # direkt als Argument übergeben; bei aktivierten generierten Notes
            # werden sie von gh als zusätzlicher Text verwendet.
            if (-not [string]::IsNullOrWhiteSpace($releaseNotesTextBox.Text)) {
                $args += @('--notes', [string]$releaseNotesTextBox.Text)
            }
            elseif (-not $releaseGenerateNotesCheckBox.Checked) {
                $args += @('--notes', '')
            }

            foreach ($asset in $releaseAssetsListBox.Items) { $args += [string]$asset }

            Set-Status "Erstelle GitHub-Release ..."
            $result = Invoke-Gh -Arguments $args -AllowEmpty
            Set-Status "Release wurde erstellt."
            Load-ReleaseData

            if (-not [string]::IsNullOrWhiteSpace([string]$result)) {
                $url = ([string]$result).Trim()
                if ($url -match '^https?://') { Start-Process $url }
            }
        }
        finally {
            # Keine temporären Notizdateien erforderlich.
        }
    }
    catch {
        Set-Status "Release konnte nicht erstellt werden."
        Show-Error -Title "Release konnte nicht erstellt werden" -ErrorObject $_
    }
}
