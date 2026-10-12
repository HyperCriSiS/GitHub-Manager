param(
    [ValidateSet('Preview', 'Execute')][string]$Mode,
    [string]$Repository,
    [hashtable]$Options,
    [object[]]$Plans,
    [System.Net.Http.HttpClient]$Client,
    [System.Threading.SemaphoreSlim]$ApiLimiter,
    [object]$DeleteThrottle,
    [System.Threading.CancellationToken]$CancellationToken,
    [System.Collections.Concurrent.ConcurrentQueue[object]]$Progress
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

function Publish-BulkProgress {
    param([string]$Kind, [string]$State, [string]$Message)
    $Progress.Enqueue([pscustomobject]@{ Repository=$Repository; Kind=$Kind; State=$State; Message=$Message; Time=[datetime]::UtcNow })
}

function Invoke-BulkApi {
    param([string]$Method, [string]$Path, [switch]$AllowNotFound)
    $uri = $Path.TrimStart('/')
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $CancellationToken.ThrowIfCancellationRequested()
        if ($Method -eq 'DELETE') {
            # Nur die Startzeitpunkte, nicht den kompletten HTTP-Aufruf serialisieren.
            [System.Threading.Monitor]::Enter($DeleteThrottle.SyncRoot)
            try {
                $nowTicks = [datetime]::UtcNow.Ticks
                $slot = [math]::Max($nowTicks, [long]$DeleteThrottle.NextTicks)
                $DeleteThrottle.NextTicks = [long]($slot + 350 * [timespan]::TicksPerMillisecond)
                $waitMs = [int][math]::Ceiling(($slot - $nowTicks) / [timespan]::TicksPerMillisecond)
            }
            finally { [System.Threading.Monitor]::Exit($DeleteThrottle.SyncRoot) }
            if ($waitMs -gt 0 -and $CancellationToken.WaitHandle.WaitOne($waitMs)) {
                $CancellationToken.ThrowIfCancellationRequested()
            }
        }
        $ApiLimiter.Wait($CancellationToken)
        $request = $null
        $response = $null
        $status = 0
        $body = ''
        $retryAfter = 0
        $networkFailure = $null
        try {
            $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $uri)
            $response = $Client.SendAsync($request, $CancellationToken).GetAwaiter().GetResult()
            $status = [int]$response.StatusCode
            $body = if ($null -ne $response.Content) { $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } else { '' }
            if ($response.IsSuccessStatusCode) {
                if ([string]::IsNullOrWhiteSpace($body)) { return $null }
                return ($body | ConvertFrom-Json)
            }
            if ($AllowNotFound -and $status -eq 404) { return $null }
            if ($null -ne $response.Headers.RetryAfter) {
                if ($null -ne $response.Headers.RetryAfter.Delta) {
                    $retryAfter = [int][math]::Ceiling($response.Headers.RetryAfter.Delta.TotalSeconds)
                }
                elseif ($null -ne $response.Headers.RetryAfter.Date) {
                    $retryAfter = [int][math]::Ceiling(($response.Headers.RetryAfter.Date.UtcDateTime - [datetime]::UtcNow).TotalSeconds)
                }
            }
            if ($status -eq 403 -or $status -eq 429) {
                $remaining = $null
                if ($response.Headers.Contains('X-RateLimit-Remaining')) {
                    $remaining = @($response.Headers.GetValues('X-RateLimit-Remaining'))[0]
                }
                if ($remaining -eq '0' -and $response.Headers.Contains('X-RateLimit-Reset')) {
                    $epoch = [long](@($response.Headers.GetValues('X-RateLimit-Reset'))[0])
                    $resetTime = [DateTimeOffset]::FromUnixTimeSeconds($epoch)
                    $retryAfter = [math]::Max($retryAfter, [int][math]::Ceiling(($resetTime - [DateTimeOffset]::UtcNow).TotalSeconds))
                }
            }
        }
        catch [System.Net.Http.HttpRequestException] {
            $networkFailure = $_.Exception.Message
        }
        finally {
            if ($null -ne $response) { $response.Dispose() }
            if ($null -ne $request) { $request.Dispose() }
            [void]$ApiLimiter.Release()
        }
        if ($networkFailure) {
            if ($attempt -ge 6) { throw "Netzwerkfehler bei $Method $uri`: $networkFailure" }
            $seconds = [math]::Min(120, [math]::Pow(2,$attempt))
            Publish-BulkProgress -Kind 'API' -State 'Retry' -Message "Netzwerkfehler – Retry in $seconds Sekunden"
            if ($CancellationToken.WaitHandle.WaitOne([int]($seconds*1000))) { $CancellationToken.ThrowIfCancellationRequested() }
            continue
        }
        $retryable = ($status -eq 429 -or $status -in @(500,502,503,504) -or
            ($status -eq 403 -and $body -match '(?i)rate limit|secondary rate limit|abuse detection'))
        if (-not $retryable -or $attempt -ge 6) {
            $safeBody = if ($body.Length -gt 400) { $body.Substring(0,400) } else { $body }
            throw "GitHub API $Method $uri`: HTTP $status – $safeBody"
        }
        # GitHubs explizite Primary-Rate-Limit-Reset-Zeit nicht kuenstlich kuerzen.
        $seconds = [math]::Max([math]::Max(1,$retryAfter), [math]::Min(120,[math]::Pow(2,$attempt)))
        Publish-BulkProgress -Kind 'API' -State 'Retry' -Message "$Repository`: HTTP $status – warte $seconds Sekunden"
        if ($CancellationToken.WaitHandle.WaitOne([int]($seconds * 1000))) { $CancellationToken.ThrowIfCancellationRequested() }
    }
}

