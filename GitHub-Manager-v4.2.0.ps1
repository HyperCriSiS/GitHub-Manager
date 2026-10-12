#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppVersion = "4.2.0-preview"
$script:LogPath = Join-Path ([System.IO.Path]::GetTempPath()) "GitHub-Manager-v4.2.0.log"
$script:AppDataPath = Join-Path $env:APPDATA "GitHub Manager"
$script:TemplatesPath = Join-Path $script:AppDataPath "templates.json"

$script:State = [ordered]@{
    Login        = $null
    Repositories = @()
    GhExecutable = $null
    Releases     = @()
    Tags         = @()
    Templates    = @()
}

$script:ApiVersion = "2026-03-10"

$moduleRoot = Join-Path $PSScriptRoot "Modules"
. (Join-Path $moduleRoot "GitHubManager.Extensions.ps1")
. (Join-Path $moduleRoot "GitHubManager.Release.ps1")
. (Join-Path $moduleRoot "GitHubManager.Templates.ps1")
. (Join-Path $moduleRoot "GitHubManager.BulkCleanup.ps1")

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    try {
        $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    }
    catch {
        # Logging darf die Anwendung niemals blockieren.
    }
}

function Get-GhExecutable {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:State.GhExecutable)) {
        if (Test-Path -LiteralPath ([string]$script:State.GhExecutable)) {
            return [string]$script:State.GhExecutable
        }
    }

    $command = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $candidate = if (-not [string]::IsNullOrWhiteSpace([string]$command.Path)) {
            [string]$command.Path
        }
        else {
            [string]$command.Definition
        }

        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $script:State.GhExecutable = $candidate
            return $candidate
        }
    }

    $candidates = @()

    if (-not [string]::IsNullOrWhiteSpace([string]$env:ProgramFiles)) {
        $candidates += Join-Path $env:ProgramFiles "GitHub CLI\gh.exe"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]${env:ProgramFiles(x86)})) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} "GitHub CLI\gh.exe"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$env:LOCALAPPDATA)) {
        $candidates += Join-Path $env:LOCALAPPDATA "Programs\GitHub CLI\gh.exe"
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            $script:State.GhExecutable = $candidate
            return $candidate
        }
    }

    return $null
}

function Open-DiagnosticLog {
    try {
        if (-not (Test-Path -LiteralPath $script:LogPath)) {
            Set-Content -LiteralPath $script:LogPath -Value "Noch keine Diagnoseeinträge vorhanden." -Encoding UTF8
        }

        Start-Process notepad.exe -ArgumentList @($script:LogPath)
    }
    catch {
        Show-Error -Title "Diagnoselog konnte nicht geöffnet werden" -ErrorObject $_
    }
}

function Invoke-Gh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$AllowEmpty
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        $ghExecutable = Get-GhExecutable
        if ([string]::IsNullOrWhiteSpace([string]$ghExecutable)) {
            throw "GitHub CLI (gh) wurde nicht gefunden."
        }

        Write-Log -Message ("gh " + ($Arguments -join " "))
        $output = @(& $ghExecutable @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    if ($exitCode -ne 0) {
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = "GitHub CLI wurde mit Exitcode $exitCode beendet."
        }

        Write-Log -Level "ERROR" -Message $text
        throw $text
    }

    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    return $text
}

function Write-FlattenedJsonResult {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return
    }

    # Windows PowerShell 5.1 gibt eine JSON-Liste als EIN Object[]-Objekt aus.
    # Wird dieses Objekt unverändert aus einer Funktion zurückgegeben, sieht der
    # Aufrufer deshalb nur ein Element: die komplette Liste. PowerShell 7
    # verhält sich an dieser Stelle anders. Durch die explizite Enumeration
    # erhalten beide Versionen dieselbe, erwartbare Ausgabe.
    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            Write-FlattenedJsonResult -Value $item
        }
        return
    }

    Write-Output -NoEnumerate $Value
}

function Invoke-GhJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $text = Invoke-Gh -Arguments $Arguments -AllowEmpty

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    try {
        $parsed = ConvertFrom-Json -InputObject $text
    }
    catch {
        Write-Log -Level "ERROR" -Message ("Ungültige JSON-Ausgabe von gh: " + $_.Exception.Message)
        throw
    }

    Write-FlattenedJsonResult -Value $parsed
}

function Get-ApiArguments {
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        [string]$Method = "GET",

        [string[]]$Fields = @(),

        [switch]$Silent
    )

    $arguments = @(
        "api",
        "--method", $Method,
        "-H", "Accept: application/vnd.github+json",
        "-H", "X-GitHub-Api-Version: $script:ApiVersion",
        $Endpoint
    )

    foreach ($field in $Fields) {
        $arguments += @("-F", $field)
    }

    if ($Silent) {
        $arguments += "--silent"
    }

    return $arguments
}

function Invoke-GhApiJson {
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        [string]$Method = "GET",

        [string[]]$Fields = @(),

        [switch]$Paginate,

        [switch]$Slurp
    )

    $arguments = Get-ApiArguments -Endpoint $Endpoint -Method $Method -Fields $Fields

    if ($Paginate) {
        $arguments += "--paginate"
    }

    if ($Slurp) {
        $arguments += "--slurp"
    }

    return Invoke-GhJson -Arguments $arguments
}

function Invoke-GhApiNoContent {
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateSet("POST", "PUT", "PATCH", "DELETE")]
        [string]$Method,

        [string[]]$Fields = @()
    )

    $arguments = Get-ApiArguments -Endpoint $Endpoint -Method $Method -Fields $Fields -Silent
    [void](Invoke-Gh -Arguments $arguments -AllowEmpty)
}


function Get-GitHubAccessToken {
    $token = Invoke-Gh -Arguments @("auth", "token", "--hostname", "github.com")
    $token = ([string]$token).Trim()

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "GitHub CLI lieferte kein Zugriffstoken. Melde Dich erneut an."
    }

    return $token
}

function New-GitHubApiClient {
    Add-Type -AssemblyName System.Net.Http

    # Windows PowerShell 5.1 verwendet je nach System noch ältere TLS-Vorgaben.
    [System.Net.ServicePointManager]::SecurityProtocol = (
        [System.Net.ServicePointManager]::SecurityProtocol -bor
        [System.Net.SecurityProtocolType]::Tls12
    )

    $token = Get-GitHubAccessToken
    $client = [System.Net.Http.HttpClient]::new()
    $client.BaseAddress = [System.Uri]::new("https://api.github.com/")
    $client.Timeout = [TimeSpan]::FromSeconds(60)
    $client.DefaultRequestHeaders.Authorization =
        [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $token)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("GitHub-Manager/$script:AppVersion")
    $client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json")
    [void]$client.DefaultRequestHeaders.TryAddWithoutValidation(
        "X-GitHub-Api-Version",
        $script:ApiVersion
    )

    return $client
}

function Get-GitHubRetryDelaySeconds {
    param(
        [System.Net.Http.HttpResponseMessage]$Response,
        [int]$Attempt
    )

    if ($null -ne $Response -and $null -ne $Response.Headers.RetryAfter) {
        if ($null -ne $Response.Headers.RetryAfter.Delta) {
            return [Math]::Max(1, [Math]::Ceiling($Response.Headers.RetryAfter.Delta.TotalSeconds))
        }

        if ($null -ne $Response.Headers.RetryAfter.Date) {
            $seconds = ($Response.Headers.RetryAfter.Date.UtcDateTime - [datetime]::UtcNow).TotalSeconds
            return [Math]::Max(1, [Math]::Ceiling($seconds))
        }
    }

    return [Math]::Min(30, [Math]::Pow(2, [Math]::Max(0, $Attempt - 1)))
}

function Invoke-GitHubDeleteRequest {
    param(
        [Parameter(Mandatory)]
        [System.Net.Http.HttpClient]$Client,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [int]$MaximumAttempts = 5
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Delete,
            $Endpoint
        )
        $response = $null

        try {
            $response = $Client.SendAsync($request).GetAwaiter().GetResult()
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $statusCode = [int]$response.StatusCode

            if ($response.IsSuccessStatusCode) {
                return
            }

            $isRateLimited = (
                $statusCode -eq 429 -or
                ($statusCode -eq 403 -and $body -match '(?i)rate limit|abuse detection')
            )

            $isTemporaryServerError = $statusCode -in @(502, 503, 504)

            if (($isRateLimited -or $isTemporaryServerError) -and $attempt -lt $MaximumAttempts) {
                $delay = Get-GitHubRetryDelaySeconds -Response $response -Attempt $attempt
                Write-Log -Level "WARN" -Message "DELETE $Endpoint erhielt HTTP $statusCode. Neuer Versuch in $delay Sekunden."
                Start-Sleep -Seconds $delay
                continue
            }

            $details = if ([string]::IsNullOrWhiteSpace($body)) {
                $response.ReasonPhrase
            }
            else {
                $body
            }

            throw "GitHub API meldete HTTP $statusCode für DELETE $Endpoint`: $details"
        }
        catch [System.Net.Http.HttpRequestException] {
            if ($attempt -ge $MaximumAttempts) {
                throw
            }

            $delay = [Math]::Min(30, [Math]::Pow(2, [Math]::Max(0, $attempt - 1)))
            Write-Log -Level "WARN" -Message "Netzwerkfehler bei DELETE $Endpoint. Neuer Versuch in $delay Sekunden: $($_.Exception.Message)"
            Start-Sleep -Seconds $delay
        }
        finally {
            if ($null -ne $response) {
                $response.Dispose()
            }

            $request.Dispose()
        }
    }

    throw "DELETE $Endpoint konnte nach $MaximumAttempts Versuchen nicht abgeschlossen werden."
}

function Invoke-GitHubDeleteBatch {
    param(
        [Parameter(Mandatory)]
        [object[]]$Rows,

        [Parameter(Mandatory)]
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [ValidateSet("WorkflowRun", "Cache", "Artifact")]
        [string]$ResourceType,

        [Parameter(Mandatory)]
        [System.Windows.Forms.DataGridView]$Grid
    )

    $parts = $RepositoryName.Split('/')
    if ($parts.Count -ne 2) {
        throw "Ungültiger Repository-Name: $RepositoryName"
    }

    $repositoryPath = [System.Uri]::EscapeDataString($parts[0]) + "/" + [System.Uri]::EscapeDataString($parts[1])

    $successfulRows = New-Object System.Collections.ArrayList
    $deleted = 0
    $failed = 0
    $position = 0
    $client = $null

    try {
        # Das Token und die HTTPS-Verbindung werden nur einmal aufgebaut.
        # Dadurch entfällt der Start eines neuen gh.exe-Prozesses pro Element.
        $client = New-GitHubApiClient

        foreach ($row in $Rows) {
            $position++

            switch ($ResourceType) {
                "WorkflowRun" {
                    $id = [string]$row.Tag.databaseId
                    $endpoint = "repos/$repositoryPath/actions/runs/$id"
                    $label = "Workflow-Run"
                }
                "Cache" {
                    $id = [string]$row.Tag.id
                    $endpoint = "repos/$repositoryPath/actions/caches/$id"
                    $label = "Cache"
                }
                "Artifact" {
                    $id = [string]$row.Tag.id
                    $endpoint = "repos/$repositoryPath/actions/artifacts/$id"
                    $label = "Artefakt"
                }
            }

            if ($position -eq 1 -or $position -eq $Rows.Count -or ($position % 5) -eq 0) {
                Set-Status "Lösche $label $position von $($Rows.Count) ..."
            }

            try {
                Invoke-GitHubDeleteRequest -Client $client -Endpoint $endpoint
                [void]$successfulRows.Add($row)
                $deleted++
            }
            catch {
                $message = $_.Exception.Message
                Write-Log -Level "ERROR" -Message "$label $id konnte nicht gelöscht werden: $message"
                $row.ErrorText = $message
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::MistyRose
                $failed++
            }

        }
    }
    finally {
        if ($null -ne $client) {
            $client.Dispose()
        }
    }

    foreach ($row in $successfulRows) {
        if ($null -ne $row.DataGridView -and $row.DataGridView -eq $Grid) {
            $Grid.Rows.Remove($row)
        }
    }

    return [pscustomobject]@{
        Deleted = $deleted
        Failed  = $failed
    }
}

function Format-ByteSize {
    param([long]$Bytes)

    if ($Bytes -ge 1TB) {
        return "{0:N2} TB" -f ($Bytes / 1TB)
    }

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }

    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }

    if ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }

    return "$Bytes B"
}

function Convert-ToLocalDateText {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    return ([datetime]$Value).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
}

function Set-Status {
    param([string]$Text)

    $statusLabel.Text = $Text
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-Error {
    param(
        [string]$Title,
        [object]$ErrorObject
    )

    $message = if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
        $ErrorObject.Exception.Message
    }
    elseif ($ErrorObject -is [System.Exception]) {
        $ErrorObject.Message
    }
    else {
        [string]$ErrorObject
    }

    [void][System.Windows.Forms.MessageBox]::Show(
        $form,
        $message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Confirm-Deletion {
    param(
        [string]$Title,
        [string]$Message,
        [string]$ExpectedText = "DELETE"
    )

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = $Title
    $dialog.StartPosition = "CenterParent"
    $dialog.ClientSize = New-Object System.Drawing.Size(620, 245)
    $dialog.MinimumSize = New-Object System.Drawing.Size(520, 245)
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(16)
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    [void]$layout.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))
    )
    [void]$layout.RowStyles.Add(
        (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))
    )
    [void]$layout.RowStyles.Add(
        (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34))
    )
    [void]$layout.RowStyles.Add(
        (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 48))
    )
    $dialog.Controls.Add($layout)

    $label = New-Object System.Windows.Forms.Label
    $label.Dock = "Fill"
    $label.AutoSize = $false
    $label.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $label.Text = "$Message`r`n`r`nGib zur Bestätigung exakt $ExpectedText ein:"
    $layout.Controls.Add($label, 0, 0)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Dock = "Fill"
    $textBox.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 4)
    $layout.Controls.Add($textBox, 0, 1)

    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.Dock = "Fill"
    $buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $buttonPanel.WrapContents = $false
    $buttonPanel.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $layout.Controls.Add($buttonPanel, 0, 2)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Abbrechen"
    $cancelButton.Size = New-Object System.Drawing.Size(110, 32)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $buttonPanel.Controls.Add($cancelButton)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "Endgültig löschen"
    $okButton.Size = New-Object System.Drawing.Size(130, 32)
    $okButton.Enabled = $false
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $buttonPanel.Controls.Add($okButton)

    $textBox.Add_TextChanged({
        $okButton.Enabled = ($textBox.Text -ceq $ExpectedText)
    })

    $dialog.AcceptButton = $okButton
    $dialog.CancelButton = $cancelButton
    $dialog.Add_Shown({ $textBox.Focus() })

    try {
        return ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK)
    }
    finally {
        $dialog.Dispose()
    }
}

function New-DataGrid {
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = "Fill"
    $grid.Margin = New-Object System.Windows.Forms.Padding(0)
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.AutoGenerateColumns = $false
    $grid.BackgroundColor = [System.Drawing.SystemColors]::Window
    $grid.BorderStyle = "Fixed3D"
    $grid.MultiSelect = $true
    $grid.ReadOnly = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = "FullRowSelect"
    $grid.AutoSizeRowsMode = "None"
    return $grid
}

function Add-GridCheckColumn {
    param([System.Windows.Forms.DataGridView]$Grid)

    $column = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $column.Name = "Marked"
    $column.HeaderText = "Löschen"
    $column.Width = 58
    $column.ReadOnly = $false
    [void]$Grid.Columns.Add($column)
}

function Add-GridTextColumn {
    param(
        [System.Windows.Forms.DataGridView]$Grid,
        [string]$Name,
        [string]$Header,
        [int]$Width,
        [System.Windows.Forms.DataGridViewAutoSizeColumnMode]$AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
    )

    $column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $column.Name = $Name
    $column.HeaderText = $Header
    $column.Width = $Width
    $column.ReadOnly = $true
    $column.AutoSizeMode = $AutoSizeMode
    [void]$Grid.Columns.Add($column)
}

function Get-MarkedRows {
    param([System.Windows.Forms.DataGridView]$Grid)

    return @(
        $Grid.Rows |
            Where-Object {
                -not $_.IsNewRow -and
                $null -ne $_.Tag -and
                [bool]$_.Cells["Marked"].Value
            }
    )
}

function Set-AllRowsMarked {
    param(
        [System.Windows.Forms.DataGridView]$Grid,
        [bool]$Value
    )

    foreach ($row in $Grid.Rows) {
        if (-not $row.IsNewRow -and $null -ne $row.Tag) {
            $row.Cells["Marked"].Value = $Value
        }
    }
}

function Get-SelectedRepositoryName {
    if ($null -eq $repositoryCombo.SelectedItem) {
        throw "Wähle zuerst ein Repository aus."
    }

    return [string]$repositoryCombo.SelectedItem
}

function Get-SelectedRepositoryObject {
    $repositoryName = Get-SelectedRepositoryName

    return @(
        $script:State.Repositories |
            Where-Object { [string]$_.nameWithOwner -eq $repositoryName }
    )[0]
}

