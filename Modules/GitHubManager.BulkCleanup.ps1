# GitHub Manager – repositoryübergreifende Bereinigung.
# Alle Remote-Operationen laufen in getrennten PowerShell-Runspaces.
$script:BulkCleanup = [pscustomobject]@{
    Running=$false; Phase=''; Jobs=@(); Auth=$null; Client=$null; Pool=$null;
    Limiter=$null; Throttle=$null; Cancellation=$null; Progress=$null; Worker='';
    PreviewOptions=$null; Finished=0; Expected=0; CloseWhenDone=$false; ErrorMessage='';
    WorkItems=@(); Options=$null;
    SelectedRepos=([System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase));
    SuppressChecks=$false
}
Add-Type -AssemblyName System.Net.Http
$script:BulkControls = @{}
$script:BulkWorkerFile = Join-Path $PSScriptRoot 'GitHubManager.BulkCleanup.Worker.ps1'

function New-BulkControl {
    param([string]$Type, [string]$Text='', [int]$Width=0)
    $control = New-Object "System.Windows.Forms.$Type"
    if ($null -ne $control.PSObject.Properties['Text']) { $control.Text = $Text }
    if ($Width -gt 0) { $control.Width = $Width }
    return $control
}

function Set-BulkMessage {
    param([string]$Message)
    if ($script:BulkControls.ContainsKey('Status')) { $script:BulkControls.Status.Text = $Message }
    if ($null -ne $statusLabel) { $statusLabel.Text = $Message }
}

function Reset-BulkPreview {
    if ($script:BulkCleanup.Running) { return }
    if ($script:BulkControls.ContainsKey('Grid')) { $script:BulkControls.Grid.Rows.Clear() }
    if ($script:BulkControls.ContainsKey('Delete')) { $script:BulkControls.Delete.Enabled = $false }
    $script:BulkCleanup.PreviewOptions = $null
    Set-BulkMessage 'Bulk-Bereinigung: Neue Vorschau erforderlich.'
}