function Get-BulkPages {
    param([string]$Path, [string]$Collection, [int]$Maximum=20000)
    $items = [System.Collections.Generic.List[object]]::new()
    for ($page = 1; $items.Count -lt $Maximum; $page++) {
        $CancellationToken.ThrowIfCancellationRequested()
        $separator = if ($Path.Contains('?')) { '&' } else { '?' }
        $result = Invoke-BulkApi -Method 'GET' -Path "$Path${separator}per_page=100&page=$page"
        $pageItems = if ([string]::IsNullOrWhiteSpace($Collection)) { @($result) } else {
            if ($null -eq $result) { @() } else { @($result.$Collection) }
        }
        foreach ($entry in $pageItems) {
            if ($null -ne $entry) {
                $items.Add($entry)
                if ($items.Count -ge $Maximum) { break }
            }
        }
        if ($pageItems.Count -lt 100) { break }
        if ($page -ge 1000) { throw 'Pagination-Sicherheitsgrenze erreicht.' }
    }
    return $items.ToArray()
}

function Get-BulkCandidates {
    param([string]$Kind)
    $now = [datetime]::UtcNow
    $protected = 0
    $scanned = 0
    $candidates = @()
    $bytes = [long]0
    switch ($Kind) {
        'Runs' {
            $runs = @(Get-BulkPages -Path "repos/$Repository/actions/runs" -Collection 'workflow_runs' -Maximum ([int]$Options.MaxRuns))
            $completed = @($runs | Where-Object { [string]$_.status -eq 'completed' } | Sort-Object { [datetime]$_.created_at } -Descending)
            $scanned = $runs.Count
            $keep = [System.Collections.Generic.HashSet[string]]::new()
            if ([int]$Options.KeepRuns -gt 0) {
                foreach ($group in @($completed | Group-Object { if ($null -ne $_.workflow_id) { [string]$_.workflow_id } else { [string]$_.name } })) {
                    foreach ($entry in @($group.Group | Select-Object -First ([int]$Options.KeepRuns))) {
                        [void]$keep.Add([string]$entry.id)
                    }
                }
            }
            $protected = $keep.Count
            $cutoff = $now.AddDays(-[int]$Options.RunsAge)
            $candidates = @($completed | Where-Object {
                -not $keep.Contains([string]$_.id) -and
                $null -ne $_.created_at -and
                ([datetime]$_.created_at).ToUniversalTime() -le $cutoff -and
                [string]$_.conclusion -in @('success','failure','cancelled','timed_out','neutral','skipped','stale','action_required','startup_failure')
            } | ForEach-Object { [pscustomobject]@{ Id=[string]$_.id; Tag=''; Size=[long]0 } })
            $note = 'Abgeschlossene Runs; neueste je Workflow geschützt'
        }
        'Caches' {
            $repoDetails = Invoke-BulkApi -Method GET -Path "repos/$Repository"
            $branch = [string]$repoDetails.default_branch
            $caches = @(Get-BulkPages -Path "repos/$Repository/actions/caches" -Collection 'actions_caches')
            $scanned = $caches.Count
            $keep = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($group in @($caches | Group-Object { '{0}|{1}' -f $_.key, $_.ref })) {
                foreach ($entry in @($group.Group | Sort-Object { [datetime]$_.last_accessed_at } -Descending | Select-Object -First ([int]$Options.KeepCaches))) {
                    [void]$keep.Add([string]$entry.id)
                }
            }
            $cutoff = $now.AddDays(-[int]$Options.CachesAge)
            $candidates = @(foreach ($entry in $caches) {
                $isProtected = $keep.Contains([string]$entry.id) -or
                    ([bool]$Options.ProtectDefaultCache -and [string]$entry.ref -eq "refs/heads/$branch")
                if ($isProtected) { $protected++; continue }
                if ($null -eq $entry.last_accessed_at -and $null -eq $entry.created_at) { $protected++; continue }
                $lastAccess = if ($null -ne $entry.last_accessed_at) { [datetime]$entry.last_accessed_at } else { [datetime]$entry.created_at }
                if ($lastAccess.ToUniversalTime() -le $cutoff) {
                    [pscustomobject]@{Id=[string]$entry.id; Tag=''; Size=[long]$entry.size_in_bytes}
                }
            })
            $note = if ($Options.ProtectDefaultCache) { "Default-Branch-Caches geschützt: $branch" } else { 'Default-Branch-Cache-Schutz deaktiviert' }
        }
        'Artifacts' {
            $artifacts = @(Get-BulkPages -Path "repos/$Repository/actions/artifacts" -Collection 'artifacts')
            $scanned = $artifacts.Count
            $keep = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($group in @($artifacts | Group-Object name)) {
                foreach ($entry in @($group.Group | Sort-Object { [datetime]$_.created_at } -Descending | Select-Object -First ([int]$Options.KeepArtifacts))) {
                    [void]$keep.Add([string]$entry.id)
                }
            }
            $cutoff = $now.AddDays(-[int]$Options.ArtifactsAge)
            $candidates = @(foreach ($entry in $artifacts) {
                if ($keep.Contains([string]$entry.id)) { $protected++; continue }
                if ($null -ne $entry.created_at -and ([datetime]$entry.created_at).ToUniversalTime() -le $cutoff) {
                    [pscustomobject]@{Id=[string]$entry.id; Tag=''; Size=[long]$entry.size_in_bytes}
                }
            })
            $note = 'Neueste Artefakte je Name geschützt'
        }
        'Releases' {
            $releases = @(Get-BulkPages -Path "repos/$Repository/releases" -Collection '')
            $scanned = $releases.Count
            $latest = Invoke-BulkApi -Method GET -Path "repos/$Repository/releases/latest" -AllowNotFound
            $latestId = if ($null -eq $latest) { '' } else { [string]$latest.id }
            $keep = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($entry in @($releases | Sort-Object { [datetime]$_.created_at } -Descending | Select-Object -First ([int]$Options.KeepReleases))) {
                [void]$keep.Add([string]$entry.id)
            }
            $cutoff = $now.AddDays(-[int]$Options.ReleasesAge)
            $candidates = @(foreach ($entry in $releases) {
                if (-not ([bool]$entry.prerelease -or [bool]$entry.draft)) { $protected++; continue }
                if ([bool]$entry.immutable -or $keep.Contains([string]$entry.id) -or [string]$entry.id -eq $latestId) { $protected++; continue }
                if ($null -eq $entry.created_at -or ([datetime]$entry.created_at).ToUniversalTime() -gt $cutoff) { $protected++; continue }
                # Tags werden nur bei expliziter separater Opt-in-Option gelöscht.
                $tag = ''
                if ([bool]$Options.DeleteReleaseTags -and -not [string]::IsNullOrWhiteSpace([string]$entry.tag_name)) {
                    $otherUsers = @($releases | Where-Object {
                        [string]$_.tag_name -eq [string]$entry.tag_name -and [string]$_.id -ne [string]$entry.id
                    })
                    if ($otherUsers.Count -eq 0) { $tag = [string]$entry.tag_name }
                }
                [pscustomobject]@{Id=[string]$entry.id; Tag=$tag; Size=[long]0}
            })
            $note = 'Nur Drafts/Prereleases, Latest/Immutable geschützt'
        }
    }
    foreach ($item in $candidates) { $bytes += [long]$item.Size }
    return [pscustomobject]@{
        Repository=$Repository; Kind=$Kind; Scanned=$scanned; Protected=$protected;
        Candidates=@($candidates); Count=@($candidates).Count; Bytes=$bytes; Note=$note; Error=''
    }
}