function Update-RepositorySummary {
    try {
        $repository = Get-SelectedRepositoryObject

        $defaultBranch = if ($null -ne $repository.PSObject.Properties["defaultBranchRef"] -and
            $null -ne $repository.defaultBranchRef -and
            $null -ne $repository.defaultBranchRef.PSObject.Properties["name"]) {
            [string]$repository.defaultBranchRef.name
        }
        else {
            "–"
        }

        $visibility = if ($null -ne $repository.PSObject.Properties["visibility"]) {
            [string]$repository.visibility
        }
        else {
            "unbekannt"
        }

        $permission = if ($null -ne $repository.PSObject.Properties["viewerPermission"] -and
            -not [string]::IsNullOrWhiteSpace([string]$repository.viewerPermission)) {
            [string]$repository.viewerPermission
        }
        else {
            "unbekannt"
        }

        $diskUsage = if ($null -ne $repository.PSObject.Properties["diskUsage"] -and
            $null -ne $repository.diskUsage) {
            Format-ByteSize -Bytes ([long]$repository.diskUsage * 1KB)
        }
        else {
            "unbekannt"
        }

        $repositoryInfoLabel.Text = "$visibility · Berechtigung: $permission · Standardbranch: $defaultBranch · Git-Daten: $diskUsage"
    }
    catch {
        $repositoryInfoLabel.Text = "Kein Repository ausgewählt."
    }
}

function Clear-PreviewGrids {
    $runsGrid.Rows.Clear()
    $cachesGrid.Rows.Clear()
    $artifactsGrid.Rows.Clear()
    $runsSummaryLabel.Text = "Noch keine Vorschau geladen."
    $cachesSummaryLabel.Text = "Noch keine Vorschau geladen."
    $artifactsSummaryLabel.Text = "Noch keine Vorschau geladen."
}

function Test-GhAuthentication {
    try {
        if ([string]::IsNullOrWhiteSpace([string](Get-GhExecutable))) {
            return $false
        }

        [void](Invoke-Gh -Arguments @("auth", "status", "--hostname", "github.com") -AllowEmpty)
        return $true
    }
    catch {
        return $false
    }
}

function Install-GhCli {
    try {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($null -eq $winget) {
            throw "GitHub CLI fehlt und winget wurde ebenfalls nicht gefunden. Installiere GitHub CLI manuell und starte die Anwendung neu."
        }

        $answer = [System.Windows.Forms.MessageBox]::Show(
            $form,
            "GitHub CLI (gh) ist nicht installiert oder wurde nicht gefunden. Soll sie jetzt mit winget installiert werden?",
            "GitHub CLI installieren",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            return $false
        }

        Set-Status "Installiere GitHub CLI ..."
        $process = Start-Process `
            -FilePath ([string]$winget.Source) `
            -ArgumentList @(
                "install", "--id", "GitHub.cli", "--exact",
                "--accept-package-agreements", "--accept-source-agreements"
            ) `
            -WindowStyle Normal `
            -PassThru `
            -Wait

        if ($process.ExitCode -ne 0) {
            throw "winget wurde mit Exitcode $($process.ExitCode) beendet."
        }

        $script:State.GhExecutable = $null
        $resolved = Get-GhExecutable
        if ([string]::IsNullOrWhiteSpace([string]$resolved)) {
            throw "GitHub CLI wurde installiert, konnte im laufenden Prozess aber noch nicht gefunden werden. Starte die Anwendung einmal neu."
        }

        Update-AuthenticationState -Quiet | Out-Null
        return $true
    }
    catch {
        Show-Error -Title "GitHub CLI konnte nicht installiert werden" -ErrorObject $_
        Set-Status "GitHub CLI fehlt."
        return $false
    }
}

function Update-AuthenticationState {
    param([switch]$Quiet)

    $ghExecutable = Get-GhExecutable

    if ([string]::IsNullOrWhiteSpace([string]$ghExecutable)) {
        $script:State.Login = $null
        $authStatusLabel.Text = "GitHub CLI fehlt"
        $authStatusLabel.ForeColor = [System.Drawing.Color]::Firebrick
        $loginButton.Text = "GitHub CLI installieren"
        $loginButton.Enabled = $true
        $checkAuthButton.Enabled = $false
        $loadRepositoriesButton.Enabled = $true
        $authHintLabel.Text = "Beim Laden wird zuerst die Installation angeboten."

        if (-not $Quiet) {
            Show-Error `
                -Title "GitHub CLI fehlt" `
                -ErrorObject "Installiere GitHub CLI. Die Anwendung kann dafür winget verwenden."
        }

        return $false
    }

    $loginButton.Enabled = $true
    $checkAuthButton.Enabled = $true
    $loadRepositoriesButton.Enabled = $true

    try {
        [void](Invoke-Gh -Arguments @("auth", "status", "--hostname", "github.com") -AllowEmpty)
        $user = Invoke-GhJson -Arguments @("api", "user")
        $script:State.Login = [string]$user.login

        $authStatusLabel.Text = "Angemeldet als $($script:State.Login)"
        $authStatusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        $loginButton.Text = "Neu anmelden"
        $authHintLabel.Text = "Authentifizierung ist aktiv."

        if ([string]::IsNullOrWhiteSpace($ownerTextBox.Text)) {
            $ownerTextBox.Text = $script:State.Login
        }

        return $true
    }
    catch {
        $script:State.Login = $null
        $authStatusLabel.Text = "Nicht angemeldet"
        $authStatusLabel.ForeColor = [System.Drawing.Color]::Firebrick
        $loginButton.Text = "Bei GitHub anmelden"
        $authHintLabel.Text = "Beim Laden der Repositories startet automatisch die Browser-Anmeldung."

        if (-not $Quiet) {
            Show-Error `
                -Title "GitHub-Anmeldung fehlt oder ist ungültig" `
                -ErrorObject "Starte die Anmeldung über die Schaltfläche oder über 'Repositories laden'.`r`n`r`nTechnische Details:`r`n$($_.Exception.Message)"
        }

        return $false
    }
}

function Start-GhAuthentication {
    try {
        $ghExecutable = Get-GhExecutable
        if ([string]::IsNullOrWhiteSpace([string]$ghExecutable)) {
            if (-not (Install-GhCli)) {
                return
            }
            $ghExecutable = Get-GhExecutable
        }

        [void][System.Windows.Forms.MessageBox]::Show(
            $form,
            "Es öffnet sich jetzt ein sichtbares Konsolenfenster mit dem GitHub-Gerätecode. Danach öffnet GitHub die Browser-Anmeldung. Schließe das Konsolenfenster nicht, bevor die Anmeldung abgeschlossen ist.",
            "GitHub-Anmeldung",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )

        Set-Status "Warte auf die GitHub-Anmeldung ..."
        $form.UseWaitCursor = $true

        $helpText = Invoke-Gh -Arguments @("auth", "login", "--help") -AllowEmpty
        $clipboardArgument = if ($helpText -match "--clipboard") { " --clipboard" } else { "" }

        $tempCommand = Join-Path ([System.IO.Path]::GetTempPath()) ("github-cleanup-auth-{0}.cmd" -f [guid]::NewGuid().ToString("N"))
        $escapedGh = $ghExecutable.Replace('"', '""')
        $batch = @"
@echo off
title GitHub-Anmeldung - GitHub Manager $($script:AppVersion)
echo GitHub-Anmeldung wird gestartet...
echo.
"$escapedGh" auth login --hostname github.com --git-protocol https --web$clipboardArgument
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" (
  echo.
  echo Die Anmeldung ist fehlgeschlagen. Exitcode: %EXITCODE%
  pause
)
exit /b %EXITCODE%
"@
        Set-Content -LiteralPath $tempCommand -Value $batch -Encoding ASCII

        try {
            $process = Start-Process `
                -FilePath $env:ComSpec `
                -ArgumentList @("/d", "/c", "`"$tempCommand`"") `
                -WindowStyle Normal `
                -PassThru `
                -Wait
        }
        finally {
            Remove-Item -LiteralPath $tempCommand -Force -ErrorAction SilentlyContinue
        }

        if ($process.ExitCode -ne 0) {
            throw "Die GitHub-Anmeldung wurde mit Exitcode $($process.ExitCode) beendet."
        }

        if (-not (Update-AuthenticationState -Quiet)) {
            throw "Die Anmeldung wurde beendet, konnte danach aber nicht verifiziert werden."
        }

        $ownerTextBox.Text = $script:State.Login
        Set-Status "GitHub-Anmeldung erfolgreich. Lade Repositories ..."
        Load-Repositories
    }
    catch {
        Set-Status "GitHub-Anmeldung fehlgeschlagen."
        Show-Error -Title "GitHub-Anmeldung fehlgeschlagen" -ErrorObject $_
    }
    finally {
        $form.UseWaitCursor = $false
    }
}