function Update-BulkRepositories {
    if (-not $script:BulkControls.ContainsKey('RepoList')) { return }
    $list = $script:BulkControls.RepoList
    $allNames = @($script:State.Repositories | ForEach-Object { [string]$_.nameWithOwner } | Where-Object { $_ })
    $allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $allNames) { [void]$allowed.Add($name) }
    foreach ($oldName in @($script:BulkCleanup.SelectedRepos)) {
        if (-not $allowed.Contains($oldName)) { [void]$script:BulkCleanup.SelectedRepos.Remove($oldName) }
    }
    $filter = $script:BulkControls.Filter.Text.Trim()
    $script:BulkCleanup.SuppressChecks = $true
    try {
        $list.BeginUpdate()
        $list.Items.Clear()
        foreach ($name in $allNames) {
            if ($filter -and $name.IndexOf($filter, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            [void]$list.Items.Add($name, $script:BulkCleanup.SelectedRepos.Contains($name))
        }
    }
    finally {
        $list.EndUpdate()
        $script:BulkCleanup.SuppressChecks = $false
    }
    $script:BulkControls.RepoCount.Text = ('{0} von {1} Repositories gewählt' -f $script:BulkCleanup.SelectedRepos.Count, $allNames.Count)
}

function Set-BulkRepositorySelection {
    param([ValidateSet('All','None','Visible')][string]$Mode)
    if ($script:BulkCleanup.Running) { return }
    if ($Mode -eq 'All') {
        foreach ($repo in @($script:State.Repositories)) { [void]$script:BulkCleanup.SelectedRepos.Add([string]$repo.nameWithOwner) }
    }
    elseif ($Mode -eq 'Visible') {
        foreach ($repo in @($script:BulkControls.RepoList.Items)) { [void]$script:BulkCleanup.SelectedRepos.Add([string]$repo) }
    }
    else { $script:BulkCleanup.SelectedRepos.Clear() }
    Update-BulkRepositories
    Reset-BulkPreview
}

function Get-BulkOptions {
    $c = $script:BulkControls
    $kinds = @()
    foreach ($name in @('Runs','Caches','Artifacts','Releases')) { if ($c[$name].Checked) { $kinds += $name } }
    if ($kinds.Count -eq 0) { throw 'Wähle mindestens eine Bereinigungsart aus.' }
    return @{
        Kinds=$kinds; RunsAge=[int]$c.RunsAge.Value; KeepRuns=[int]$c.KeepRuns.Value;
        MaxRuns=[int]$c.MaxRuns.Value; CachesAge=[int]$c.CachesAge.Value;
        KeepCaches=[int]$c.KeepCaches.Value; ProtectDefaultCache=$c.ProtectDefaultCache.Checked;
        ArtifactsAge=[int]$c.ArtifactsAge.Value; KeepArtifacts=[int]$c.KeepArtifacts.Value;
        ReleasesAge=[int]$c.ReleasesAge.Value; KeepReleases=[int]$c.KeepReleases.Value;
        DeleteReleaseTags=$c.DeleteReleaseTags.Checked
    }
}

function Set-BulkEnabled {
    param([bool]$Value)
    $c = $script:BulkControls
    foreach ($key in @('RepoList','Filter','All','None','Visible','Runs','Caches','Artifacts','Releases',
            'RunsAge','KeepRuns','MaxRuns','CachesAge','KeepCaches','ProtectDefaultCache',
            'ArtifactsAge','KeepArtifacts','ReleasesAge','KeepReleases','DeleteReleaseTags')) {
        $c[$key].Enabled = $Value
    }
    $c.Preview.Enabled = $Value
    $c.Delete.Enabled = $Value -and $null -ne $script:BulkCleanup.PreviewOptions
    $c.Cancel.Enabled = -not $Value
}

function Dispose-BulkRunspaces {
    foreach ($job in @($script:BulkCleanup.Jobs)) {
        try { $job.PS.Dispose() } catch {}
    }
    if ($null -ne $script:BulkCleanup.Auth) {
        try { $script:BulkCleanup.Auth.PS.Dispose() } catch {}
    }
    if ($null -ne $script:BulkCleanup.Pool) {
        try { $script:BulkCleanup.Pool.Close() } catch {}
        try { $script:BulkCleanup.Pool.Dispose() } catch {}
    }
    if ($null -ne $script:BulkCleanup.Client) { $script:BulkCleanup.Client.Dispose() }
    if ($null -ne $script:BulkCleanup.Limiter) { $script:BulkCleanup.Limiter.Dispose() }
    if ($null -ne $script:BulkCleanup.Cancellation) { $script:BulkCleanup.Cancellation.Dispose() }
    $script:BulkCleanup.Jobs = @()
    $script:BulkCleanup.Pool = $null
    $script:BulkCleanup.Client = $null
    $script:BulkCleanup.Auth = $null
    $script:BulkCleanup.Limiter = $null
    $script:BulkCleanup.Throttle = $null
    $script:BulkCleanup.Cancellation = $null
    $script:BulkCleanup.Progress = $null
}

function Complete-BulkBatch {
    $wasPhase = $script:BulkCleanup.Phase
    $cancelled = $false
    if ($null -ne $script:BulkCleanup.Cancellation) { $cancelled = $script:BulkCleanup.Cancellation.IsCancellationRequested }
    Dispose-BulkRunspaces
    $script:BulkCleanup.Running = $false
    $script:BulkCleanup.Phase = ''
    Set-BulkEnabled -Value $true
    if ($script:BulkCleanup.ErrorMessage) {
        $script:BulkCleanup.PreviewOptions = $null
        $script:BulkControls.Delete.Enabled = $false
        Set-BulkMessage $script:BulkCleanup.ErrorMessage
    }
    elseif ($wasPhase -eq 'Execute') {
        $script:BulkCleanup.PreviewOptions = $null
        $script:BulkControls.Delete.Enabled = $false
        if ($cancelled) {
            Set-BulkMessage 'Bulk-Löschlauf abgebrochen. Bereits erfolgte Deletes bleiben bestehen; fuer den naechsten Lauf ist eine neue Vorschau erforderlich.'
        }
        else { Set-BulkMessage 'Bulk-Löschlauf beendet. Für einen weiteren Lauf neue Vorschau erstellen.' }
    }
    elseif ($cancelled) {
        $script:BulkCleanup.PreviewOptions = $null
        $script:BulkControls.Delete.Enabled = $false
        Set-BulkMessage 'Bulk-Lauf abgebrochen; noch nicht gestartete Löschvorgänge wurden übersprungen.'
    }
    else {
        $ready = @($script:BulkControls.Grid.Rows | Where-Object { $null -ne $_.Tag -and $_.Tag.Count -gt 0 }).Count
        $script:BulkControls.Delete.Enabled = ($ready -gt 0)
        Set-BulkMessage "Vorschau fertig. $ready Bereinigungsgruppen mit Löschkandidaten."
    }
    if ($script:BulkCleanup.CloseWhenDone) { $script:BulkCleanup.CloseWhenDone=$false; $form.Close() }
}

function Start-BulkWorkers {
    param([string]$Token)
    try {
        if ($script:BulkCleanup.Cancellation.IsCancellationRequested) { Complete-BulkBatch; return }
        $client = [System.Net.Http.HttpClient]::new()
        $client.BaseAddress = [uri]'https://api.github.com/'
        $client.Timeout = [timespan]::FromSeconds(90)
        $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token.Trim())
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('GitHub-Manager-Bulk/4.2')
        $client.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
        [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('X-GitHub-Api-Version', $script:ApiVersion)
        $script:BulkCleanup.Client = $client
        $script:BulkCleanup.Limiter = [System.Threading.SemaphoreSlim]::new(5, 5)
        # Loesch-Startzeitpunkte global staffeln (ca. 2,8/s), Requests bleiben parallel.
        $script:BulkCleanup.Throttle = [pscustomobject]@{ SyncRoot=(New-Object object); NextTicks=([long]0) }
        $script:BulkCleanup.Progress = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $maxWorkers = [math]::Max(1, [math]::Min(32, $script:BulkCleanup.Expected))
        $pool = [runspacefactory]::CreateRunspacePool(1,$maxWorkers)
        $pool.Open()
        $script:BulkCleanup.Pool = $pool
        foreach ($workItem in @($script:BulkCleanup.WorkItems)) {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($script:BulkCleanup.Worker)
            [void]$ps.AddArgument($script:BulkCleanup.Phase)
            [void]$ps.AddArgument([string]$workItem.Repo)
            [void]$ps.AddArgument($script:BulkCleanup.Options)
            [void]$ps.AddArgument([object[]]$workItem.Plans)
            [void]$ps.AddArgument($client)
            [void]$ps.AddArgument($script:BulkCleanup.Limiter)
            [void]$ps.AddArgument($script:BulkCleanup.Throttle)
            [void]$ps.AddArgument($script:BulkCleanup.Cancellation.Token)
            [void]$ps.AddArgument($script:BulkCleanup.Progress)
            $handle = $ps.BeginInvoke()
            $script:BulkCleanup.Jobs += [pscustomobject]@{PS=$ps; Handle=$handle; Repo=[string]$workItem.Repo; Finished=$false}
        }
        Set-BulkMessage "$($script:BulkCleanup.Expected) Repository-Jobs gestartet; max. 5 API-Requests gleichzeitig und gepacete DELETEs."
    }
    catch {
        $script:BulkCleanup.ErrorMessage = "Bulk-Start fehlgeschlagen: $($_.Exception.Message)"
        Write-Log -Level 'ERROR' -Message $script:BulkCleanup.ErrorMessage
        $script:BulkCleanup.Cancellation.Cancel()
        if ($script:BulkCleanup.Jobs.Count -eq 0) { Complete-BulkBatch }
    }
}

function Process-BulkResult {
    param([object]$Result)
    $grid = $script:BulkControls.Grid
    $kind = [string]$Result.Kind
    $repo = [string]$Result.Repository
    if ($script:BulkCleanup.Phase -eq 'Preview') {
        $errorText = [string]$Result.Error
        $status = if ($errorText) { 'Fehler' } else { 'Vorschau' }
        $note = if ($errorText) { $errorText } else { [string]$Result.Note }
        $idx = $grid.Rows.Add(($Result.Count -gt 0 -and -not $errorText), $repo, $kind,
            [string]$Result.Scanned, [string]$Result.Protected, [string]$Result.Count,
            ('{0:N1} MB' -f ($Result.Bytes / 1MB)), $status, $note)
        $grid.Rows[$idx].Tag = $Result
        if ($errorText) { $grid.Rows[$idx].DefaultCellStyle.ForeColor = [System.Drawing.Color]::Firebrick }
    }
    else {
        foreach ($row in @($grid.Rows)) {
            if ($null -ne $row.Tag -and [string]$row.Tag.Repository -eq $repo -and [string]$row.Tag.Kind -eq $kind) {
                $row.Cells['BulkState'].Value = 'Gelöscht: {0}, Fehler: {1}, übersprungen: {2}' -f $Result.Deleted, $Result.Failed, $Result.Skipped
                if ([string]$Result.Error) {
                    $row.Cells['BulkNote'].Value = [string]$Result.Error
                    $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Firebrick
                }
                break
            }
        }
    }
}

function Poll-BulkCleanup {
    if (-not $script:BulkCleanup.Running) { return }
    if ($null -ne $script:BulkCleanup.Auth) {
        if (-not $script:BulkCleanup.Auth.Handle.IsCompleted) { return }
        $authJob = $script:BulkCleanup.Auth
        $script:BulkCleanup.Auth = $null
        try {
            $authOutput = @($authJob.PS.EndInvoke($authJob.Handle))
            if ($authOutput.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$authOutput[0])) { throw 'gh auth token lieferte kein Token.' }
            Start-BulkWorkers -Token ([string]$authOutput[0])
        }
        catch {
            $script:BulkCleanup.ErrorMessage = "Authentifizierung fehlgeschlagen: $($_.Exception.Message)"
            Write-Log -Level 'ERROR' -Message $script:BulkCleanup.ErrorMessage
            $script:BulkCleanup.Cancellation.Cancel()
            Complete-BulkBatch
        }
        finally { $authJob.PS.Dispose() }
        return
    }
    if ($null -eq $script:BulkCleanup.Pool) { return }
    $item = $null
    $handled = 0
    while ($handled -lt 100 -and $script:BulkCleanup.Progress.TryDequeue([ref]$item)) {
        $handled++
        $script:BulkControls.Activity.Text = "{0}: {1} – {2}" -f $item.Repository,$item.Kind,$item.Message
    }
    foreach ($job in @($script:BulkCleanup.Jobs)) {
        if ($job.Finished -or -not $job.Handle.IsCompleted) { continue }
        $job.Finished = $true
        $script:BulkCleanup.Finished++
        try {
            $output = @($job.PS.EndInvoke($job.Handle))
            foreach ($result in $output) {
                if ($null -ne $result) { Process-BulkResult -Result $result }
            }
            if ($job.PS.HadErrors) { throw (($job.PS.Streams.Error | ForEach-Object { $_.ToString() }) -join '; ') }
        }
        catch {
            $err = $_.Exception.Message
            $script:BulkControls.Activity.Text = "$($job.Repo): $err"
            if ($script:BulkCleanup.Phase -eq 'Preview') {
                $idx = $script:BulkControls.Grid.Rows.Add($false,$job.Repo,'Gesamt','0','0','0','0 MB','Fehler',$err)
                $script:BulkControls.Grid.Rows[$idx].DefaultCellStyle.ForeColor = [System.Drawing.Color]::Firebrick
            }
        }
        finally { $job.PS.Dispose() }
    }
    $script:BulkControls.Progress.Text = '{0}/{1} Repositories abgeschlossen' -f $script:BulkCleanup.Finished,$script:BulkCleanup.Expected
    if ($script:BulkCleanup.Finished -ge $script:BulkCleanup.Expected) { Complete-BulkBatch }
}