function Remove-BulkResource {
    param([string]$Kind, [object]$Item)
    switch ($Kind) {
        'Runs'      { $path = "repos/$Repository/actions/runs/$($Item.Id)" }
        'Caches'    { $path = "repos/$Repository/actions/caches/$($Item.Id)" }
        'Artifacts' { $path = "repos/$Repository/actions/artifacts/$($Item.Id)" }
        'Releases'  { $path = "repos/$Repository/releases/$($Item.Id)" }
    }
    [void](Invoke-BulkApi -Method DELETE -Path $path)
    if ($Kind -eq 'Releases' -and -not [string]::IsNullOrWhiteSpace([string]$Item.Tag)) {
        # Tags mit Slashes werden als Git-Ref-Pfad benötigt, nicht mit '/' als URL-Pfad-Kontext kodiert.
        $encoded = (([string]$Item.Tag -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
        [void](Invoke-BulkApi -Method DELETE -Path "repos/$Repository/git/refs/tags/$encoded" -AllowNotFound)
    }
}

$results = [System.Collections.Generic.List[object]]::new()
if ($Mode -eq 'Preview') {
    foreach ($kind in @($Options.Kinds)) {
        $CancellationToken.ThrowIfCancellationRequested()
        Publish-BulkProgress -Kind $kind -State 'Working' -Message 'Kandidaten werden ermittelt'
        try {
            $result = Get-BulkCandidates -Kind $kind
            $results.Add($result)
            Publish-BulkProgress -Kind $kind -State 'Ready' -Message ("{0} Kandidaten, {1} geschützt" -f $result.Count, $result.Protected)
        }
        catch [System.OperationCanceledException] { throw }
        catch {
            $results.Add([pscustomobject]@{ Repository=$Repository; Kind=$kind; Scanned=0; Protected=0; Candidates=@(); Count=0; Bytes=0; Note=''; Error=$_.Exception.Message })
            Publish-BulkProgress -Kind $kind -State 'Error' -Message $_.Exception.Message
        }
    }
}
else {
    foreach ($plan in $Plans) {
        $CancellationToken.ThrowIfCancellationRequested()
        $kind = [string]$plan.Kind
        $succeeded = 0
        $failed = 0
        $skipped = 0
        $errors = [System.Collections.Generic.List[string]]::new()
        Publish-BulkProgress -Kind $kind -State 'Working' -Message 'Schutzregeln werden erneut geprüft'
        try {
            $fresh = Get-BulkCandidates -Kind $kind
            $safeIds = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($entry in @($fresh.Candidates)) { [void]$safeIds.Add([string]$entry.Id) }
            $planned = @($plan.Candidates)
            foreach ($item in $planned) {
                $CancellationToken.ThrowIfCancellationRequested()
                if (-not $safeIds.Contains([string]$item.Id)) { $skipped++; continue }
                $freshItem = @($fresh.Candidates | Where-Object { [string]$_.Id -eq [string]$item.Id } | Select-Object -First 1)
                if ($freshItem.Count -eq 0) { $skipped++; continue }
                try {
                    Remove-BulkResource -Kind $kind -Item $freshItem[0]
                    $succeeded++
                }
                catch [System.OperationCanceledException] { throw }
                catch {
                    $failed++
                    if ($errors.Count -lt 8) { $errors.Add("$($item.Id): $($_.Exception.Message)") }
                }
                if ((($succeeded + $failed) % 10) -eq 0) {
                    Publish-BulkProgress -Kind $kind -State 'Working' -Message ("{0}/{1} abgearbeitet" -f ($succeeded + $failed + $skipped), $planned.Count)
                }
            }
            $results.Add([pscustomobject]@{ Repository=$Repository; Kind=$kind; Deleted=$succeeded; Failed=$failed; Skipped=$skipped; Error=($errors -join ' | ') })
            Publish-BulkProgress -Kind $kind -State 'Finished' -Message ("Gelöscht: {0} / Fehler: {1} / Geschützt oder verschwunden: {2}" -f $succeeded,$failed,$skipped)
        }
        catch [System.OperationCanceledException] { throw }
        catch {
            $results.Add([pscustomobject]@{ Repository=$Repository; Kind=$kind; Deleted=$succeeded; Failed=$failed; Skipped=0; Error=$_.Exception.Message })
            Publish-BulkProgress -Kind $kind -State 'Error' -Message $_.Exception.Message
        }
    }
}
return $results.ToArray()