function Load-Repositories {
    try {
        if (-not (Update-AuthenticationState -Quiet)) {
            # Der Benutzer muss nicht erst erraten, dass eine separate Anmeldung nötig ist.
            # Ein Klick auf "Repositories laden" startet den Browser-Flow direkt.
            Start-GhAuthentication
            return
        }

        Set-Status "Lade Repositories ..."
        $form.UseWaitCursor = $true

        $owner = $ownerTextBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($owner)) {
            $owner = $script:State.Login
            $ownerTextBox.Text = $owner
        }

        if ([string]::IsNullOrWhiteSpace($owner)) {
            throw "Gib einen GitHub-Benutzer oder eine Organisation an."
        }

        $arguments = @(
            "repo", "list", $owner,
            "--limit", "10000",
            "--json", "nameWithOwner,visibility,isPrivate,isArchived,isFork,diskUsage,pushedAt,viewerPermission,defaultBranchRef,deleteBranchOnMerge,url"
        )

        try {
            $allRepositories = @(Invoke-GhJson -Arguments $arguments)
        }
        catch {
            if ($_.Exception.Message -notmatch "(Unknown JSON field|unknown field|invalid value.*--json)") {
                throw
            }

            $compatibilityArguments = @(
                "repo", "list", $owner,
                "--limit", "10000",
                "--json", "nameWithOwner,visibility,isPrivate,isArchived,isFork,diskUsage,pushedAt,defaultBranchRef,url"
            )

            $allRepositories = @(Invoke-GhJson -Arguments $compatibilityArguments)
            Set-Status "Repositories im Kompatibilitätsmodus geladen."
        }

        # Nur echte Repository-Objekte übernehmen. Dadurch landen weder ein
        # versehentlich verschachteltes Array noch leere Einträge in der ComboBox.
        $rawRepositoryCount = $allRepositories.Count
        $allRepositories = @(
            $allRepositories |
                Where-Object {
                    $null -ne $_ -and
                    $null -ne $_.PSObject.Properties["nameWithOwner"] -and
                    -not [string]::IsNullOrWhiteSpace([string]$_.nameWithOwner)
                } |
                Sort-Object nameWithOwner -Unique
        )

        $loadedBeforeFilters = $allRepositories.Count
        Write-Log -Message ("Repository-Antwort: {0} Roheinträge, {1} gültige Repository-Objekte." -f $rawRepositoryCount, $loadedBeforeFilters)

        if ($loadedBeforeFilters -eq 0 -and $rawRepositoryCount -gt 0) {
            throw "GitHub lieferte Daten, aber keine gültigen Repository-Objekte. Öffne das Diagnoselog für die Details."
        }

        $repositories = @($allRepositories)

        switch ($forkModeComboBox.SelectedIndex) {
            0 {
                $repositories = @($repositories | Where-Object { -not [bool]$_.isFork })
            }
            2 {
                $repositories = @($repositories | Where-Object { [bool]$_.isFork })
            }
        }

        if (-not $includeArchivedCheckBox.Checked) {
            $repositories = @($repositories | Where-Object { -not [bool]$_.isArchived })
        }

        if ($onlyWritableCheckBox.Checked) {
            $permissionInformationAvailable = @(
                $repositories |
                    Where-Object { $null -ne $_.PSObject.Properties["viewerPermission"] }
            ).Count -gt 0

            if ($permissionInformationAvailable) {
                $repositories = @(
                    $repositories |
                        Where-Object {
                            $permission = [string]$_.viewerPermission
                            $repositoryOwner = ([string]$_.nameWithOwner -split "/", 2)[0]

                            ($permission -in @("WRITE", "MAINTAIN", "ADMIN")) -or
                            ($repositoryOwner -ieq $script:State.Login)
                        }
                )
            }
            elseif ($owner -ine $script:State.Login) {
                Set-Status "Berechtigungsfilter im Kompatibilitätsmodus nicht verfügbar."
            }
        }

        $repositories = @($repositories | Sort-Object nameWithOwner)
        $script:State.Repositories = $repositories
        Update-BulkRepositories

        $previousSelection = if ($null -ne $repositoryCombo.SelectedItem) {
            [string]$repositoryCombo.SelectedItem
        }
        else {
            ""
        }

        $repositoryCombo.BeginUpdate()
        try {
            $repositoryCombo.Items.Clear()
            foreach ($repository in $repositories) {
                [void]$repositoryCombo.Items.Add([string]$repository.nameWithOwner)
            }
        }
        finally {
            $repositoryCombo.EndUpdate()
        }

        if ($repositoryCombo.Items.Count -gt 0) {
            $previousIndex = $repositoryCombo.Items.IndexOf($previousSelection)
            $repositoryCombo.SelectedIndex = if ($previousIndex -ge 0) { $previousIndex } else { 0 }
            Set-Status "$($repositories.Count) von $loadedBeforeFilters Repositories geladen."
        }
        else {
            $repositoryInfoLabel.Text = "Kein Repository entspricht den aktuellen Filtern."
            Clear-PreviewGrids

            if ($loadedBeforeFilters -gt 0) {
                Set-Status "$loadedBeforeFilters Repositories gefunden, aber alle herausgefiltert."
                [void][System.Windows.Forms.MessageBox]::Show(
                    $form,
                    "$loadedBeforeFilters Repositories wurden gefunden, aber durch die aktuellen Filter ausgeblendet.`r`n`r`nDeaktiviere testweise 'Nur beschreibbare' oder ändere den Fork-Filter.",
                    "Keine Repositories nach Filterung",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            else {
                Set-Status "Für '$owner' wurden keine Repositories gefunden."
                [void][System.Windows.Forms.MessageBox]::Show(
                    $form,
                    "GitHub hat für '$owner' keine Repositories zurückgegeben. Prüfe die Schreibweise sowie den Zugriff auf private Organisations-Repositories.",
                    "Keine Repositories gefunden",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
        }
    }
    catch {
        Write-Log -Level "ERROR" -Message $_.Exception.Message
        Set-Status "Fehler beim Laden der Repositories."
        Show-Error -Title "Repositories konnten nicht geladen werden" -ErrorObject ("{0}`r`n`r`nDiagnoselog: {1}" -f $_.Exception.Message, $script:LogPath)
    }
    finally {
        $form.UseWaitCursor = $false
    }
}

function Get-SelectedConclusions {
    $selected = @()

    foreach ($item in $conclusionsCheckedList.CheckedItems) {
        $selected += [string]$item
    }

    return $selected
}

function Preview-WorkflowRuns {
    try {
        $repositoryName = Get-SelectedRepositoryName
        $selectedConclusions = @(Get-SelectedConclusions)

        if ($selectedConclusions.Count -eq 0) {
            throw "Wähle mindestens ein Ergebnis aus."
        }

        Set-Status "Lade abgeschlossene Workflow-Runs ..."
        $form.UseWaitCursor = $true
        $runsGrid.Rows.Clear()

        $arguments = @(
            "run", "list",
            "--repo", $repositoryName,
            "--limit", [string][int]$runsLimitNumeric.Value,
            "--status", "completed",
            "--json", "databaseId,createdAt,status,conclusion,workflowName,displayTitle,url,headBranch,event,number"
        )

        if ($includeDisabledRunsCheckBox.Checked) {
            $arguments += "--all"
        }

        $allRuns = @(Invoke-GhJson -Arguments $arguments)
        $allRuns = @($allRuns | Sort-Object { [datetime]$_.createdAt } -Descending)

        $protectedIds = New-Object "System.Collections.Generic.HashSet[string]"
        $keepNewest = [int]$keepRunsNumeric.Value

        if ($keepNewest -gt 0) {
            if ($keepPerWorkflowCheckBox.Checked) {
                $groups = @(
                    $allRuns |
                        Group-Object {
                            if ([string]::IsNullOrWhiteSpace([string]$_.workflowName)) {
                                "(ohne Workflowname)"
                            }
                            else {
                                [string]$_.workflowName
                            }
                        }
                )

                foreach ($group in $groups) {
                    foreach ($run in @($group.Group | Sort-Object { [datetime]$_.createdAt } -Descending | Select-Object -First $keepNewest)) {
                        [void]$protectedIds.Add([string]$run.databaseId)
                    }
                }
            }
            else {
                foreach ($run in @($allRuns | Select-Object -First $keepNewest)) {
                    [void]$protectedIds.Add([string]$run.databaseId)
                }
            }
        }

        $cutoff = (Get-Date).ToUniversalTime().AddDays(-[int]$minimumRunAgeNumeric.Value)

        $candidates = @(
            $allRuns |
                Where-Object {
                    -not $protectedIds.Contains([string]$_.databaseId) -and
                    ([datetime]$_.createdAt).ToUniversalTime() -le $cutoff -and
                    [string]$_.conclusion -in $selectedConclusions
                }
        )

        foreach ($run in $candidates) {
            $workflowName = if ([string]::IsNullOrWhiteSpace([string]$run.workflowName)) {
                "(ohne Workflowname)"
            }
            else {
                [string]$run.workflowName
            }

            $rowIndex = $runsGrid.Rows.Add(
                $true,
                (Convert-ToLocalDateText $run.createdAt),
                $workflowName,
                [string]$run.conclusion,
                [string]$run.event,
                [string]$run.headBranch,
                [string]$run.displayTitle,
                [string]$run.databaseId
            )

            $runsGrid.Rows[$rowIndex].Tag = $run
        }

        $scopeText = if ($keepPerWorkflowCheckBox.Checked) { "pro Workflow" } else { "global" }
        $runsSummaryLabel.Text = "Geladen: $($allRuns.Count) · Geschützt: $($protectedIds.Count) ($scopeText) · Löschkandidaten: $($candidates.Count)"
        Set-Status "Workflow-Vorschau geladen."
    }
    catch {
        Set-Status "Fehler bei der Workflow-Vorschau."
        Show-Error -Title "Workflow-Runs konnten nicht geladen werden" -ErrorObject $_
    }
    finally {
        $form.UseWaitCursor = $false
    }
}

function Delete-SelectedWorkflowRuns {
    try {
        $repositoryName = Get-SelectedRepositoryName
        Assert-BulkWriteAllowed -Repository $repositoryName
        $rows = @(Get-MarkedRows -Grid $runsGrid)

        if ($rows.Count -eq 0) {
            throw "Es sind keine Workflow-Runs markiert."
        }

        $confirmed = Confirm-Deletion `
            -Title "Workflow-Runs löschen" `
            -Message "$($rows.Count) Workflow-Runs aus $repositoryName werden unwiderruflich gelöscht. Zugehörige Logs und Artefakte werden ebenfalls entfernt."

        if (-not $confirmed) {
            return
        }

        $result = Invoke-GitHubDeleteBatch `
            -Rows $rows `
            -RepositoryName $repositoryName `
            -ResourceType "WorkflowRun" `
            -Grid $runsGrid

        $runsSummaryLabel.Text = "Gelöscht: $($result.Deleted) · Fehlgeschlagen: $($result.Failed) · Verbleibende Kandidaten: $($runsGrid.Rows.Count)"
        Set-Status "Workflow-Bereinigung abgeschlossen."

        if ($result.Failed -gt 0) {
            [void][System.Windows.Forms.MessageBox]::Show(
                $form,
                "$($result.Deleted) Runs wurden gelöscht, $($result.Failed) konnten nicht gelöscht werden. Details stehen an den betroffenen Tabellenzeilen.",
                "Bereinigung teilweise fehlgeschlagen",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    }
    catch {
        Set-Status "Workflow-Bereinigung fehlgeschlagen."
        Show-Error -Title "Workflow-Runs konnten nicht gelöscht werden" -ErrorObject $_
    }
}

function Preview-Caches {
    try {
        $repositoryName = Get-SelectedRepositoryName
        $repository = Get-SelectedRepositoryObject

        Set-Status "Lade Actions-Caches ..."
        $form.UseWaitCursor = $true
        $cachesGrid.Rows.Clear()

        $arguments = @(
            "cache", "list",
            "--repo", $repositoryName,
            "--limit", [string][int]$cacheLimitNumeric.Value,
            "--sort", "last_accessed_at",
            "--order", "asc",
            "--json", "id,key,createdAt,lastAccessedAt,ref,sizeInBytes,version"
        )

        $allCaches = @(Invoke-GhJson -Arguments $arguments)
        $cutoff = (Get-Date).ToUniversalTime().AddDays(-[int]$cacheAgeNumeric.Value)

        $defaultBranch = if ($null -ne $repository.defaultBranchRef) {
            [string]$repository.defaultBranchRef.name
        }
        else {
            ""
        }

        $defaultRef = if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
            ""
        }
        else {
            "refs/heads/$defaultBranch"
        }

        $candidates = @(
            $allCaches |
                Where-Object {
                    $isOld = ([datetime]$_.lastAccessedAt).ToUniversalTime() -le $cutoff
                    $isProtected = $protectDefaultBranchCacheCheckBox.Checked -and [string]$_.ref -eq $defaultRef
                    $isOld -and -not $isProtected
                }
        )

        $totalBytes = [long]0

        foreach ($cache in $candidates) {
            $size = [long]$cache.sizeInBytes
            $totalBytes += $size

            $rowIndex = $cachesGrid.Rows.Add(
                $true,
                (Convert-ToLocalDateText $cache.lastAccessedAt),
                (Convert-ToLocalDateText $cache.createdAt),
                (Format-ByteSize $size),
                [string]$cache.ref,
                [string]$cache.key,
                [string]$cache.id
            )

            $cachesGrid.Rows[$rowIndex].Tag = $cache
        }

        $protectedCount = $allCaches.Count - $candidates.Count
        $cachesSummaryLabel.Text = "Geladen: $($allCaches.Count) · Nicht markiert/geschützt: $protectedCount · Löschkandidaten: $($candidates.Count) · Größe: $(Format-ByteSize $totalBytes)"
        Set-Status "Cache-Vorschau geladen."
    }
    catch {
        Set-Status "Fehler bei der Cache-Vorschau."
        Show-Error -Title "Actions-Caches konnten nicht geladen werden" -ErrorObject $_
    }
    finally {
        $form.UseWaitCursor = $false
    }
}

function Delete-SelectedCaches {
    try {
        $repositoryName = Get-SelectedRepositoryName
        Assert-BulkWriteAllowed -Repository $repositoryName
        $rows = @(Get-MarkedRows -Grid $cachesGrid)

        if ($rows.Count -eq 0) {
            throw "Es sind keine Caches markiert."
        }

        $bytes = [long]0
        foreach ($row in $rows) {
            $bytes += [long]$row.Tag.sizeInBytes
        }

        $confirmed = Confirm-Deletion `
            -Title "Actions-Caches löschen" `
            -Message "$($rows.Count) Caches aus $repositoryName mit insgesamt $(Format-ByteSize $bytes) werden gelöscht. Fehlende Caches müssen bei späteren Builds neu erzeugt werden."

        if (-not $confirmed) {
            return
        }

        $result = Invoke-GitHubDeleteBatch `
            -Rows $rows `
            -RepositoryName $repositoryName `
            -ResourceType "Cache" `
            -Grid $cachesGrid

        $cachesSummaryLabel.Text = "Gelöscht: $($result.Deleted) · Fehlgeschlagen: $($result.Failed) · Verbleibende Kandidaten: $($cachesGrid.Rows.Count)"
        Set-Status "Cache-Bereinigung abgeschlossen."

        if ($result.Failed -gt 0) {
            [void][System.Windows.Forms.MessageBox]::Show(
                $form,
                "$($result.Deleted) Caches wurden gelöscht, $($result.Failed) konnten nicht gelöscht werden. Details stehen an den betroffenen Tabellenzeilen.",
                "Bereinigung teilweise fehlgeschlagen",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    }
    catch {
        Set-Status "Cache-Bereinigung fehlgeschlagen."
        Show-Error -Title "Actions-Caches konnten nicht gelöscht werden" -ErrorObject $_
    }
}

function Get-AllArtifacts {
    param([string]$RepositoryName)

    $pages = @(
        Invoke-GhApiJson `
            -Endpoint "repos/$RepositoryName/actions/artifacts?per_page=100" `
            -Paginate `
            -Slurp
    )

    $artifacts = @()

    foreach ($page in $pages) {
        if ($null -ne $page -and $null -ne $page.artifacts) {
            $artifacts += @($page.artifacts)
        }
    }

    return $artifacts
}

function Preview-Artifacts {
    try {
        $repositoryName = Get-SelectedRepositoryName

        Set-Status "Lade Workflow-Artefakte ..."
        $form.UseWaitCursor = $true
        $artifactsGrid.Rows.Clear()

        $allArtifacts = @(Get-AllArtifacts -RepositoryName $repositoryName)
        $allArtifacts = @($allArtifacts | Sort-Object { [datetime]$_.created_at } -Descending)

        $protectedIds = New-Object "System.Collections.Generic.HashSet[string]"
        $keepNewestPerName = [int]$keepArtifactsNumeric.Value

        if ($keepNewestPerName -gt 0) {
            foreach ($group in @($allArtifacts | Group-Object name)) {
                foreach ($artifact in @($group.Group | Sort-Object { [datetime]$_.created_at } -Descending | Select-Object -First $keepNewestPerName)) {
                    [void]$protectedIds.Add([string]$artifact.id)
                }
            }
        }

        $cutoff = (Get-Date).ToUniversalTime().AddDays(-[int]$artifactAgeNumeric.Value)

        $candidates = @(
            $allArtifacts |
                Where-Object {
                    $isOld = ([datetime]$_.created_at).ToUniversalTime() -le $cutoff
                    $isProtected = $protectedIds.Contains([string]$_.id)
                    $matchesExpiredFilter = -not $onlyExpiredArtifactsCheckBox.Checked -or [bool]$_.expired
                    $isOld -and -not $isProtected -and $matchesExpiredFilter
                }
        )

        $totalBytes = [long]0

        foreach ($artifact in $candidates) {
            $size = [long]$artifact.size_in_bytes
            $totalBytes += $size

            $runId = if ($null -ne $artifact.workflow_run) {
                [string]$artifact.workflow_run.id
            }
            else {
                ""
            }

            $rowIndex = $artifactsGrid.Rows.Add(
                $true,
                (Convert-ToLocalDateText $artifact.created_at),
                (Convert-ToLocalDateText $artifact.expires_at),
                [bool]$artifact.expired,
                (Format-ByteSize $size),
                [string]$artifact.name,
                $runId,
                [string]$artifact.id
            )

            $artifactsGrid.Rows[$rowIndex].Tag = $artifact
        }

        $artifactsSummaryLabel.Text = "Geladen: $($allArtifacts.Count) · Geschützt: $($protectedIds.Count) · Löschkandidaten: $($candidates.Count) · Größe: $(Format-ByteSize $totalBytes)"
        Set-Status "Artefakt-Vorschau geladen."
    }
    catch {
        Set-Status "Fehler bei der Artefakt-Vorschau."
        Show-Error -Title "Workflow-Artefakte konnten nicht geladen werden" -ErrorObject $_
    }
    finally {
        $form.UseWaitCursor = $false
    }
}

function Delete-SelectedArtifacts {
    try {
        $repositoryName = Get-SelectedRepositoryName
        Assert-BulkWriteAllowed -Repository $repositoryName
        $rows = @(Get-MarkedRows -Grid $artifactsGrid)

        if ($rows.Count -eq 0) {
            throw "Es sind keine Artefakte markiert."
        }

        $bytes = [long]0
        foreach ($row in $rows) {
            $bytes += [long]$row.Tag.size_in_bytes
        }

        $confirmed = Confirm-Deletion `
            -Title "Workflow-Artefakte löschen" `
            -Message "$($rows.Count) Artefakte aus $repositoryName mit insgesamt $(Format-ByteSize $bytes) werden gelöscht. Die zugehörigen Workflow-Runs und Logs bleiben erhalten."

        if (-not $confirmed) {
            return
        }

        $result = Invoke-GitHubDeleteBatch `
            -Rows $rows `
            -RepositoryName $repositoryName `
            -ResourceType "Artifact" `
            -Grid $artifactsGrid

        $artifactsSummaryLabel.Text = "Gelöscht: $($result.Deleted) · Fehlgeschlagen: $($result.Failed) · Verbleibende Kandidaten: $($artifactsGrid.Rows.Count)"
        Set-Status "Artefakt-Bereinigung abgeschlossen."

        if ($result.Failed -gt 0) {
            [void][System.Windows.Forms.MessageBox]::Show(
                $form,
                "$($result.Deleted) Artefakte wurden gelöscht, $($result.Failed) konnten nicht gelöscht werden. Details stehen an den betroffenen Tabellenzeilen.",
                "Bereinigung teilweise fehlgeschlagen",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    }
    catch {
        Set-Status "Artefakt-Bereinigung fehlgeschlagen."
        Show-Error -Title "Workflow-Artefakte konnten nicht gelöscht werden" -ErrorObject $_
    }
}

function Load-RepositorySettings {
    try {
        $repositoryName = Get-SelectedRepositoryName
        Set-Status "Lade Repository-Einstellungen ..."
        $form.UseWaitCursor = $true

        $repository = Invoke-GhJson -Arguments @(
            "repo", "view", $repositoryName,
            "--json", "nameWithOwner,diskUsage,defaultBranchRef,visibility,isPrivate,isArchived,isFork,viewerPermission,deleteBranchOnMerge,url"
        )

        $defaultBranch = if ($null -ne $repository.PSObject.Properties["defaultBranchRef"] -and
            $null -ne $repository.defaultBranchRef -and
            $null -ne $repository.defaultBranchRef.PSObject.Properties["name"]) {
            [string]$repository.defaultBranchRef.name
        }
        else {
            "–"
        }

        $repositoryNameValueLabel.Text = [string]$repository.nameWithOwner
        $defaultBranchValueLabel.Text = $defaultBranch
        $visibilityValueLabel.Text = [string]$repository.visibility
        $permissionValueLabel.Text = [string]$repository.viewerPermission
        $gitSizeValueLabel.Text = Format-ByteSize -Bytes ([long]$repository.diskUsage * 1KB)
        $autoDeleteBranchesCheckBox.Checked = [bool]$repository.deleteBranchOnMerge

        $isPublic = [string]$repository.visibility -eq "PUBLIC"
        $artifactRetentionNumeric.Maximum = if ($isPublic) { 90 } else { 400 }
        $cacheRetentionNumeric.Maximum = if ($isPublic) { 90 } else { 365 }

        try {
            $retention = Invoke-GhApiJson -Endpoint "repos/$repositoryName/actions/permissions/artifact-and-log-retention"
            $artifactRetentionNumeric.Value = [decimal][int]$retention.days
            $artifactRetentionNumeric.Enabled = $true
            $saveArtifactRetentionButton.Enabled = $true
            $artifactRetentionStatusLabel.Text = "Aktuell: $($retention.days) Tage"
        }
        catch {
            $artifactRetentionNumeric.Enabled = $false
            $saveArtifactRetentionButton.Enabled = $false
            $artifactRetentionStatusLabel.Text = "Nicht verfügbar: $($_.Exception.Message)"
        }

        try {
            $cacheRetention = Invoke-GhApiJson -Endpoint "repos/$repositoryName/actions/cache/retention-limit"
            $cacheRetentionNumeric.Value = [decimal][int]$cacheRetention.max_cache_retention_days
            $cacheRetentionNumeric.Enabled = $true
            $saveCacheRetentionButton.Enabled = $true
            $cacheRetentionStatusLabel.Text = "Aktuell: $($cacheRetention.max_cache_retention_days) Tage"
        }
        catch {
            $cacheRetentionNumeric.Enabled = $false
            $saveCacheRetentionButton.Enabled = $false
            $cacheRetentionStatusLabel.Text = "Nicht verfügbar oder Tarif/Berechtigung fehlt."
        }

        try {
            $cacheStorage = Invoke-GhApiJson -Endpoint "repos/$repositoryName/actions/cache/storage-limit"
            $cacheStorageNumeric.Value = [decimal][int]$cacheStorage.max_cache_size_gb
            $cacheStorageNumeric.Enabled = $true
            $saveCacheStorageButton.Enabled = $true
            $cacheStorageStatusLabel.Text = "Aktuell: $($cacheStorage.max_cache_size_gb) GB"
        }
        catch {
            $cacheStorageNumeric.Enabled = $false
            $saveCacheStorageButton.Enabled = $false
            $cacheStorageStatusLabel.Text = "Nicht verfügbar oder Tarif/Berechtigung fehlt."
        }

        Set-Status "Repository-Einstellungen geladen."
    }
    catch {
        Set-Status "Repository-Einstellungen konnten nicht geladen werden."
        Show-Error -Title "Repository-Einstellungen" -ErrorObject $_
    }
    finally {
        $form.UseWaitCursor = $false
    }
}

function Save-ArtifactRetention {
    try {
        $repositoryName = Get-SelectedRepositoryName
        $days = [int]$artifactRetentionNumeric.Value

        Invoke-GhApiNoContent `
            -Endpoint "repos/$repositoryName/actions/permissions/artifact-and-log-retention" `
            -Method PUT `
            -Fields @("days=$days")

        $artifactRetentionStatusLabel.Text = "Aktuell: $days Tage"
        Set-Status "Artefakt- und Log-Aufbewahrung gespeichert."
    }
    catch {
        Show-Error -Title "Aufbewahrung konnte nicht gespeichert werden" -ErrorObject $_
    }
}

function Save-CacheRetention {
    try {
        $repositoryName = Get-SelectedRepositoryName
        $days = [int]$cacheRetentionNumeric.Value

        Invoke-GhApiNoContent `
            -Endpoint "repos/$repositoryName/actions/cache/retention-limit" `
            -Method PUT `
            -Fields @("max_cache_retention_days=$days")

        $cacheRetentionStatusLabel.Text = "Aktuell: $days Tage"
        Set-Status "Cache-Aufbewahrung gespeichert."
    }
    catch {
        Show-Error -Title "Cache-Aufbewahrung konnte nicht gespeichert werden" -ErrorObject $_
    }
}

function Save-CacheStorage {
    try {
        $repositoryName = Get-SelectedRepositoryName
        $gigabytes = [int]$cacheStorageNumeric.Value

        Invoke-GhApiNoContent `
            -Endpoint "repos/$repositoryName/actions/cache/storage-limit" `
            -Method PUT `
            -Fields @("max_cache_size_gb=$gigabytes")

        $cacheStorageStatusLabel.Text = "Aktuell: $gigabytes GB"
        Set-Status "Cache-Speicherlimit gespeichert."
    }
    catch {
        Show-Error -Title "Cache-Speicherlimit konnte nicht gespeichert werden" -ErrorObject $_
    }
}

function Save-AutoDeleteBranches {
    try {
        $repositoryName = Get-SelectedRepositoryName
        Set-Status "Speichere Branch-Einstellung ..."

        if ($autoDeleteBranchesCheckBox.Checked) {
            [void](Invoke-Gh -Arguments @("repo", "edit", $repositoryName, "--delete-branch-on-merge") -AllowEmpty)
        }
        else {
            [void](Invoke-Gh -Arguments @("repo", "edit", $repositoryName, "--delete-branch-on-merge=false") -AllowEmpty)
        }

        Set-Status "Branch-Einstellung gespeichert."
    }
    catch {
        Show-Error -Title "Branch-Einstellung konnte nicht gespeichert werden" -ErrorObject $_
    }
}

function Open-SelectedRepository {
    try {
        $repository = Get-SelectedRepositoryObject
        Start-Process ([string]$repository.url)
    }
    catch {
        Show-Error -Title "Repository konnte nicht geöffnet werden" -ErrorObject $_
    }
}

function Initialize-Application {
    Write-Log -Message "Anwendung $($script:AppVersion) gestartet."
    Initialize-TemplateSystem
    Set-Status "Prüfe GitHub CLI und Anmeldung ..."

    if (Update-AuthenticationState -Quiet) {
        $ownerTextBox.Text = $script:State.Login
        $newRepoOwnerTextBox.Text = $script:State.Login
        Load-Repositories
    }
    else {
        Set-Status "Nicht angemeldet. 'Repositories laden' startet die Anmeldung automatisch."
    }
}

# Hauptfenster
$form = New-Object System.Windows.Forms.Form
$form.Text = "GitHub Manager $script:AppVersion"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1280, 850)
$form.MinimumSize = New-Object System.Drawing.Size(820, 620)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized

$mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
$mainLayout.Dock = "Fill"
$mainLayout.ColumnCount = 1
$mainLayout.RowCount = 3
[void]$mainLayout.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$mainLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 132))
)
[void]$mainLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$mainLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))
)
$form.Controls.Add($mainLayout)

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = "Fill"
$topPanel.Padding = New-Object System.Windows.Forms.Padding(8)
$topPanel.AutoSize = $false
$topPanel.AutoScroll = $true
$mainLayout.Controls.Add($topPanel, 0, 0)