function Start-BulkBatch {
    param([ValidateSet('Preview','Execute')][string]$Mode, [object[]]$WorkItems, [hashtable]$Options)
    if ($script:BulkCleanup.Running) { return }
    $gh = Get-GhExecutable
    if (-not $gh) { throw 'GitHub CLI wurde nicht gefunden.' }
    if (@($WorkItems).Count -lt 1) { throw 'Es sind keine Repository-Jobs vorhanden.' }
    $script:BulkCleanup.ErrorMessage = ''
    $script:BulkCleanup.Phase = $Mode
    $script:BulkCleanup.WorkItems = @($WorkItems)
    $script:BulkCleanup.Options = $Options
    $script:BulkCleanup.Expected = @($WorkItems).Count
    $script:BulkCleanup.Finished = 0
    $script:BulkCleanup.Worker = Get-Content -LiteralPath $script:BulkWorkerFile -Raw -Encoding UTF8
    $script:BulkCleanup.Cancellation = [System.Threading.CancellationTokenSource]::new()
    $script:BulkCleanup.Running = $true
    Set-BulkEnabled -Value $false
    $script:BulkControls.Progress.Text = "0/$($script:BulkCleanup.Expected) Repositories abgeschlossen"
    $script:BulkControls.Activity.Text = 'GitHub-Token wird im Hintergrund geladen ...'
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript('param([string]$gh) $ErrorActionPreference="Stop"; $token = (& $gh auth token --hostname github.com 2>&1); if ($LASTEXITCODE -ne 0) { throw ($token -join " ") }; $token')
        [void]$ps.AddArgument([string]$gh)
        $script:BulkCleanup.Auth = [pscustomobject]@{PS=$ps; Handle=$ps.BeginInvoke()}
    }
    catch {
        Complete-BulkBatch
        throw
    }
}