$topLayout = New-Object System.Windows.Forms.TableLayoutPanel
$topLayout.Dock = "Top"
$topLayout.AutoSize = $true
$topLayout.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$topLayout.ColumnCount = 1
$topLayout.RowCount = 3
[void]$topLayout.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$topLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))
)
[void]$topLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))
)
[void]$topLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))
)
$topPanel.Controls.Add($topLayout)

$authRow = New-Object System.Windows.Forms.FlowLayoutPanel
$authRow.Dock = "Top"
$authRow.AutoSize = $true
$authRow.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$authRow.WrapContents = $true
$authRow.AutoScroll = $false
$authRow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$topLayout.Controls.Add($authRow, 0, 0)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = "GitHub Manager $script:AppVersion"
$versionLabel.AutoSize = $true
$versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$versionLabel.Margin = New-Object System.Windows.Forms.Padding(3, 9, 14, 0)
$authRow.Controls.Add($versionLabel)

$authCaptionLabel = New-Object System.Windows.Forms.Label
$authCaptionLabel.Text = "GitHub:"
$authCaptionLabel.AutoSize = $true
$authCaptionLabel.Margin = New-Object System.Windows.Forms.Padding(3, 9, 4, 0)
$authRow.Controls.Add($authCaptionLabel)

$authStatusLabel = New-Object System.Windows.Forms.Label
$authStatusLabel.Text = "Wird geprüft ..."
$authStatusLabel.Size = New-Object System.Drawing.Size(200, 24)
$authStatusLabel.Margin = New-Object System.Windows.Forms.Padding(0, 7, 8, 0)
$authRow.Controls.Add($authStatusLabel)

$loginButton = New-Object System.Windows.Forms.Button
$loginButton.Text = "Bei GitHub anmelden"
$loginButton.Size = New-Object System.Drawing.Size(145, 30)
$loginButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 0)
$authRow.Controls.Add($loginButton)

$checkAuthButton = New-Object System.Windows.Forms.Button
$checkAuthButton.Text = "Anmeldung prüfen"
$checkAuthButton.Size = New-Object System.Drawing.Size(130, 30)
$checkAuthButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 0)
$authRow.Controls.Add($checkAuthButton)

$openLogButton = New-Object System.Windows.Forms.Button
$openLogButton.Text = "Diagnoselog"
$openLogButton.Size = New-Object System.Drawing.Size(105, 30)
$openLogButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 0)
$authRow.Controls.Add($openLogButton)

$authHintLabel = New-Object System.Windows.Forms.Label
$authHintLabel.Text = "Die Zugangsdaten werden von GitHub CLI im Windows-Anmeldeinformationsspeicher verwaltet."
$authHintLabel.AutoSize = $true
$authHintLabel.AutoEllipsis = $true
$authHintLabel.Margin = New-Object System.Windows.Forms.Padding(4, 9, 0, 0)
$authRow.Controls.Add($authHintLabel)

$filterRow = New-Object System.Windows.Forms.FlowLayoutPanel
$filterRow.Dock = "Top"
$filterRow.AutoSize = $true
$filterRow.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$filterRow.WrapContents = $true
$filterRow.AutoScroll = $false
$filterRow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$topLayout.Controls.Add($filterRow, 0, 1)

$ownerLabel = New-Object System.Windows.Forms.Label
$ownerLabel.Text = "Benutzer / Organisation:"
$ownerLabel.AutoSize = $true
$ownerLabel.Margin = New-Object System.Windows.Forms.Padding(3, 10, 6, 0)
$filterRow.Controls.Add($ownerLabel)

$ownerTextBox = New-Object System.Windows.Forms.TextBox
$ownerTextBox.Size = New-Object System.Drawing.Size(190, 25)
$ownerTextBox.Margin = New-Object System.Windows.Forms.Padding(0, 6, 12, 0)
$filterRow.Controls.Add($ownerTextBox)

$forkModeLabel = New-Object System.Windows.Forms.Label
$forkModeLabel.Text = "Forks:"
$forkModeLabel.AutoSize = $true
$forkModeLabel.Margin = New-Object System.Windows.Forms.Padding(0, 10, 6, 0)
$filterRow.Controls.Add($forkModeLabel)

$forkModeComboBox = New-Object System.Windows.Forms.ComboBox
$forkModeComboBox.DropDownStyle = "DropDownList"
$forkModeComboBox.Size = New-Object System.Drawing.Size(225, 25)
$forkModeComboBox.Margin = New-Object System.Windows.Forms.Padding(0, 6, 12, 0)
[void]$forkModeComboBox.Items.Add("Nur eigenständige Repositories")
[void]$forkModeComboBox.Items.Add("Alle einschließlich Forks")
[void]$forkModeComboBox.Items.Add("Nur Forks")
$forkModeComboBox.SelectedIndex = 0
$filterRow.Controls.Add($forkModeComboBox)

$includeArchivedCheckBox = New-Object System.Windows.Forms.CheckBox
$includeArchivedCheckBox.Text = "Archivierte einbeziehen"
$includeArchivedCheckBox.AutoSize = $true
$includeArchivedCheckBox.Margin = New-Object System.Windows.Forms.Padding(0, 9, 12, 0)
$filterRow.Controls.Add($includeArchivedCheckBox)

$onlyWritableCheckBox = New-Object System.Windows.Forms.CheckBox
$onlyWritableCheckBox.Text = "Nur beschreibbare"
$onlyWritableCheckBox.AutoSize = $true
$onlyWritableCheckBox.Checked = $true
$onlyWritableCheckBox.Margin = New-Object System.Windows.Forms.Padding(0, 9, 12, 0)
$filterRow.Controls.Add($onlyWritableCheckBox)

$loadRepositoriesButton = New-Object System.Windows.Forms.Button
$loadRepositoriesButton.Text = "Repositories laden"
$loadRepositoriesButton.Size = New-Object System.Drawing.Size(145, 30)
$loadRepositoriesButton.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
$filterRow.Controls.Add($loadRepositoriesButton)

$repositoryRow = New-Object System.Windows.Forms.FlowLayoutPanel
$repositoryRow.Dock = "Top"
$repositoryRow.AutoSize = $true
$repositoryRow.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$repositoryRow.WrapContents = $true
$repositoryRow.AutoScroll = $false
$repositoryRow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$topLayout.Controls.Add($repositoryRow, 0, 2)

$repositoryLabel = New-Object System.Windows.Forms.Label
$repositoryLabel.Text = "Repository:"
$repositoryLabel.AutoSize = $true
$repositoryLabel.Margin = New-Object System.Windows.Forms.Padding(3, 10, 6, 0)
$repositoryRow.Controls.Add($repositoryLabel)

$repositoryCombo = New-Object System.Windows.Forms.ComboBox
$repositoryCombo.Size = New-Object System.Drawing.Size(390, 25)
$repositoryCombo.DropDownStyle = "DropDownList"
$repositoryCombo.Margin = New-Object System.Windows.Forms.Padding(0, 6, 10, 0)
$repositoryRow.Controls.Add($repositoryCombo)

$openRepositoryButton = New-Object System.Windows.Forms.Button
$openRepositoryButton.Text = "Im Browser öffnen"
$openRepositoryButton.Size = New-Object System.Drawing.Size(125, 30)
$openRepositoryButton.Margin = New-Object System.Windows.Forms.Padding(0, 4, 12, 0)
$repositoryRow.Controls.Add($openRepositoryButton)

$repositoryInfoLabel = New-Object System.Windows.Forms.Label
$repositoryInfoLabel.Text = "Kein Repository ausgewählt."
$repositoryInfoLabel.AutoSize = $true
$repositoryInfoLabel.Margin = New-Object System.Windows.Forms.Padding(0, 9, 0, 0)
$repositoryRow.Controls.Add($repositoryInfoLabel)

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = "Fill"
$mainLayout.Controls.Add($tabControl, 0, 1)

# Repositoryuebergreifende, asynchrone Bereinigung.
Initialize-BulkCleanupTab -Tabs $tabControl

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.Dock = "Fill"
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Bereit – GitHub Manager $script:AppVersion"
$statusLabel.Spring = $true
$statusLabel.TextAlign = "MiddleLeft"
[void]$statusStrip.Items.Add($statusLabel)
$mainLayout.Controls.Add($statusStrip, 0, 2)

# Tab: Workflow-Runs
$runsTab = New-Object System.Windows.Forms.TabPage
$runsTab.Text = "Workflow-Runs"
$tabControl.TabPages.Add($runsTab)

$runsLayout = New-Object System.Windows.Forms.TableLayoutPanel
$runsLayout.Dock = "Fill"
$runsLayout.Margin = New-Object System.Windows.Forms.Padding(0)
$runsLayout.Padding = New-Object System.Windows.Forms.Padding(0)
$runsLayout.ColumnCount = 1
$runsLayout.RowCount = 3
[void]$runsLayout.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$runsLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))
)
[void]$runsLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$runsLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52))
)
$runsTab.Controls.Add($runsLayout)

$runsTopPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$runsTopPanel.Dock = "Fill"
$runsTopPanel.AutoSize = $true
$runsTopPanel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$runsTopPanel.Padding = New-Object System.Windows.Forms.Padding(8)
$runsTopPanel.WrapContents = $true
$runsTopPanel.AutoScroll = $false
$runsLayout.Controls.Add($runsTopPanel, 0, 0)

$runsProtectionGroup = New-Object System.Windows.Forms.GroupBox
$runsProtectionGroup.Text = "Schutzregeln"
$runsProtectionGroup.Size = New-Object System.Drawing.Size(355, 100)
$runsTopPanel.Controls.Add($runsProtectionGroup)

$keepRunsLabel = New-Object System.Windows.Forms.Label
$keepRunsLabel.Text = "Neueste behalten:"
$keepRunsLabel.Location = New-Object System.Drawing.Point(12, 26)
$keepRunsLabel.AutoSize = $true
$runsProtectionGroup.Controls.Add($keepRunsLabel)

$keepRunsNumeric = New-Object System.Windows.Forms.NumericUpDown
$keepRunsNumeric.Location = New-Object System.Drawing.Point(130, 22)
$keepRunsNumeric.Size = New-Object System.Drawing.Size(70, 25)
$keepRunsNumeric.Minimum = 0
$keepRunsNumeric.Maximum = 1000
$keepRunsNumeric.Value = 10
$runsProtectionGroup.Controls.Add($keepRunsNumeric)

$keepPerWorkflowCheckBox = New-Object System.Windows.Forms.CheckBox
$keepPerWorkflowCheckBox.Text = "pro Workflow"
$keepPerWorkflowCheckBox.Location = New-Object System.Drawing.Point(215, 24)
$keepPerWorkflowCheckBox.AutoSize = $true
$keepPerWorkflowCheckBox.Checked = $true
$runsProtectionGroup.Controls.Add($keepPerWorkflowCheckBox)

$minimumRunAgeLabel = New-Object System.Windows.Forms.Label
$minimumRunAgeLabel.Text = "Mindestalter in Tagen:"
$minimumRunAgeLabel.Location = New-Object System.Drawing.Point(12, 63)
$minimumRunAgeLabel.AutoSize = $true
$runsProtectionGroup.Controls.Add($minimumRunAgeLabel)

$minimumRunAgeNumeric = New-Object System.Windows.Forms.NumericUpDown
$minimumRunAgeNumeric.Location = New-Object System.Drawing.Point(150, 59)
$minimumRunAgeNumeric.Size = New-Object System.Drawing.Size(70, 25)
$minimumRunAgeNumeric.Minimum = 0
$minimumRunAgeNumeric.Maximum = 3650
$minimumRunAgeNumeric.Value = 14
$runsProtectionGroup.Controls.Add($minimumRunAgeNumeric)

$runsFetchGroup = New-Object System.Windows.Forms.GroupBox
$runsFetchGroup.Text = "Abruf"
$runsFetchGroup.Size = New-Object System.Drawing.Size(220, 100)
$runsTopPanel.Controls.Add($runsFetchGroup)

$runsLimitLabel = New-Object System.Windows.Forms.Label
$runsLimitLabel.Text = "Maximale Runs:"
$runsLimitLabel.Location = New-Object System.Drawing.Point(12, 27)
$runsLimitLabel.AutoSize = $true
$runsFetchGroup.Controls.Add($runsLimitLabel)

$runsLimitNumeric = New-Object System.Windows.Forms.NumericUpDown
$runsLimitNumeric.Location = New-Object System.Drawing.Point(118, 23)
$runsLimitNumeric.Size = New-Object System.Drawing.Size(85, 25)
$runsLimitNumeric.Minimum = 20
$runsLimitNumeric.Maximum = 10000
$runsLimitNumeric.Value = 1000
$runsFetchGroup.Controls.Add($runsLimitNumeric)

$includeDisabledRunsCheckBox = New-Object System.Windows.Forms.CheckBox
$includeDisabledRunsCheckBox.Text = "Deaktivierte Workflows einbeziehen"
$includeDisabledRunsCheckBox.Location = New-Object System.Drawing.Point(12, 62)
$includeDisabledRunsCheckBox.AutoSize = $true
$includeDisabledRunsCheckBox.Checked = $true
$runsFetchGroup.Controls.Add($includeDisabledRunsCheckBox)

$conclusionsGroup = New-Object System.Windows.Forms.GroupBox
$conclusionsGroup.Text = "Ergebnisse, die gelöscht werden dürfen"
$conclusionsGroup.Size = New-Object System.Drawing.Size(430, 100)
$runsTopPanel.Controls.Add($conclusionsGroup)

$conclusionsCheckedList = New-Object System.Windows.Forms.CheckedListBox
$conclusionsCheckedList.Location = New-Object System.Drawing.Point(10, 20)
$conclusionsCheckedList.Size = New-Object System.Drawing.Size(410, 68)
$conclusionsCheckedList.CheckOnClick = $true
$conclusionsCheckedList.MultiColumn = $true
$conclusionsCheckedList.ColumnWidth = 130
$conclusionsCheckedList.BorderStyle = "None"
$conclusions = @("success", "failure", "cancelled", "timed_out", "skipped", "neutral", "stale", "action_required", "startup_failure")
foreach ($conclusion in $conclusions) {
    [void]$conclusionsCheckedList.Items.Add($conclusion, $true)
}
$conclusionsGroup.Controls.Add($conclusionsCheckedList)

$previewRunsButton = New-Object System.Windows.Forms.Button
$previewRunsButton.Text = "Vorschau laden"
$previewRunsButton.Size = New-Object System.Drawing.Size(140, 42)
$previewRunsButton.Margin = New-Object System.Windows.Forms.Padding(10, 30, 0, 0)
$runsTopPanel.Controls.Add($previewRunsButton)

$runsBottomPanel = New-Object System.Windows.Forms.TableLayoutPanel
$runsBottomPanel.Dock = "Fill"
$runsBottomPanel.ColumnCount = 2
$runsBottomPanel.RowCount = 1
[void]$runsBottomPanel.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$runsBottomPanel.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 350))
)
$runsLayout.Controls.Add($runsBottomPanel, 0, 2)