function Assert-BulkWriteAllowed {
    param([string]$Repository)
    if (-not $script:BulkCleanup.Running -or $script:BulkCleanup.Phase -ne 'Execute') { return }
    foreach ($job in @($script:BulkCleanup.WorkItems)) {
        if ([string]$job.Repo -ieq $Repository) {
            throw "Fuer $Repository laeuft bereits eine Bulk-Bereinigung. Konkurrierende Schreiboperationen auf dasselbe Repository sind gesperrt."
        }
    }
}

function Preview-BulkCleanup {
    try {
        $repos = @($script:BulkCleanup.SelectedRepos | Sort-Object)
        if ($repos.Count -eq 0) { throw 'Wähle mindestens ein Repository aus.' }
        $options = Get-BulkOptions
        $script:BulkControls.Grid.Rows.Clear()
        $script:BulkCleanup.PreviewOptions = $null
        $script:BulkControls.Delete.Enabled = $false
        $work = @(foreach ($repo in $repos) { [pscustomobject]@{Repo=$repo; Plans=@()} })
        Start-BulkBatch -Mode Preview -WorkItems $work -Options $options
        $script:BulkCleanup.PreviewOptions = $options
    }
    catch { Show-Error -Title 'Bulk-Vorschau konnte nicht gestartet werden' -ErrorObject $_ }
}