$runsSummaryLabel = New-Object System.Windows.Forms.Label
$runsSummaryLabel.Text = "Noch keine Vorschau geladen."
$runsSummaryLabel.Dock = "Fill"
$runsSummaryLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$runsSummaryLabel.Padding = New-Object System.Windows.Forms.Padding(10, 0, 4, 0)
$runsSummaryLabel.AutoEllipsis = $true
$runsBottomPanel.Controls.Add($runsSummaryLabel, 0, 0)

$runsActionsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$runsActionsPanel.Dock = "Fill"
$runsActionsPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$runsActionsPanel.WrapContents = $false
$runsActionsPanel.Padding = New-Object System.Windows.Forms.Padding(4, 8, 0, 0)
$runsBottomPanel.Controls.Add($runsActionsPanel, 1, 0)

$selectAllRunsButton = New-Object System.Windows.Forms.Button
$selectAllRunsButton.Text = "Alle markieren"
$selectAllRunsButton.Size = New-Object System.Drawing.Size(105, 32)
$runsActionsPanel.Controls.Add($selectAllRunsButton)

$selectNoRunsButton = New-Object System.Windows.Forms.Button
$selectNoRunsButton.Text = "Keine"
$selectNoRunsButton.Size = New-Object System.Drawing.Size(75, 32)
$runsActionsPanel.Controls.Add($selectNoRunsButton)

$deleteRunsButton = New-Object System.Windows.Forms.Button
$deleteRunsButton.Text = "Markierte löschen"
$deleteRunsButton.Size = New-Object System.Drawing.Size(145, 32)
$runsActionsPanel.Controls.Add($deleteRunsButton)

$runsGrid = New-DataGrid
Add-GridCheckColumn -Grid $runsGrid
Add-GridTextColumn -Grid $runsGrid -Name "Created" -Header "Datum" -Width 140
Add-GridTextColumn -Grid $runsGrid -Name "Workflow" -Header "Workflow" -Width 190
Add-GridTextColumn -Grid $runsGrid -Name "Conclusion" -Header "Ergebnis" -Width 90
Add-GridTextColumn -Grid $runsGrid -Name "Event" -Header "Event" -Width 90
Add-GridTextColumn -Grid $runsGrid -Name "Branch" -Header "Branch" -Width 150
Add-GridTextColumn -Grid $runsGrid -Name "Title" -Header "Titel" -Width 300 -AutoSizeMode Fill
Add-GridTextColumn -Grid $runsGrid -Name "Id" -Header "Run-ID" -Width 100
$runsLayout.Controls.Add($runsGrid, 0, 1)

# Tab: Caches
$cachesTab = New-Object System.Windows.Forms.TabPage
$cachesTab.Text = "Actions-Caches"
$tabControl.TabPages.Add($cachesTab)

$cachesLayout = New-Object System.Windows.Forms.TableLayoutPanel
$cachesLayout.Dock = "Fill"
$cachesLayout.Margin = New-Object System.Windows.Forms.Padding(0)
$cachesLayout.Padding = New-Object System.Windows.Forms.Padding(0)
$cachesLayout.ColumnCount = 1
$cachesLayout.RowCount = 3
[void]$cachesLayout.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$cachesLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))
)
[void]$cachesLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$cachesLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52))
)
$cachesTab.Controls.Add($cachesLayout)

$cachesTopPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$cachesTopPanel.Dock = "Fill"
$cachesTopPanel.AutoSize = $true
$cachesTopPanel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$cachesTopPanel.Padding = New-Object System.Windows.Forms.Padding(8)
$cachesTopPanel.WrapContents = $true
$cachesTopPanel.AutoScroll = $false
$cachesLayout.Controls.Add($cachesTopPanel, 0, 0)

$cacheFilterGroup = New-Object System.Windows.Forms.GroupBox
$cacheFilterGroup.Text = "Filter"
$cacheFilterGroup.Size = New-Object System.Drawing.Size(420, 70)
$cachesTopPanel.Controls.Add($cacheFilterGroup)

$cacheAgeLabel = New-Object System.Windows.Forms.Label
$cacheAgeLabel.Text = "Seit mindestens Tagen nicht verwendet:"
$cacheAgeLabel.Location = New-Object System.Drawing.Point(12, 29)
$cacheAgeLabel.AutoSize = $true
$cacheFilterGroup.Controls.Add($cacheAgeLabel)

$cacheAgeNumeric = New-Object System.Windows.Forms.NumericUpDown
$cacheAgeNumeric.Location = New-Object System.Drawing.Point(245, 25)
$cacheAgeNumeric.Size = New-Object System.Drawing.Size(65, 25)
$cacheAgeNumeric.Minimum = 0
$cacheAgeNumeric.Maximum = 3650
$cacheAgeNumeric.Value = 14
$cacheFilterGroup.Controls.Add($cacheAgeNumeric)

$protectDefaultBranchCacheCheckBox = New-Object System.Windows.Forms.CheckBox
$protectDefaultBranchCacheCheckBox.Text = "Standardbranch schützen"
$protectDefaultBranchCacheCheckBox.Location = New-Object System.Drawing.Point(320, 28)
$protectDefaultBranchCacheCheckBox.AutoSize = $true
$protectDefaultBranchCacheCheckBox.Checked = $true
$cacheFilterGroup.Controls.Add($protectDefaultBranchCacheCheckBox)

$cacheFetchGroup = New-Object System.Windows.Forms.GroupBox
$cacheFetchGroup.Text = "Abruf"
$cacheFetchGroup.Size = New-Object System.Drawing.Size(205, 70)
$cachesTopPanel.Controls.Add($cacheFetchGroup)

$cacheLimitLabel = New-Object System.Windows.Forms.Label
$cacheLimitLabel.Text = "Maximale Caches:"
$cacheLimitLabel.Location = New-Object System.Drawing.Point(12, 29)
$cacheLimitLabel.AutoSize = $true
$cacheFetchGroup.Controls.Add($cacheLimitLabel)

$cacheLimitNumeric = New-Object System.Windows.Forms.NumericUpDown
$cacheLimitNumeric.Location = New-Object System.Drawing.Point(122, 25)
$cacheLimitNumeric.Size = New-Object System.Drawing.Size(70, 25)
$cacheLimitNumeric.Minimum = 30
$cacheLimitNumeric.Maximum = 10000
$cacheLimitNumeric.Value = 1000
$cacheFetchGroup.Controls.Add($cacheLimitNumeric)

$previewCachesButton = New-Object System.Windows.Forms.Button
$previewCachesButton.Text = "Vorschau laden"
$previewCachesButton.Size = New-Object System.Drawing.Size(140, 38)
$previewCachesButton.Margin = New-Object System.Windows.Forms.Padding(10, 20, 0, 0)
$cachesTopPanel.Controls.Add($previewCachesButton)

$cachesBottomPanel = New-Object System.Windows.Forms.TableLayoutPanel
$cachesBottomPanel.Dock = "Fill"
$cachesBottomPanel.ColumnCount = 2
$cachesBottomPanel.RowCount = 1
[void]$cachesBottomPanel.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$cachesBottomPanel.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 350))
)
$cachesLayout.Controls.Add($cachesBottomPanel, 0, 2)

$cachesSummaryLabel = New-Object System.Windows.Forms.Label
$cachesSummaryLabel.Text = "Noch keine Vorschau geladen."
$cachesSummaryLabel.Dock = "Fill"
$cachesSummaryLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$cachesSummaryLabel.Padding = New-Object System.Windows.Forms.Padding(10, 0, 4, 0)
$cachesSummaryLabel.AutoEllipsis = $true
$cachesBottomPanel.Controls.Add($cachesSummaryLabel, 0, 0)

$cachesActionsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$cachesActionsPanel.Dock = "Fill"
$cachesActionsPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$cachesActionsPanel.WrapContents = $false
$cachesActionsPanel.Padding = New-Object System.Windows.Forms.Padding(4, 8, 0, 0)
$cachesBottomPanel.Controls.Add($cachesActionsPanel, 1, 0)

$selectAllCachesButton = New-Object System.Windows.Forms.Button
$selectAllCachesButton.Text = "Alle markieren"
$selectAllCachesButton.Size = New-Object System.Drawing.Size(105, 32)
$cachesActionsPanel.Controls.Add($selectAllCachesButton)

$selectNoCachesButton = New-Object System.Windows.Forms.Button
$selectNoCachesButton.Text = "Keine"
$selectNoCachesButton.Size = New-Object System.Drawing.Size(75, 32)
$cachesActionsPanel.Controls.Add($selectNoCachesButton)

$deleteCachesButton = New-Object System.Windows.Forms.Button
$deleteCachesButton.Text = "Markierte löschen"
$deleteCachesButton.Size = New-Object System.Drawing.Size(145, 32)
$cachesActionsPanel.Controls.Add($deleteCachesButton)

$cachesGrid = New-DataGrid
Add-GridCheckColumn -Grid $cachesGrid
Add-GridTextColumn -Grid $cachesGrid -Name "LastAccessed" -Header "Zuletzt verwendet" -Width 145
Add-GridTextColumn -Grid $cachesGrid -Name "Created" -Header "Erstellt" -Width 145
Add-GridTextColumn -Grid $cachesGrid -Name "Size" -Header "Größe" -Width 90
Add-GridTextColumn -Grid $cachesGrid -Name "Ref" -Header "Ref" -Width 240
Add-GridTextColumn -Grid $cachesGrid -Name "Key" -Header "Cache-Key" -Width 400 -AutoSizeMode Fill
Add-GridTextColumn -Grid $cachesGrid -Name "Id" -Header "Cache-ID" -Width 100
$cachesLayout.Controls.Add($cachesGrid, 0, 1)

# Tab: Artefakte
$artifactsTab = New-Object System.Windows.Forms.TabPage
$artifactsTab.Text = "Workflow-Artefakte"
$tabControl.TabPages.Add($artifactsTab)

$artifactsLayout = New-Object System.Windows.Forms.TableLayoutPanel
$artifactsLayout.Dock = "Fill"
$artifactsLayout.Margin = New-Object System.Windows.Forms.Padding(0)
$artifactsLayout.Padding = New-Object System.Windows.Forms.Padding(0)
$artifactsLayout.ColumnCount = 1
$artifactsLayout.RowCount = 3
[void]$artifactsLayout.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$artifactsLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))
)
[void]$artifactsLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$artifactsLayout.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52))
)
$artifactsTab.Controls.Add($artifactsLayout)

$artifactsTopPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$artifactsTopPanel.Dock = "Fill"
$artifactsTopPanel.AutoSize = $true
$artifactsTopPanel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$artifactsTopPanel.Padding = New-Object System.Windows.Forms.Padding(8)
$artifactsTopPanel.WrapContents = $true
$artifactsTopPanel.AutoScroll = $false
$artifactsLayout.Controls.Add($artifactsTopPanel, 0, 0)

$artifactFilterGroup = New-Object System.Windows.Forms.GroupBox
$artifactFilterGroup.Text = "Schutzregeln und Filter"
$artifactFilterGroup.Size = New-Object System.Drawing.Size(620, 70)
$artifactsTopPanel.Controls.Add($artifactFilterGroup)

$artifactAgeLabel = New-Object System.Windows.Forms.Label
$artifactAgeLabel.Text = "Älter als Tage:"
$artifactAgeLabel.Location = New-Object System.Drawing.Point(12, 29)
$artifactAgeLabel.AutoSize = $true
$artifactFilterGroup.Controls.Add($artifactAgeLabel)

$artifactAgeNumeric = New-Object System.Windows.Forms.NumericUpDown
$artifactAgeNumeric.Location = New-Object System.Drawing.Point(110, 25)
$artifactAgeNumeric.Size = New-Object System.Drawing.Size(65, 25)
$artifactAgeNumeric.Minimum = 0
$artifactAgeNumeric.Maximum = 3650
$artifactAgeNumeric.Value = 30
$artifactFilterGroup.Controls.Add($artifactAgeNumeric)

$keepArtifactsLabel = New-Object System.Windows.Forms.Label
$keepArtifactsLabel.Text = "Neueste je Name behalten:"
$keepArtifactsLabel.Location = New-Object System.Drawing.Point(195, 29)
$keepArtifactsLabel.AutoSize = $true
$artifactFilterGroup.Controls.Add($keepArtifactsLabel)

$keepArtifactsNumeric = New-Object System.Windows.Forms.NumericUpDown
$keepArtifactsNumeric.Location = New-Object System.Drawing.Point(350, 25)
$keepArtifactsNumeric.Size = New-Object System.Drawing.Size(60, 25)
$keepArtifactsNumeric.Minimum = 0
$keepArtifactsNumeric.Maximum = 100
$keepArtifactsNumeric.Value = 1
$artifactFilterGroup.Controls.Add($keepArtifactsNumeric)

$onlyExpiredArtifactsCheckBox = New-Object System.Windows.Forms.CheckBox
$onlyExpiredArtifactsCheckBox.Text = "Nur bereits abgelaufene"
$onlyExpiredArtifactsCheckBox.Location = New-Object System.Drawing.Point(430, 28)
$onlyExpiredArtifactsCheckBox.AutoSize = $true
$artifactFilterGroup.Controls.Add($onlyExpiredArtifactsCheckBox)

$previewArtifactsButton = New-Object System.Windows.Forms.Button
$previewArtifactsButton.Text = "Vorschau laden"
$previewArtifactsButton.Size = New-Object System.Drawing.Size(140, 38)
$previewArtifactsButton.Margin = New-Object System.Windows.Forms.Padding(10, 20, 0, 0)
$artifactsTopPanel.Controls.Add($previewArtifactsButton)

$artifactsBottomPanel = New-Object System.Windows.Forms.TableLayoutPanel
$artifactsBottomPanel.Dock = "Fill"
$artifactsBottomPanel.ColumnCount = 2
$artifactsBottomPanel.RowCount = 1
[void]$artifactsBottomPanel.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))
)
[void]$artifactsBottomPanel.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 350))
)
$artifactsLayout.Controls.Add($artifactsBottomPanel, 0, 2)

$artifactsSummaryLabel = New-Object System.Windows.Forms.Label
$artifactsSummaryLabel.Text = "Noch keine Vorschau geladen."
$artifactsSummaryLabel.Dock = "Fill"
$artifactsSummaryLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$artifactsSummaryLabel.Padding = New-Object System.Windows.Forms.Padding(10, 0, 4, 0)
$artifactsSummaryLabel.AutoEllipsis = $true
$artifactsBottomPanel.Controls.Add($artifactsSummaryLabel, 0, 0)

$artifactsActionsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$artifactsActionsPanel.Dock = "Fill"
$artifactsActionsPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$artifactsActionsPanel.WrapContents = $false
$artifactsActionsPanel.Padding = New-Object System.Windows.Forms.Padding(4, 8, 0, 0)
$artifactsBottomPanel.Controls.Add($artifactsActionsPanel, 1, 0)

$selectAllArtifactsButton = New-Object System.Windows.Forms.Button
$selectAllArtifactsButton.Text = "Alle markieren"
$selectAllArtifactsButton.Size = New-Object System.Drawing.Size(105, 32)
$artifactsActionsPanel.Controls.Add($selectAllArtifactsButton)

$selectNoArtifactsButton = New-Object System.Windows.Forms.Button
$selectNoArtifactsButton.Text = "Keine"
$selectNoArtifactsButton.Size = New-Object System.Drawing.Size(75, 32)
$artifactsActionsPanel.Controls.Add($selectNoArtifactsButton)

$deleteArtifactsButton = New-Object System.Windows.Forms.Button
$deleteArtifactsButton.Text = "Markierte löschen"
$deleteArtifactsButton.Size = New-Object System.Drawing.Size(145, 32)
$artifactsActionsPanel.Controls.Add($deleteArtifactsButton)

$artifactsGrid = New-DataGrid
Add-GridCheckColumn -Grid $artifactsGrid
Add-GridTextColumn -Grid $artifactsGrid -Name "Created" -Header "Erstellt" -Width 145
Add-GridTextColumn -Grid $artifactsGrid -Name "Expires" -Header "Läuft ab" -Width 145
Add-GridTextColumn -Grid $artifactsGrid -Name "Expired" -Header "Abgelaufen" -Width 80
Add-GridTextColumn -Grid $artifactsGrid -Name "Size" -Header "Größe" -Width 90
Add-GridTextColumn -Grid $artifactsGrid -Name "Name" -Header "Name" -Width 380 -AutoSizeMode Fill
Add-GridTextColumn -Grid $artifactsGrid -Name "RunId" -Header "Run-ID" -Width 110
Add-GridTextColumn -Grid $artifactsGrid -Name "Id" -Header "Artefakt-ID" -Width 110
$artifactsLayout.Controls.Add($artifactsGrid, 0, 1)

# Tab: Release Manager
$releaseTab = New-Object System.Windows.Forms.TabPage
$releaseTab.Text = "Release Manager"
$tabControl.TabPages.Add($releaseTab)

$releaseLayout = New-Object System.Windows.Forms.TableLayoutPanel
$releaseLayout.Dock = "Fill"
$releaseLayout.ColumnCount = 1
$releaseLayout.RowCount = 2
[void]$releaseLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$releaseLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
$releaseTab.Controls.Add($releaseLayout)

$releaseTopFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$releaseTopFlow.Dock = "Fill"
$releaseTopFlow.AutoSize = $true
$releaseTopFlow.WrapContents = $true
$releaseTopFlow.Padding = New-Object System.Windows.Forms.Padding(8)
$releaseLayout.Controls.Add($releaseTopFlow,0,0)

$releaseDataGroup = New-Object System.Windows.Forms.GroupBox
$releaseDataGroup.Text = "Repository-Stand"
$releaseDataGroup.Size = New-Object System.Drawing.Size(350,128)
$releaseTopFlow.Controls.Add($releaseDataGroup)

$releaseCurrentLabel = New-Object System.Windows.Forms.Label
$releaseCurrentLabel.Text = "Noch nicht geladen."
$releaseCurrentLabel.Location = New-Object System.Drawing.Point(12,24)
$releaseCurrentLabel.Size = New-Object System.Drawing.Size(325,48)
$releaseCurrentLabel.AutoEllipsis = $true
$releaseDataGroup.Controls.Add($releaseCurrentLabel)

$releaseLoadButton = New-Object System.Windows.Forms.Button
$releaseLoadButton.Text = "Releases & Tags laden"
$releaseLoadButton.Location = New-Object System.Drawing.Point(12,78)
$releaseLoadButton.Size = New-Object System.Drawing.Size(160,32)
$releaseDataGroup.Controls.Add($releaseLoadButton)

$releaseVersionGroup = New-Object System.Windows.Forms.GroupBox
$releaseVersionGroup.Text = "Version und Ziel"
$releaseVersionGroup.Size = New-Object System.Drawing.Size(650,128)
$releaseTopFlow.Controls.Add($releaseVersionGroup)

$releaseTagLabel = New-Object System.Windows.Forms.Label
$releaseTagLabel.Text = "Neuer Tag:"
$releaseTagLabel.Location = New-Object System.Drawing.Point(12,26)
$releaseTagLabel.AutoSize = $true
$releaseVersionGroup.Controls.Add($releaseTagLabel)

$releaseTagTextBox = New-Object System.Windows.Forms.TextBox
$releaseTagTextBox.Location = New-Object System.Drawing.Point(80,22)
$releaseTagTextBox.Size = New-Object System.Drawing.Size(180,25)
$releaseVersionGroup.Controls.Add($releaseTagTextBox)

$releaseSuggestionPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$releaseSuggestionPanel.Location = New-Object System.Drawing.Point(270,18)
$releaseSuggestionPanel.Size = New-Object System.Drawing.Size(365,34)
$releaseSuggestionPanel.WrapContents = $false
$releaseVersionGroup.Controls.Add($releaseSuggestionPanel)

$releasePatchButton = New-Object System.Windows.Forms.Button; $releasePatchButton.Text = "Patch"; $releasePatchButton.Size = New-Object System.Drawing.Size(55,28); $releaseSuggestionPanel.Controls.Add($releasePatchButton)
$releaseMinorButton = New-Object System.Windows.Forms.Button; $releaseMinorButton.Text = "Minor"; $releaseMinorButton.Size = New-Object System.Drawing.Size(55,28); $releaseSuggestionPanel.Controls.Add($releaseMinorButton)
$releaseMajorButton = New-Object System.Windows.Forms.Button; $releaseMajorButton.Text = "Major"; $releaseMajorButton.Size = New-Object System.Drawing.Size(55,28); $releaseSuggestionPanel.Controls.Add($releaseMajorButton)
$releaseBetaButton = New-Object System.Windows.Forms.Button; $releaseBetaButton.Text = "Beta"; $releaseBetaButton.Size = New-Object System.Drawing.Size(52,28); $releaseSuggestionPanel.Controls.Add($releaseBetaButton)
$releaseRcButton = New-Object System.Windows.Forms.Button; $releaseRcButton.Text = "RC"; $releaseRcButton.Size = New-Object System.Drawing.Size(46,28); $releaseSuggestionPanel.Controls.Add($releaseRcButton)
$releaseStableButton = New-Object System.Windows.Forms.Button; $releaseStableButton.Text = "Stable"; $releaseStableButton.Size = New-Object System.Drawing.Size(58,28); $releaseSuggestionPanel.Controls.Add($releaseStableButton)

$releaseTitleLabel = New-Object System.Windows.Forms.Label
$releaseTitleLabel.Text = "Titel:"
$releaseTitleLabel.Location = New-Object System.Drawing.Point(12,61)
$releaseTitleLabel.AutoSize = $true
$releaseVersionGroup.Controls.Add($releaseTitleLabel)

$releaseTitleTextBox = New-Object System.Windows.Forms.TextBox
$releaseTitleTextBox.Location = New-Object System.Drawing.Point(80,57)
$releaseTitleTextBox.Size = New-Object System.Drawing.Size(315,25)
$releaseVersionGroup.Controls.Add($releaseTitleTextBox)

$releaseTargetLabel = New-Object System.Windows.Forms.Label
$releaseTargetLabel.Text = "Ziel:"
$releaseTargetLabel.Location = New-Object System.Drawing.Point(410,61)
$releaseTargetLabel.AutoSize = $true
$releaseVersionGroup.Controls.Add($releaseTargetLabel)

$releaseTargetTextBox = New-Object System.Windows.Forms.TextBox
$releaseTargetTextBox.Location = New-Object System.Drawing.Point(450,57)
$releaseTargetTextBox.Size = New-Object System.Drawing.Size(185,25)
$releaseVersionGroup.Controls.Add($releaseTargetTextBox)

$releaseFileVersionLabel = New-Object System.Windows.Forms.Label
$releaseFileVersionLabel.Text = "Dateiversion:"
$releaseFileVersionLabel.Location = New-Object System.Drawing.Point(12,95)
$releaseFileVersionLabel.AutoSize = $true
$releaseVersionGroup.Controls.Add($releaseFileVersionLabel)

$releaseFileVersionTextBox = New-Object System.Windows.Forms.TextBox
$releaseFileVersionTextBox.Location = New-Object System.Drawing.Point(95,91)
$releaseFileVersionTextBox.Size = New-Object System.Drawing.Size(120,25)
$releaseVersionGroup.Controls.Add($releaseFileVersionTextBox)

$releaseDetectVersionFilesButton = New-Object System.Windows.Forms.Button
$releaseDetectVersionFilesButton.Text = "Versionsdateien erkennen"
$releaseDetectVersionFilesButton.Location = New-Object System.Drawing.Point(225,88)
$releaseDetectVersionFilesButton.Size = New-Object System.Drawing.Size(160,30)
$releaseVersionGroup.Controls.Add($releaseDetectVersionFilesButton)

$releaseOptionsGroup = New-Object System.Windows.Forms.GroupBox
$releaseOptionsGroup.Text = "Release-Optionen"
$releaseOptionsGroup.Size = New-Object System.Drawing.Size(475,128)
$releaseTopFlow.Controls.Add($releaseOptionsGroup)

$releaseGenerateNotesCheckBox = New-Object System.Windows.Forms.CheckBox
$releaseGenerateNotesCheckBox.Text = "GitHub Release Notes generieren"
$releaseGenerateNotesCheckBox.Location = New-Object System.Drawing.Point(12,24)
$releaseGenerateNotesCheckBox.AutoSize = $true
$releaseGenerateNotesCheckBox.Checked = $true
$releaseOptionsGroup.Controls.Add($releaseGenerateNotesCheckBox)

$releaseFailNoCommitsCheckBox = New-Object System.Windows.Forms.CheckBox
$releaseFailNoCommitsCheckBox.Text = "Bei keinen neuen Commits abbrechen"
$releaseFailNoCommitsCheckBox.Location = New-Object System.Drawing.Point(12,51)
$releaseFailNoCommitsCheckBox.AutoSize = $true
$releaseFailNoCommitsCheckBox.Checked = $true
$releaseOptionsGroup.Controls.Add($releaseFailNoCommitsCheckBox)

$releaseVerifyTagCheckBox = New-Object System.Windows.Forms.CheckBox
$releaseVerifyTagCheckBox.Text = "Tag muss bereits existieren"
$releaseVerifyTagCheckBox.Location = New-Object System.Drawing.Point(12,78)
$releaseVerifyTagCheckBox.AutoSize = $true
$releaseOptionsGroup.Controls.Add($releaseVerifyTagCheckBox)

$releasePrereleaseCheckBox = New-Object System.Windows.Forms.CheckBox
$releasePrereleaseCheckBox.Text = "Pre-Release"
$releasePrereleaseCheckBox.Location = New-Object System.Drawing.Point(270,24)
$releasePrereleaseCheckBox.AutoSize = $true
$releaseOptionsGroup.Controls.Add($releasePrereleaseCheckBox)

$releaseDraftCheckBox = New-Object System.Windows.Forms.CheckBox
$releaseDraftCheckBox.Text = "Draft"
$releaseDraftCheckBox.Location = New-Object System.Drawing.Point(270,51)
$releaseDraftCheckBox.AutoSize = $true
$releaseOptionsGroup.Controls.Add($releaseDraftCheckBox)

$releaseLatestLabel = New-Object System.Windows.Forms.Label
$releaseLatestLabel.Text = "Latest:"
$releaseLatestLabel.Location = New-Object System.Drawing.Point(270,82)
$releaseLatestLabel.AutoSize = $true
$releaseOptionsGroup.Controls.Add($releaseLatestLabel)

$releaseLatestComboBox = New-Object System.Windows.Forms.ComboBox
$releaseLatestComboBox.DropDownStyle = "DropDownList"
$releaseLatestComboBox.Location = New-Object System.Drawing.Point(320,78)
$releaseLatestComboBox.Size = New-Object System.Drawing.Size(135,25)
[void]$releaseLatestComboBox.Items.Add("Automatisch")
[void]$releaseLatestComboBox.Items.Add("Als Latest")
[void]$releaseLatestComboBox.Items.Add("Nicht Latest")
$releaseLatestComboBox.SelectedIndex = 0
$releaseOptionsGroup.Controls.Add($releaseLatestComboBox)

$releaseMainSplit = New-Object System.Windows.Forms.SplitContainer
$releaseMainSplit.Dock = "Fill"
$releaseMainSplit.Orientation = [System.Windows.Forms.Orientation]::Vertical
$releaseLayout.Controls.Add($releaseMainSplit,0,1)

$releaseEditorLayout = New-Object System.Windows.Forms.TableLayoutPanel
$releaseEditorLayout.Dock = "Fill"
$releaseEditorLayout.Padding = New-Object System.Windows.Forms.Padding(8)
$releaseEditorLayout.ColumnCount = 1
$releaseEditorLayout.RowCount = 3
[void]$releaseEditorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,45)))
[void]$releaseEditorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,25)))
[void]$releaseEditorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,30)))
$releaseMainSplit.Panel1.Controls.Add($releaseEditorLayout)

$releaseNotesGroup = New-Object System.Windows.Forms.GroupBox
$releaseNotesGroup.Text = "Eigene Release Notes (optional, bei Auto-Notes vorangestellt)"
$releaseNotesGroup.Dock = "Fill"
$releaseEditorLayout.Controls.Add($releaseNotesGroup,0,0)
$releaseNotesTextBox = New-Object System.Windows.Forms.TextBox
$releaseNotesTextBox.Multiline = $true
$releaseNotesTextBox.ScrollBars = "Vertical"
$releaseNotesTextBox.Dock = "Fill"
$releaseNotesGroup.Controls.Add($releaseNotesTextBox)

$releaseAssetsGroup = New-Object System.Windows.Forms.GroupBox
$releaseAssetsGroup.Text = "Release Assets"
$releaseAssetsGroup.Dock = "Fill"
$releaseEditorLayout.Controls.Add($releaseAssetsGroup,0,1)
$releaseAssetsLayout = New-Object System.Windows.Forms.TableLayoutPanel
$releaseAssetsLayout.Dock = "Fill"
$releaseAssetsLayout.ColumnCount = 2
$releaseAssetsLayout.RowCount = 1
[void]$releaseAssetsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
[void]$releaseAssetsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,120)))
$releaseAssetsGroup.Controls.Add($releaseAssetsLayout)
$releaseAssetsListBox = New-Object System.Windows.Forms.ListBox
$releaseAssetsListBox.Dock = "Fill"
$releaseAssetsListBox.HorizontalScrollbar = $true
$releaseAssetsLayout.Controls.Add($releaseAssetsListBox,0,0)
$releaseAssetsButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$releaseAssetsButtons.Dock = "Fill"
$releaseAssetsButtons.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$releaseAssetsLayout.Controls.Add($releaseAssetsButtons,1,0)
$releaseAddAssetsButton = New-Object System.Windows.Forms.Button; $releaseAddAssetsButton.Text = "Hinzufügen"; $releaseAddAssetsButton.Size = New-Object System.Drawing.Size(105,30); $releaseAssetsButtons.Controls.Add($releaseAddAssetsButton)
$releaseRemoveAssetsButton = New-Object System.Windows.Forms.Button; $releaseRemoveAssetsButton.Text = "Entfernen"; $releaseRemoveAssetsButton.Size = New-Object System.Drawing.Size(105,30); $releaseAssetsButtons.Controls.Add($releaseRemoveAssetsButton)

$releaseVersionFilesGroup = New-Object System.Windows.Forms.GroupBox
$releaseVersionFilesGroup.Text = "Versionsdateien über Release-PR aktualisieren"
$releaseVersionFilesGroup.Dock = "Fill"
$releaseEditorLayout.Controls.Add($releaseVersionFilesGroup,0,2)
$releaseVersionFilesLayout = New-Object System.Windows.Forms.TableLayoutPanel
$releaseVersionFilesLayout.Dock = "Fill"
$releaseVersionFilesLayout.ColumnCount = 2
$releaseVersionFilesLayout.RowCount = 2
[void]$releaseVersionFilesLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
[void]$releaseVersionFilesLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,180)))
[void]$releaseVersionFilesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
[void]$releaseVersionFilesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
$releaseVersionFilesGroup.Controls.Add($releaseVersionFilesLayout)
$releaseVersionPathsTextBox = New-Object System.Windows.Forms.TextBox
$releaseVersionPathsTextBox.Multiline = $true
$releaseVersionPathsTextBox.ScrollBars = "Vertical"
$releaseVersionPathsTextBox.Dock = "Fill"
$releaseVersionPathsTextBox.Text = "package.json`r`nmanifest.json"
$releaseVersionFilesLayout.Controls.Add($releaseVersionPathsTextBox,0,0)
$releaseVersionHintLabel = New-Object System.Windows.Forms.Label
$releaseVersionHintLabel.Text = "Eine Datei pro Zeile. Nicht vorhandene Einträge vor dem Start entfernen. JSON, TOML, .csproj/.props und __version__ werden unterstützt."
$releaseVersionHintLabel.Dock = "Fill"
$releaseVersionHintLabel.AutoEllipsis = $true
$releaseVersionFilesLayout.Controls.Add($releaseVersionHintLabel,0,1)
$releaseCreateVersionPrButton = New-Object System.Windows.Forms.Button
$releaseCreateVersionPrButton.Text = "Versions-PR erstellen"
$releaseCreateVersionPrButton.Dock = "Fill"
$releaseCreateVersionPrButton.Margin = New-Object System.Windows.Forms.Padding(8,8,4,8)
$releaseVersionFilesLayout.SetRowSpan($releaseCreateVersionPrButton,2)
$releaseVersionFilesLayout.Controls.Add($releaseCreateVersionPrButton,1,0)

$releaseRightLayout = New-Object System.Windows.Forms.TableLayoutPanel
$releaseRightLayout.Dock = "Fill"
$releaseRightLayout.Padding = New-Object System.Windows.Forms.Padding(8)
$releaseRightLayout.ColumnCount = 1
$releaseRightLayout.RowCount = 2
[void]$releaseRightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
[void]$releaseRightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,52)))
$releaseMainSplit.Panel2.Controls.Add($releaseRightLayout)

$releaseGrid = New-DataGrid
$releaseGrid.ReadOnly = $true
Add-GridTextColumn -Grid $releaseGrid -Name "Published" -Header "Datum" -Width 135
Add-GridTextColumn -Grid $releaseGrid -Name "Tag" -Header "Tag" -Width 130
Add-GridTextColumn -Grid $releaseGrid -Name "Name" -Header "Titel" -Width 250 -AutoSizeMode Fill
Add-GridTextColumn -Grid $releaseGrid -Name "Pre" -Header "Pre" -Width 45
Add-GridTextColumn -Grid $releaseGrid -Name "Draft" -Header "Draft" -Width 50
Add-GridTextColumn -Grid $releaseGrid -Name "Latest" -Header "Latest" -Width 50
Add-GridTextColumn -Grid $releaseGrid -Name "Immutable" -Header "Immutable" -Width 70
$releaseRightLayout.Controls.Add($releaseGrid,0,0)

$releaseCreateButton = New-Object System.Windows.Forms.Button
$releaseCreateButton.Text = "Release erstellen"
$releaseCreateButton.Dock = "Right"
$releaseCreateButton.Size = New-Object System.Drawing.Size(170,36)
$releaseCreateButton.Margin = New-Object System.Windows.Forms.Padding(4,8,4,8)
$releaseRightLayout.Controls.Add($releaseCreateButton,0,1)

# Tab: Repository Setup & Templates
$setupTab = New-Object System.Windows.Forms.TabPage
$setupTab.Text = "Repo-Setup & Templates"
$tabControl.TabPages.Add($setupTab)