function Execute-BulkCleanup {
    try {
        if ($script:BulkCleanup.Running -or $null -eq $script:BulkCleanup.PreviewOptions) { throw 'Lade zuerst eine vollständige Vorschau.' }
        [void]$script:BulkControls.Grid.EndEdit()
        $byRepo = @{}
        $total = 0
        $tagCount = 0
        foreach ($row in @($script:BulkControls.Grid.Rows)) {
            if ($row.IsNewRow -or -not [bool]$row.Cells[0].Value -or $null -eq $row.Tag) { continue }
            $preview = $row.Tag
            if ([string]$preview.Error -or $preview.Count -le 0) { continue }
            $repo = [string]$preview.Repository
            if (-not $byRepo.ContainsKey($repo)) { $byRepo[$repo] = New-Object System.Collections.Generic.List[object] }
            $byRepo[$repo].Add([pscustomobject]@{Kind=[string]$preview.Kind; Candidates=@($preview.Candidates)})
            $total += [int]$preview.Count
            if ([string]$preview.Kind -eq 'Releases') {
                $tagCount += @($preview.Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Tag) }).Count
            }
        }
        if ($total -le 0) { throw 'Keine Löschkandidaten markiert.' }
        $expectedText = "DELETE $total"
        if (-not (Confirm-Deletion -Title 'Bulk-Bereinigung: endgültig löschen' -ExpectedText $expectedText `
            -Message "$total Elemente aus $($byRepo.Count) Repositories werden zur Löschung vorgemerkt. Zusätzlich werden bis zu $tagCount zugehörige Tags gelöscht (nur bei explizitem Opt-in). Vor JEDEM Löschlauf werden alle Schutzregeln nochmals geprüft. GitHub bietet dafür keinen allgemeinen Papierkorb.")) { return }
        $work = @(foreach ($repo in @($byRepo.Keys | Sort-Object)) { [pscustomobject]@{Repo=$repo; Plans=@($byRepo[$repo].ToArray())} })
        Start-BulkBatch -Mode Execute -WorkItems $work -Options $script:BulkCleanup.PreviewOptions
    }
    catch { Show-Error -Title 'Bulk-Bereinigung konnte nicht gestartet werden' -ErrorObject $_ }
}

function Export-BulkCleanupReport {
    try {
        [void]$script:BulkControls.Grid.EndEdit()
        $rows = @($script:BulkControls.Grid.Rows | Where-Object { -not $_.IsNewRow })
        if ($rows.Count -eq 0) { throw 'Noch keine Vorschau oder Ergebnisse vorhanden.' }
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Title = 'Bulk-Bereinigungsreport exportieren'
        $dialog.Filter = 'CSV-Datei (*.csv)|*.csv'
        $dialog.FileName = 'github-bulk-cleanup-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
        if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $report = @(foreach ($row in $rows) {
            [pscustomobject]@{
                Markiert=[bool]$row.Cells[0].Value
                Repository=[string]$row.Cells['BulkRepo'].Value
                Kategorie=[string]$row.Cells['BulkKind'].Value
                Geladen=[string]$row.Cells['BulkScanned'].Value
                Geschuetzt=[string]$row.Cells['BulkProtected'].Value
                Kandidaten=[string]$row.Cells['BulkCandidates'].Value
                Groesse=[string]$row.Cells['BulkSize'].Value
                Status=[string]$row.Cells['BulkState'].Value
                Details=[string]$row.Cells['BulkNote'].Value
            }
        })
        $report | Export-Csv -LiteralPath $dialog.FileName -Encoding UTF8 -NoTypeInformation
        Set-BulkMessage ("CSV-Bericht exportiert: $($report.Count) Zeilen")
    }
    catch { Show-Error -Title 'Bulk-Bericht konnte nicht exportiert werden' -ErrorObject $_ }
}

function Initialize-BulkCleanupTab {
    param([System.Windows.Forms.TabControl]$Tabs)
    $tab = New-BulkControl -Type 'TabPage' -Text 'Bulk-Bereinigung'
    $Tabs.TabPages.Add($tab)
    $base = New-BulkControl -Type 'TableLayoutPanel'
    $base.Dock='Fill'; $base.RowCount=1; $base.ColumnCount=2
    [void]$base.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,330)))
    [void]$base.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
    $tab.Controls.Add($base)

    $left = New-BulkControl -Type 'TableLayoutPanel'
    $left.Dock='Fill'; $left.RowCount=5; $left.ColumnCount=1; $left.Padding=New-Object System.Windows.Forms.Padding(8)
    [void]$left.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,32)))
    [void]$left.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
    [void]$left.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$left.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,40)))
    [void]$left.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,28)))
    $base.Controls.Add($left,0,0)
    $caption=New-BulkControl -Type Label -Text 'Ziel-Repositories (Mehrfachauswahl)'
    $caption.Dock='Fill'; $left.Controls.Add($caption,0,0)
    $filter=New-BulkControl -Type TextBox
    $filter.Dock='Fill'; $left.Controls.Add($filter,0,1); $script:BulkControls.Filter=$filter
    $list=New-BulkControl -Type CheckedListBox
    $list.Dock='Fill'; $list.CheckOnClick=$true; $list.IntegralHeight=$false
    $left.Controls.Add($list,0,2); $script:BulkControls.RepoList=$list
    $buttons=New-BulkControl -Type FlowLayoutPanel
    $buttons.Dock='Fill'; $buttons.WrapContents=$false; $left.Controls.Add($buttons,0,3)
    foreach ($item in @(@('All','Alle'),@('None','Keine'),@('Visible','Gefilterte'))) {
        $btn=New-BulkControl -Type Button -Text $item[1] -Width 91
        $btn.Height=29; $buttons.Controls.Add($btn); $script:BulkControls[$item[0]]=$btn
    }
    $count=New-BulkControl -Type Label -Text '0 Repositories gewählt'
    $count.Dock='Fill'; $left.Controls.Add($count,0,4); $script:BulkControls.RepoCount=$count

    $right=New-BulkControl -Type TableLayoutPanel
    $right.Dock='Fill'; $right.RowCount=5; $right.ColumnCount=1
    [void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,150)))
    [void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,46)))
    [void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,27)))
    [void]$right.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,27)))
    $base.Controls.Add($right,1,0)
    $settings=New-BulkControl -Type FlowLayoutPanel
    $settings.Dock='Fill'; $settings.WrapContents=$true; $settings.AutoScroll=$true
    $right.Controls.Add($settings,0,0)
    foreach ($entry in @(@('Runs','Workflow-Runs', $true),@('Caches','Caches', $false),@('Artifacts','Artefakte',$false),@('Releases','Drafts/Prereleases',$false))) {
        $check=New-BulkControl -Type CheckBox -Text $entry[1] -Width 150
        $check.Checked=[bool]$entry[2]; $check.Height=28; $settings.Controls.Add($check); $script:BulkControls[$entry[0]]=$check
    }
    $numericDefs=@(
        @('RunsAge','Runs älter als (Tage)',14,0,3650),@('KeepRuns','Runs je Workflow behalten',10,0,1000),
        @('MaxRuns','Max. Runs / Repo',20000,100,100000),@('CachesAge','Caches ungenutzt (Tage)',30,0,3650),
        @('KeepCaches','Caches je Key/Ref behalten',1,0,1000),@('ArtifactsAge','Artefakte älter (Tage)',30,0,3650),
        @('KeepArtifacts','Artefakte je Name behalten',1,0,1000),@('ReleasesAge','Draft/Prerelease älter (Tage)',90,0,3650),
        @('KeepReleases','Neueste Releases behalten',5,0,1000)
    )
    foreach ($spec in $numericDefs) {
        $panel=New-BulkControl -Type FlowLayoutPanel -Width 266
        $panel.Height=30; $panel.WrapContents=$false
        $label=New-BulkControl -Type Label -Text $spec[1] -Width 196
        $label.Height=26; $panel.Controls.Add($label)
        $value=New-BulkControl -Type NumericUpDown -Width 65
        $value.Minimum=[decimal]$spec[3]; $value.Maximum=[decimal]$spec[4]; $value.Value=[decimal]$spec[2]
        $panel.Controls.Add($value); $script:BulkControls[$spec[0]]=$value; $settings.Controls.Add($panel)
    }
    foreach ($setting in @(@('ProtectDefaultCache','Caches des Default Branch schützen',$true),
                           @('DeleteReleaseTags','Zusätzlich Tags von gelöschten Drafts/Prereleases löschen (Risiko)', $false))) {
        $check=New-BulkControl -Type CheckBox -Text $setting[1] -Width 475
        $check.Height=27; $check.Checked=[bool]$setting[2]
        $settings.Controls.Add($check); $script:BulkControls[$setting[0]]=$check
    }
    $actions=New-BulkControl -Type FlowLayoutPanel
    $actions.Dock='Fill'; $actions.WrapContents=$false; $right.Controls.Add($actions,0,1)
    foreach ($b in @(@('Preview','Vorschau aller Repos',174),@('Delete','Ausgewählte Kandidaten löschen',228),@('Cancel','Abbrechen',118),@('Export','CSV exportieren',137))) {
        $button=New-BulkControl -Type Button -Text $b[1] -Width $b[2]
        $button.Height=35; $actions.Controls.Add($button); $script:BulkControls[$b[0]]=$button
    }
    $script:BulkControls.Delete.Enabled=$false
    $script:BulkControls.Cancel.Enabled=$false
    $grid=New-DataGrid
    $grid.AllowUserToAddRows=$false
    $grid.MultiSelect=$false
    $grid.EditMode=[System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
    Add-GridCheckColumn -Grid $grid
    foreach ($col in @(@('BulkRepo','Repository',215),@('BulkKind','Kategorie',107),@('BulkScanned','Geladen',75),
                     @('BulkProtected','Geschützt',78),@('BulkCandidates','Kandidaten',85),@('BulkSize','Größe',94),
                     @('BulkState','Status',165),@('BulkNote','Hinweis / Fehler',300))) {
        Add-GridTextColumn -Grid $grid -Name $col[0] -Header $col[1] -Width ([int]$col[2])
    }
    $grid.Columns['BulkNote'].AutoSizeMode=[System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    $right.Controls.Add($grid,0,2); $script:BulkControls.Grid=$grid
    $progress=New-BulkControl -Type Label -Text 'Bereit – Vorschau und Löschung erfolgen parallel nach Repository.'
    $progress.Dock='Fill'; $right.Controls.Add($progress,0,3); $script:BulkControls.Progress=$progress
    $activity=New-BulkControl -Type Label -Text 'Vor der Löschung ist eine Vorschau und explizite Bestätigung erforderlich.'
    $activity.Dock='Fill'; $activity.AutoEllipsis=$true; $right.Controls.Add($activity,0,4); $script:BulkControls.Activity=$activity
    $script:BulkControls.Status=$activity

    $filter.Add_TextChanged({ Update-BulkRepositories })
    $list.Add_ItemCheck({ param($sender,$eventArgs)
        if ($script:BulkCleanup.SuppressChecks -or $script:BulkCleanup.Running) { return }
        $name=[string]$sender.Items[$eventArgs.Index]
        if ($eventArgs.NewValue -eq [System.Windows.Forms.CheckState]::Checked) {
            [void]$script:BulkCleanup.SelectedRepos.Add($name)
        } else { [void]$script:BulkCleanup.SelectedRepos.Remove($name) }
        $script:BulkControls.RepoCount.Text=('{0} Repositories gewählt' -f $script:BulkCleanup.SelectedRepos.Count)
        Reset-BulkPreview
    })
    $script:BulkControls.All.Add_Click({ Set-BulkRepositorySelection -Mode All })
    $script:BulkControls.None.Add_Click({ Set-BulkRepositorySelection -Mode None })
    $script:BulkControls.Visible.Add_Click({ Set-BulkRepositorySelection -Mode Visible })
    $script:BulkControls.Preview.Add_Click({ Preview-BulkCleanup })
    $script:BulkControls.Delete.Add_Click({ Execute-BulkCleanup })
    $script:BulkControls.Cancel.Add_Click({ if ($script:BulkCleanup.Running) { $script:BulkCleanup.Cancellation.Cancel(); Set-BulkMessage 'Abbruch angefordert ...' } })
    $script:BulkControls.Export.Add_Click({ Export-BulkCleanupReport })
    foreach ($key in @('Runs','Caches','Artifacts','Releases','ProtectDefaultCache','DeleteReleaseTags')) {
        $script:BulkControls[$key].Add_CheckedChanged({ Reset-BulkPreview })
    }
    foreach ($key in @('RunsAge','KeepRuns','MaxRuns','CachesAge','KeepCaches','ArtifactsAge','KeepArtifacts','ReleasesAge','KeepReleases')) {
        $script:BulkControls[$key].Add_ValueChanged({ Reset-BulkPreview })
    }
    $poller=New-Object System.Windows.Forms.Timer
    $poller.Interval=220
    $poller.Add_Tick({
        try { Poll-BulkCleanup }
        catch {
            Write-Log -Level 'ERROR' -Message ('Bulk-Polling: ' + $_.Exception.Message)
            if ($script:BulkCleanup.Running -and $null -ne $script:BulkCleanup.Cancellation) {
                $script:BulkCleanup.Cancellation.Cancel()
            }
            Set-BulkMessage ('Bulk-Fehler: ' + $_.Exception.Message)
        }
    })
    $poller.Start()
    $script:BulkControls.Timer=$poller
}