$setupLayout = New-Object System.Windows.Forms.TableLayoutPanel
$setupLayout.Dock = "Fill"
$setupLayout.ColumnCount = 1
$setupLayout.RowCount = 3
[void]$setupLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,235)))
[void]$setupLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
[void]$setupLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,150)))
$setupTab.Controls.Add($setupLayout)

$setupTopSplit = New-Object System.Windows.Forms.SplitContainer
$setupTopSplit.Dock = "Fill"
$setupTopSplit.Orientation = [System.Windows.Forms.Orientation]::Vertical
$setupTopSplit.Panel1.AutoScroll = $true
$setupTopSplit.Panel2.AutoScroll = $true
$setupLayout.Controls.Add($setupTopSplit,0,0)

$newRepoGroup = New-Object System.Windows.Forms.GroupBox
$newRepoGroup.Text = "Neues Repository erstellen"
$newRepoGroup.Dock = "Fill"
$newRepoGroup.Padding = New-Object System.Windows.Forms.Padding(10)
$setupTopSplit.Panel1.Controls.Add($newRepoGroup)

$newRepoTable = New-Object System.Windows.Forms.TableLayoutPanel
$newRepoTable.Dock = "Fill"
$newRepoTable.ColumnCount = 4
$newRepoTable.RowCount = 4
[void]$newRepoTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
[void]$newRepoTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
[void]$newRepoTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,34)))
[void]$newRepoTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
[void]$newRepoTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,115)))
[void]$newRepoTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
[void]$newRepoTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,95)))
[void]$newRepoTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
$newRepoGroup.Controls.Add($newRepoTable)

function Add-NewRepoLabel([string]$text,[int]$col,[int]$row) { $l=New-Object System.Windows.Forms.Label; $l.Text=$text; $l.Dock='Fill'; $l.TextAlign=[System.Drawing.ContentAlignment]::MiddleLeft; $newRepoTable.Controls.Add($l,$col,$row) }
Add-NewRepoLabel "Benutzer / Org:" 0 0
$newRepoOwnerTextBox = New-Object System.Windows.Forms.TextBox; $newRepoOwnerTextBox.Dock='Fill'; $newRepoTable.Controls.Add($newRepoOwnerTextBox,1,0)
Add-NewRepoLabel "Name:" 2 0
$newRepoNameTextBox = New-Object System.Windows.Forms.TextBox; $newRepoNameTextBox.Dock='Fill'; $newRepoTable.Controls.Add($newRepoNameTextBox,3,0)
Add-NewRepoLabel "Beschreibung:" 0 1
$newRepoDescriptionTextBox = New-Object System.Windows.Forms.TextBox; $newRepoDescriptionTextBox.Dock='Fill'; $newRepoTable.SetColumnSpan($newRepoDescriptionTextBox,3); $newRepoTable.Controls.Add($newRepoDescriptionTextBox,1,1)
Add-NewRepoLabel "Sichtbarkeit:" 0 2
$newRepoVisibilityComboBox = New-Object System.Windows.Forms.ComboBox; $newRepoVisibilityComboBox.DropDownStyle='DropDownList'; $newRepoVisibilityComboBox.Dock='Fill'; [void]$newRepoVisibilityComboBox.Items.Add('public'); [void]$newRepoVisibilityComboBox.Items.Add('private'); [void]$newRepoVisibilityComboBox.Items.Add('internal'); $newRepoVisibilityComboBox.SelectedIndex=0; $newRepoTable.Controls.Add($newRepoVisibilityComboBox,1,2)
Add-NewRepoLabel "GitHub-Template:" 2 2
$newRepoSourceTemplateTextBox = New-Object System.Windows.Forms.TextBox; $newRepoSourceTemplateTextBox.Dock='Fill'; $newRepoSourceTemplateTextBox.Text=''; $newRepoTable.Controls.Add($newRepoSourceTemplateTextBox,3,2)

$newRepoBottomFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$newRepoBottomFlow.Dock='Fill'; $newRepoBottomFlow.WrapContents=$true
$newRepoTable.SetColumnSpan($newRepoBottomFlow,4); $newRepoTable.Controls.Add($newRepoBottomFlow,0,3)
$newRepoReadmeCheckBox = New-Object System.Windows.Forms.CheckBox; $newRepoReadmeCheckBox.Text='README initialisieren'; $newRepoReadmeCheckBox.Checked=$true; $newRepoReadmeCheckBox.AutoSize=$true; $newRepoBottomFlow.Controls.Add($newRepoReadmeCheckBox)
$newRepoGitignoreTextBox = New-Object System.Windows.Forms.TextBox; $newRepoGitignoreTextBox.Width=90; $newRepoGitignoreTextBox.Text=''; $newRepoBottomFlow.Controls.Add((New-Object System.Windows.Forms.Label -Property @{Text=' .gitignore:';AutoSize=$true;Margin=(New-Object System.Windows.Forms.Padding(8,7,2,0))})); $newRepoBottomFlow.Controls.Add($newRepoGitignoreTextBox)
$newRepoLicenseTextBox = New-Object System.Windows.Forms.TextBox; $newRepoLicenseTextBox.Width=90; $newRepoLicenseTextBox.Text=''; $newRepoBottomFlow.Controls.Add((New-Object System.Windows.Forms.Label -Property @{Text=' Lizenz:';AutoSize=$true;Margin=(New-Object System.Windows.Forms.Padding(8,7,2,0))})); $newRepoBottomFlow.Controls.Add($newRepoLicenseTextBox)
$applyTemplateAfterCreateCheckBox = New-Object System.Windows.Forms.CheckBox; $applyTemplateAfterCreateCheckBox.Text='Aktuelle Template-Werte danach anwenden'; $applyTemplateAfterCreateCheckBox.Checked=$true; $applyTemplateAfterCreateCheckBox.AutoSize=$true; $applyTemplateAfterCreateCheckBox.Margin=New-Object System.Windows.Forms.Padding(12,5,5,0); $newRepoBottomFlow.Controls.Add($applyTemplateAfterCreateCheckBox)
$newRepoUseSelectedTemplateButton = New-Object System.Windows.Forms.Button; $newRepoUseSelectedTemplateButton.Text='Ausgewähltes Repo als Content-Basis'; $newRepoUseSelectedTemplateButton.Size=New-Object System.Drawing.Size(225,30); $newRepoBottomFlow.Controls.Add($newRepoUseSelectedTemplateButton)
$newRepoCreateButton = New-Object System.Windows.Forms.Button; $newRepoCreateButton.Text='Repository erstellen'; $newRepoCreateButton.Size=New-Object System.Drawing.Size(145,30); $newRepoBottomFlow.Controls.Add($newRepoCreateButton)

$templateGroup = New-Object System.Windows.Forms.GroupBox
$templateGroup.Text = "Template-Verwaltung"
$templateGroup.Dock = "Fill"
$templateGroup.Padding = New-Object System.Windows.Forms.Padding(10)
$setupTopSplit.Panel2.Controls.Add($templateGroup)

$templateFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$templateFlow.Dock='Fill'; $templateFlow.FlowDirection=[System.Windows.Forms.FlowDirection]::TopDown; $templateFlow.WrapContents=$false
$templateGroup.Controls.Add($templateFlow)
$templateComboRow = New-Object System.Windows.Forms.FlowLayoutPanel; $templateComboRow.AutoSize=$true; $templateComboRow.WrapContents=$false; $templateFlow.Controls.Add($templateComboRow)
$templateComboRow.Controls.Add((New-Object System.Windows.Forms.Label -Property @{Text='Template:';AutoSize=$true;Margin=(New-Object System.Windows.Forms.Padding(3,7,4,0))}))
$templateComboBox = New-Object System.Windows.Forms.ComboBox; $templateComboBox.DropDownStyle='DropDownList'; $templateComboBox.Width=240; $templateComboRow.Controls.Add($templateComboBox)
$templateLoadButton = New-Object System.Windows.Forms.Button; $templateLoadButton.Text='Laden'; $templateLoadButton.Size=New-Object System.Drawing.Size(75,28); $templateComboRow.Controls.Add($templateLoadButton)
$templateRecommendButton = New-Object System.Windows.Forms.Button; $templateRecommendButton.Text='Profil empfehlen'; $templateRecommendButton.Size=New-Object System.Drawing.Size(120,28); $templateComboRow.Controls.Add($templateRecommendButton)
$templateImportButton = New-Object System.Windows.Forms.Button; $templateImportButton.Text='Repo importieren'; $templateImportButton.Size=New-Object System.Drawing.Size(115,28); $templateComboRow.Controls.Add($templateImportButton)
$templateNameRow = New-Object System.Windows.Forms.FlowLayoutPanel; $templateNameRow.AutoSize=$true; $templateNameRow.WrapContents=$false; $templateFlow.Controls.Add($templateNameRow)
$templateNameRow.Controls.Add((New-Object System.Windows.Forms.Label -Property @{Text='Name:';AutoSize=$true;Margin=(New-Object System.Windows.Forms.Padding(3,7,4,0))}))
$templateNameTextBox = New-Object System.Windows.Forms.TextBox; $templateNameTextBox.Width=215; $templateNameRow.Controls.Add($templateNameTextBox)
$templateNameRow.Controls.Add((New-Object System.Windows.Forms.Label -Property @{Text='Bereich:';AutoSize=$true;Margin=(New-Object System.Windows.Forms.Padding(8,7,4,0))}))
$templateScopeComboBox = New-Object System.Windows.Forms.ComboBox; $templateScopeComboBox.DropDownStyle='DropDownList'; $templateScopeComboBox.Width=180; $templateNameRow.Controls.Add($templateScopeComboBox)
$templateSaveButton = New-Object System.Windows.Forms.Button; $templateSaveButton.Text='Speichern'; $templateSaveButton.Size=New-Object System.Drawing.Size(85,28); $templateNameRow.Controls.Add($templateSaveButton)
$templateDeleteButton = New-Object System.Windows.Forms.Button; $templateDeleteButton.Text='Löschen'; $templateDeleteButton.Size=New-Object System.Drawing.Size(75,28); $templateNameRow.Controls.Add($templateDeleteButton)
$templateDescriptionRow = New-Object System.Windows.Forms.FlowLayoutPanel; $templateDescriptionRow.AutoSize=$true; $templateDescriptionRow.WrapContents=$false; $templateFlow.Controls.Add($templateDescriptionRow)
$templateDescriptionRow.Controls.Add((New-Object System.Windows.Forms.Label -Property @{Text='Beschreibung:';AutoSize=$true;Margin=(New-Object System.Windows.Forms.Padding(3,7,4,0))}))
$templateDescriptionTextBox = New-Object System.Windows.Forms.TextBox; $templateDescriptionTextBox.Width=470; $templateDescriptionRow.Controls.Add($templateDescriptionTextBox)
$templateApplyButton = New-Object System.Windows.Forms.Button; $templateApplyButton.Text='GitHub-Einstellungen anwenden'; $templateApplyButton.Size=New-Object System.Drawing.Size(210,34); $templateApplyButton.Margin=New-Object System.Windows.Forms.Padding(3,6,3,3); $templateFlow.Controls.Add($templateApplyButton)
$templateMarkRow = New-Object System.Windows.Forms.FlowLayoutPanel; $templateMarkRow.AutoSize=$true; $templateMarkRow.WrapContents=$false; $templateFlow.Controls.Add($templateMarkRow)
$templateMarkAllButton = New-Object System.Windows.Forms.Button; $templateMarkAllButton.Text='Alle Anwenden'; $templateMarkAllButton.Size=New-Object System.Drawing.Size(105,28); $templateMarkRow.Controls.Add($templateMarkAllButton)
$templateMarkNoneButton = New-Object System.Windows.Forms.Button; $templateMarkNoneButton.Text='Keine Anwenden'; $templateMarkNoneButton.Size=New-Object System.Drawing.Size(110,28); $templateMarkRow.Controls.Add($templateMarkNoneButton)
$templateHintLabel = New-Object System.Windows.Forms.Label; $templateHintLabel.Text='Nur Zeilen mit „Anwenden = Ja“ werden verändert. Dadurch kann ein Template auch bewusst nur Teilbereiche setzen.'; $templateHintLabel.Size=New-Object System.Drawing.Size(430,40); $templateFlow.Controls.Add($templateHintLabel)

$setupSettingsFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$setupSettingsFlow.Dock = "Fill"
$setupSettingsFlow.AutoScroll = $true
$setupSettingsFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$setupSettingsFlow.WrapContents = $false
$setupSettingsFlow.Padding = New-Object System.Windows.Forms.Padding(4)
$setupLayout.Controls.Add($setupSettingsFlow,0,1)
foreach ($category in @('Repository','Merge & Branches','Security & Dependabot','GitHub Actions','Default-Branch Ruleset')) {
    $group = New-SetupCategoryGroup -Category $category
    $setupSettingsFlow.Controls.Add($group)
}

$setupResultGroup = New-Object System.Windows.Forms.GroupBox
$setupResultGroup.Text = "Ergebnis / Protokoll der letzten Anwendung"
$setupResultGroup.Dock = "Fill"
$setupResultGroup.Padding = New-Object System.Windows.Forms.Padding(8)
$setupLayout.Controls.Add($setupResultGroup,0,2)
$setupResultTextBox = New-Object System.Windows.Forms.TextBox
$setupResultTextBox.Multiline = $true
$setupResultTextBox.ReadOnly = $true
$setupResultTextBox.ScrollBars = "Vertical"
$setupResultTextBox.Dock = "Fill"
$setupResultTextBox.Font = New-Object System.Drawing.Font("Consolas",9)
$setupResultGroup.Controls.Add($setupResultTextBox)


# Tab: Repository-Einstellungen
$settingsTab = New-Object System.Windows.Forms.TabPage
$settingsTab.Text = "Repository-Einstellungen"
$tabControl.TabPages.Add($settingsTab)

$settingsPanel = New-Object System.Windows.Forms.Panel
$settingsPanel.Dock = "Fill"
$settingsPanel.AutoScroll = $true
$settingsTab.Controls.Add($settingsPanel)

$loadSettingsButton = New-Object System.Windows.Forms.Button
$loadSettingsButton.Text = "Einstellungen neu laden"
$loadSettingsButton.Location = New-Object System.Drawing.Point(18, 18)
$loadSettingsButton.Size = New-Object System.Drawing.Size(170, 34)
$settingsPanel.Controls.Add($loadSettingsButton)

$repoInfoGroup = New-Object System.Windows.Forms.GroupBox
$repoInfoGroup.Text = "Repository"
$repoInfoGroup.Location = New-Object System.Drawing.Point(18, 68)
$repoInfoGroup.Size = New-Object System.Drawing.Size(560, 205)
$settingsPanel.Controls.Add($repoInfoGroup)

$infoLabels = @(
    @("Repository:", "repositoryNameValueLabel", 28),
    @("Standardbranch:", "defaultBranchValueLabel", 60),
    @("Sichtbarkeit:", "visibilityValueLabel", 92),
    @("Berechtigung:", "permissionValueLabel", 124),
    @("Git-Datengröße:", "gitSizeValueLabel", 156)
)

foreach ($definition in $infoLabels) {
    $caption = New-Object System.Windows.Forms.Label
    $caption.Text = $definition[0]
    $caption.Location = New-Object System.Drawing.Point(16, [int]$definition[2])
    $caption.Size = New-Object System.Drawing.Size(125, 22)
    $repoInfoGroup.Controls.Add($caption)

    $value = New-Object System.Windows.Forms.Label
    $value.Text = "–"
    $value.Location = New-Object System.Drawing.Point(150, [int]$definition[2])
    $value.Size = New-Object System.Drawing.Size(390, 22)
    $repoInfoGroup.Controls.Add($value)

    Set-Variable -Name $definition[1] -Value $value -Scope Script
}

$branchGroup = New-Object System.Windows.Forms.GroupBox
$branchGroup.Text = "Branches"
$branchGroup.Location = New-Object System.Drawing.Point(598, 68)
$branchGroup.Size = New-Object System.Drawing.Size(560, 120)
$settingsPanel.Controls.Add($branchGroup)

$autoDeleteBranchesCheckBox = New-Object System.Windows.Forms.CheckBox
$autoDeleteBranchesCheckBox.Text = "Head-Branches nach dem Mergen automatisch löschen"
$autoDeleteBranchesCheckBox.Location = New-Object System.Drawing.Point(16, 30)
$autoDeleteBranchesCheckBox.AutoSize = $true
$branchGroup.Controls.Add($autoDeleteBranchesCheckBox)

$saveAutoDeleteBranchesButton = New-Object System.Windows.Forms.Button
$saveAutoDeleteBranchesButton.Text = "Speichern"
$saveAutoDeleteBranchesButton.Location = New-Object System.Drawing.Point(16, 68)
$saveAutoDeleteBranchesButton.Size = New-Object System.Drawing.Size(105, 32)
$branchGroup.Controls.Add($saveAutoDeleteBranchesButton)

$artifactRetentionGroup = New-Object System.Windows.Forms.GroupBox
$artifactRetentionGroup.Text = "Actions-Artefakte und Logs"
$artifactRetentionGroup.Location = New-Object System.Drawing.Point(18, 292)
$artifactRetentionGroup.Size = New-Object System.Drawing.Size(560, 135)
$settingsPanel.Controls.Add($artifactRetentionGroup)

$artifactRetentionDescription = New-Object System.Windows.Forms.Label
$artifactRetentionDescription.Text = "Aufbewahrungszeit für neu erzeugte Workflow-Artefakte und Logs:"
$artifactRetentionDescription.Location = New-Object System.Drawing.Point(16, 28)
$artifactRetentionDescription.Size = New-Object System.Drawing.Size(510, 22)
$artifactRetentionGroup.Controls.Add($artifactRetentionDescription)

$artifactRetentionNumeric = New-Object System.Windows.Forms.NumericUpDown
$artifactRetentionNumeric.Location = New-Object System.Drawing.Point(16, 60)
$artifactRetentionNumeric.Size = New-Object System.Drawing.Size(85, 25)
$artifactRetentionNumeric.Minimum = 1
$artifactRetentionNumeric.Maximum = 400
$artifactRetentionNumeric.Value = 30
$artifactRetentionGroup.Controls.Add($artifactRetentionNumeric)

$artifactRetentionDaysLabel = New-Object System.Windows.Forms.Label
$artifactRetentionDaysLabel.Text = "Tage"
$artifactRetentionDaysLabel.Location = New-Object System.Drawing.Point(108, 63)
$artifactRetentionDaysLabel.AutoSize = $true
$artifactRetentionGroup.Controls.Add($artifactRetentionDaysLabel)

$saveArtifactRetentionButton = New-Object System.Windows.Forms.Button
$saveArtifactRetentionButton.Text = "Speichern"
$saveArtifactRetentionButton.Location = New-Object System.Drawing.Point(165, 56)
$saveArtifactRetentionButton.Size = New-Object System.Drawing.Size(105, 32)
$artifactRetentionGroup.Controls.Add($saveArtifactRetentionButton)

$artifactRetentionStatusLabel = New-Object System.Windows.Forms.Label
$artifactRetentionStatusLabel.Text = "Noch nicht geladen."
$artifactRetentionStatusLabel.Location = New-Object System.Drawing.Point(16, 98)
$artifactRetentionStatusLabel.Size = New-Object System.Drawing.Size(520, 22)
$artifactRetentionGroup.Controls.Add($artifactRetentionStatusLabel)

$cacheSettingsGroup = New-Object System.Windows.Forms.GroupBox
$cacheSettingsGroup.Text = "Actions-Cache-Limits"
$cacheSettingsGroup.Location = New-Object System.Drawing.Point(598, 207)
$cacheSettingsGroup.Size = New-Object System.Drawing.Size(560, 220)
$settingsPanel.Controls.Add($cacheSettingsGroup)

$cacheRetentionDescription = New-Object System.Windows.Forms.Label
$cacheRetentionDescription.Text = "Cache-Aufbewahrung:"
$cacheRetentionDescription.Location = New-Object System.Drawing.Point(16, 30)
$cacheRetentionDescription.Size = New-Object System.Drawing.Size(150, 22)
$cacheSettingsGroup.Controls.Add($cacheRetentionDescription)

$cacheRetentionNumeric = New-Object System.Windows.Forms.NumericUpDown
$cacheRetentionNumeric.Location = New-Object System.Drawing.Point(170, 26)
$cacheRetentionNumeric.Size = New-Object System.Drawing.Size(85, 25)
$cacheRetentionNumeric.Minimum = 1
$cacheRetentionNumeric.Maximum = 365
$cacheRetentionNumeric.Value = 7
$cacheSettingsGroup.Controls.Add($cacheRetentionNumeric)

$cacheRetentionDaysLabel = New-Object System.Windows.Forms.Label
$cacheRetentionDaysLabel.Text = "Tage"
$cacheRetentionDaysLabel.Location = New-Object System.Drawing.Point(262, 29)
$cacheRetentionDaysLabel.AutoSize = $true
$cacheSettingsGroup.Controls.Add($cacheRetentionDaysLabel)

$saveCacheRetentionButton = New-Object System.Windows.Forms.Button
$saveCacheRetentionButton.Text = "Speichern"
$saveCacheRetentionButton.Location = New-Object System.Drawing.Point(325, 22)
$saveCacheRetentionButton.Size = New-Object System.Drawing.Size(105, 32)
$cacheSettingsGroup.Controls.Add($saveCacheRetentionButton)

$cacheRetentionStatusLabel = New-Object System.Windows.Forms.Label
$cacheRetentionStatusLabel.Text = "Noch nicht geladen."
$cacheRetentionStatusLabel.Location = New-Object System.Drawing.Point(16, 62)
$cacheRetentionStatusLabel.Size = New-Object System.Drawing.Size(520, 22)
$cacheSettingsGroup.Controls.Add($cacheRetentionStatusLabel)

$cacheStorageDescription = New-Object System.Windows.Forms.Label
$cacheStorageDescription.Text = "Maximale Cache-Größe:"
$cacheStorageDescription.Location = New-Object System.Drawing.Point(16, 110)
$cacheStorageDescription.Size = New-Object System.Drawing.Size(150, 22)
$cacheSettingsGroup.Controls.Add($cacheStorageDescription)

$cacheStorageNumeric = New-Object System.Windows.Forms.NumericUpDown
$cacheStorageNumeric.Location = New-Object System.Drawing.Point(170, 106)
$cacheStorageNumeric.Size = New-Object System.Drawing.Size(85, 25)
$cacheStorageNumeric.Minimum = 1
$cacheStorageNumeric.Maximum = 10000
$cacheStorageNumeric.Value = 10
$cacheSettingsGroup.Controls.Add($cacheStorageNumeric)

$cacheStorageGbLabel = New-Object System.Windows.Forms.Label
$cacheStorageGbLabel.Text = "GB"
$cacheStorageGbLabel.Location = New-Object System.Drawing.Point(262, 109)
$cacheStorageGbLabel.AutoSize = $true
$cacheSettingsGroup.Controls.Add($cacheStorageGbLabel)

$saveCacheStorageButton = New-Object System.Windows.Forms.Button
$saveCacheStorageButton.Text = "Speichern"
$saveCacheStorageButton.Location = New-Object System.Drawing.Point(325, 102)
$saveCacheStorageButton.Size = New-Object System.Drawing.Size(105, 32)
$cacheSettingsGroup.Controls.Add($saveCacheStorageButton)

$cacheStorageStatusLabel = New-Object System.Windows.Forms.Label
$cacheStorageStatusLabel.Text = "Noch nicht geladen."
$cacheStorageStatusLabel.Location = New-Object System.Drawing.Point(16, 142)
$cacheStorageStatusLabel.Size = New-Object System.Drawing.Size(520, 22)
$cacheSettingsGroup.Controls.Add($cacheStorageStatusLabel)

$cachePlanHintLabel = New-Object System.Windows.Forms.Label
$cachePlanHintLabel.Text = "Die Cache-Limits sind tarif- und berechtigungsabhängig. Nicht verfügbare Felder werden deaktiviert."
$cachePlanHintLabel.Location = New-Object System.Drawing.Point(16, 174)
$cachePlanHintLabel.Size = New-Object System.Drawing.Size(520, 36)
$cacheSettingsGroup.Controls.Add($cachePlanHintLabel)

$recommendationsGroup = New-Object System.Windows.Forms.GroupBox
$recommendationsGroup.Text = "Bewusst nicht automatisch gelöscht"
$recommendationsGroup.Location = New-Object System.Drawing.Point(18, 447)
$recommendationsGroup.Size = New-Object System.Drawing.Size(1140, 160)
$settingsPanel.Controls.Add($recommendationsGroup)

$recommendationsTextBox = New-Object System.Windows.Forms.TextBox
$recommendationsTextBox.Multiline = $true
$recommendationsTextBox.ReadOnly = $true
$recommendationsTextBox.BorderStyle = "None"
$recommendationsTextBox.BackColor = [System.Drawing.SystemColors]::Control
$recommendationsTextBox.Location = New-Object System.Drawing.Point(16, 26)
$recommendationsTextBox.Size = New-Object System.Drawing.Size(1105, 120)
$recommendationsTextBox.Text = @"
• Releases, Tags und Release-Assets: können echte Veröffentlichungen unbrauchbar machen und werden deshalb nicht pauschal gelöscht.
• Git-Historie und große Binärdateien: eine Verkleinerung erfordert meist filter-repo/LFS und einen Force-Push. Das ist kein normaler Release-Cleanup.
• Packages und Container-Images: besitzen eigene Versionierungs- und Aufbewahrungsregeln und sollten projektspezifisch geprüft werden.
• Branches: automatische Löschung hält die Oberfläche sauber, reduziert die eigentliche Git-Historie aber normalerweise kaum.
"@
$recommendationsGroup.Controls.Add($recommendationsTextBox)

function Initialize-ManagerSplitters {
    # SplitterDistance darf erst gesetzt werden, wenn WinForms die tatsächliche
    # Fensterbreite berechnet hat. Sonst kann es bei DPI-Skalierung oder kleinen
    # Startgrößen zu ArgumentOutOfRangeException kommen.
    try {
        if ($releaseMainSplit.Width -gt 700) {
            $distance = [Math]::Max(360, [Math]::Min([int]($releaseMainSplit.Width * 0.46), $releaseMainSplit.Width - 330))
            if ($distance -gt 0 -and $distance -lt $releaseMainSplit.Width) {
                $releaseMainSplit.SplitterDistance = $distance
            }
        }

        if ($setupTopSplit.Width -gt 760) {
            $distance = [Math]::Max(430, [Math]::Min([int]($setupTopSplit.Width * 0.55), $setupTopSplit.Width - 340))
            if ($distance -gt 0 -and $distance -lt $setupTopSplit.Width) {
                $setupTopSplit.SplitterDistance = $distance
            }
        }
    }
    catch {
        Write-Log -Level WARN -Message "Splitter konnten nicht initial positioniert werden: $($_.Exception.Message)"
    }
}

# Ereignisse
$loginButton.Add_Click({ Start-GhAuthentication })
$openLogButton.Add_Click({ Open-DiagnosticLog })
$checkAuthButton.Add_Click({
    if (Update-AuthenticationState) {
        Set-Status "GitHub-Anmeldung ist gültig."
    }
    else {
        Set-Status "Keine gültige GitHub-Anmeldung."
    }
})
$loadRepositoriesButton.Add_Click({ Load-Repositories })
$ownerTextBox.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $eventArgs.SuppressKeyPress = $true
        Load-Repositories
    }
})
$repositoryCombo.Add_SelectedIndexChanged({
    Update-RepositorySummary
    Clear-PreviewGrids
    Clear-ReleaseData
})
$openRepositoryButton.Add_Click({ Open-SelectedRepository })

$previewRunsButton.Add_Click({ Preview-WorkflowRuns })
$selectAllRunsButton.Add_Click({ Set-AllRowsMarked -Grid $runsGrid -Value $true })
$selectNoRunsButton.Add_Click({ Set-AllRowsMarked -Grid $runsGrid -Value $false })
$deleteRunsButton.Add_Click({ Delete-SelectedWorkflowRuns })
$runsGrid.Add_CellDoubleClick({
    param($sender, $eventArgs)
    if ($eventArgs.RowIndex -ge 0) {
        $run = $runsGrid.Rows[$eventArgs.RowIndex].Tag
        if ($null -ne $run -and -not [string]::IsNullOrWhiteSpace([string]$run.url)) {
            Start-Process ([string]$run.url)
        }
    }
})

$previewCachesButton.Add_Click({ Preview-Caches })
$selectAllCachesButton.Add_Click({ Set-AllRowsMarked -Grid $cachesGrid -Value $true })
$selectNoCachesButton.Add_Click({ Set-AllRowsMarked -Grid $cachesGrid -Value $false })
$deleteCachesButton.Add_Click({ Delete-SelectedCaches })

$previewArtifactsButton.Add_Click({ Preview-Artifacts })
$selectAllArtifactsButton.Add_Click({ Set-AllRowsMarked -Grid $artifactsGrid -Value $true })
$selectNoArtifactsButton.Add_Click({ Set-AllRowsMarked -Grid $artifactsGrid -Value $false })
$deleteArtifactsButton.Add_Click({ Delete-SelectedArtifacts })
$artifactsGrid.Add_CellDoubleClick({
    param($sender, $eventArgs)
    if ($eventArgs.RowIndex -ge 0) {
        $artifact = $artifactsGrid.Rows[$eventArgs.RowIndex].Tag
        if ($null -ne $artifact -and $null -ne $artifact.workflow_run) {
            $repositoryName = Get-SelectedRepositoryName
            Start-Process "https://github.com/$repositoryName/actions/runs/$($artifact.workflow_run.id)"
        }
    }
})

$releaseLoadButton.Add_Click({ Load-ReleaseData })
$releasePatchButton.Add_Click({ Set-ReleaseVersionSuggestion -Kind 'Patch' })
$releaseMinorButton.Add_Click({ Set-ReleaseVersionSuggestion -Kind 'Minor' })
$releaseMajorButton.Add_Click({ Set-ReleaseVersionSuggestion -Kind 'Major' })
$releaseBetaButton.Add_Click({ Set-ReleaseVersionSuggestion -Kind 'Beta' })
$releaseRcButton.Add_Click({ Set-ReleaseVersionSuggestion -Kind 'RC' })
$releaseStableButton.Add_Click({ Set-ReleaseVersionSuggestion -Kind 'Stable' })
$releaseTagTextBox.Add_Leave({ Update-ReleaseTitleFromTag })
$releaseAddAssetsButton.Add_Click({ Add-ReleaseAssets })
$releaseRemoveAssetsButton.Add_Click({ Remove-ReleaseAssets })
$releaseDetectVersionFilesButton.Add_Click({ Detect-ReleaseVersionPaths })
$releaseCreateVersionPrButton.Add_Click({ Create-ReleaseVersionPullRequest })
$releaseCreateButton.Add_Click({ Create-GitHubRelease })
$releaseGrid.Add_CellDoubleClick({
    param($sender,$eventArgs)
    if ($eventArgs.RowIndex -ge 0) {
        $release = $releaseGrid.Rows[$eventArgs.RowIndex].Tag
        if ($null -ne $release -and -not [string]::IsNullOrWhiteSpace([string]$release.tagName)) {
            $repo = Get-SelectedRepositoryName
            Start-Process "https://github.com/$repo/releases/tag/$([System.Uri]::EscapeDataString([string]$release.tagName))"
        }
    }
})

$templateLoadButton.Add_Click({ Load-SelectedTemplate })
$templateComboBox.Add_SelectedIndexChanged({
    if ($templateComboBox.SelectedIndex -ge 0) { Load-SelectedTemplate }
})
$templateRecommendButton.Add_Click({ Select-RecommendedTemplateForCurrentRepository })
$templateImportButton.Add_Click({ Import-SelectedRepositoryAsTemplate })
$templateSaveButton.Add_Click({ Save-CurrentTemplate })
$templateDeleteButton.Add_Click({ Delete-SelectedTemplate })
$templateApplyButton.Add_Click({ Apply-CurrentSetupTemplate })
$templateMarkAllButton.Add_Click({ Set-AllSetupApply -Value $true })
$templateMarkNoneButton.Add_Click({ Set-AllSetupApply -Value $false })
$newRepoUseSelectedTemplateButton.Add_Click({ try { $newRepoSourceTemplateTextBox.Text = Get-SelectedRepositoryName } catch { Show-Error -Title 'Content-Basis konnte nicht übernommen werden' -ErrorObject $_ } })
$newRepoCreateButton.Add_Click({ Create-RepositoryFromUi })
$setupSettingsFlow.Add_Resize({ Update-SetupGroupWidths })

$loadSettingsButton.Add_Click({ Load-RepositorySettings })
$saveArtifactRetentionButton.Add_Click({ Save-ArtifactRetention })
$saveCacheRetentionButton.Add_Click({ Save-CacheRetention })
$saveCacheStorageButton.Add_Click({ Save-CacheStorage })
$saveAutoDeleteBranchesButton.Add_Click({ Save-AutoDeleteBranches })

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $settingsTab -and $null -ne $repositoryCombo.SelectedItem) {
        Load-RepositorySettings
    }
    elseif ($tabControl.SelectedTab -eq $releaseTab -and $null -ne $repositoryCombo.SelectedItem -and $script:State.Releases.Count -eq 0) {
        Load-ReleaseData
    }
    elseif ($tabControl.SelectedTab -eq $setupTab) {
        Update-SetupGroupWidths
        if ([string]::IsNullOrWhiteSpace($newRepoOwnerTextBox.Text) -and -not [string]::IsNullOrWhiteSpace([string]$script:State.Login)) {
            $newRepoOwnerTextBox.Text = $script:State.Login
        }
    }
})

$form.Add_Shown({
    Initialize-ManagerSplitters
    Initialize-Application
})

$form.Add_FormClosing({
    param($sender,$eventArgs)
    if ($script:BulkCleanup.Running) {
        $choice = [System.Windows.Forms.MessageBox]::Show(
            $form,
            'Bulk-Jobs sind noch aktiv. Abbrechen und nach Abschluss der laufenden Requests beenden?',
            'Laufende Bulk-Jobs',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        $eventArgs.Cancel = $true
        if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
            $script:BulkCleanup.CloseWhenDone = $true
            $script:BulkCleanup.Cancellation.Cancel()
            Set-BulkMessage 'Beenden nach sicherem Job-Abbruch ...'
        }
    }
})
$form.Add_FormClosed({
    if ($script:BulkControls.ContainsKey('Timer')) {
        $script:BulkControls.Timer.Stop()
        $script:BulkControls.Timer.Dispose()
    }
})
[void]$form.ShowDialog()
