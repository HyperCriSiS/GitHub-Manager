$script:SetupControls = @{}
$script:SetupGroups = @()
$script:SetupDefinitions = @(
    [ordered]@{ Key='Repository.Issues'; Category='Repository'; Label='Issues'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Issue-Tracker aktivieren oder deaktivieren.' },
    [ordered]@{ Key='Repository.Projects'; Category='Repository'; Label='Projects'; Type='Bool'; DefaultApply=$true; DefaultValue=$false; Help='GitHub Projects für das Repository.' },
    [ordered]@{ Key='Repository.Wiki'; Category='Repository'; Label='Wiki'; Type='Bool'; DefaultApply=$true; DefaultValue=$false; Help='Repository-Wiki aktivieren.' },
    [ordered]@{ Key='Repository.Discussions'; Category='Repository'; Label='Discussions'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='GitHub Discussions aktivieren.' },
    [ordered]@{ Key='Repository.PullRequests'; Category='Repository'; Label='Pull Requests'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Pull Requests für das Repository erlauben.' },
    [ordered]@{ Key='Repository.PRPolicy'; Category='Repository'; Label='Wer darf PRs erstellen'; Type='Choice'; Values=@('all','collaborators_only'); DefaultApply=$false; DefaultValue='all'; Help='Optional auf Collaborators beschränken.' },
    [ordered]@{ Key='Repository.IsTemplate'; Category='Repository'; Label='Als GitHub-Template-Repo markieren'; Type='Bool'; DefaultApply=$false; DefaultValue=$false; Help='Das Repository selbst als GitHub-Template verfügbar machen.' },

    [ordered]@{ Key='Merge.Squash'; Category='Merge & Branches'; Label='Squash-Merge'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Squash-Merges erlauben.' },
    [ordered]@{ Key='Merge.MergeCommit'; Category='Merge & Branches'; Label='Merge-Commit'; Type='Bool'; DefaultApply=$true; DefaultValue=$false; Help='Klassische Merge-Commits erlauben.' },
    [ordered]@{ Key='Merge.Rebase'; Category='Merge & Branches'; Label='Rebase-Merge'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Rebase-Merges erlauben.' },
    [ordered]@{ Key='Merge.AutoMerge'; Category='Merge & Branches'; Label='Auto-Merge'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='GitHub Auto-Merge für PRs erlauben.' },
    [ordered]@{ Key='Merge.DeleteBranch'; Category='Merge & Branches'; Label='Branch nach Merge löschen'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Head-Branches nach erfolgreichem Merge automatisch entfernen.' },
    [ordered]@{ Key='Merge.UpdateBranch'; Category='Merge & Branches'; Label='PR-Branch aktualisieren erlauben'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Update-Branch-Schaltfläche erlauben.' },
    [ordered]@{ Key='Merge.WebSignoff'; Category='Merge & Branches'; Label='Web-Commit Sign-off verlangen'; Type='Bool'; DefaultApply=$false; DefaultValue=$false; Help='DCO-Sign-off für Web-Commits verlangen.' },
    [ordered]@{ Key='Merge.SquashTitle'; Category='Merge & Branches'; Label='Squash-Titel'; Type='Choice'; Values=@('PR_TITLE','COMMIT_OR_PR_TITLE'); DefaultApply=$false; DefaultValue='PR_TITLE'; Help='Standardtitel des Squash-Commits.' },
    [ordered]@{ Key='Merge.SquashMessage'; Category='Merge & Branches'; Label='Squash-Nachricht'; Type='Choice'; Values=@('PR_BODY','COMMIT_MESSAGES','BLANK'); DefaultApply=$false; DefaultValue='PR_BODY'; Help='Standardtext des Squash-Commits.' },

    [ordered]@{ Key='Security.DependabotAlerts'; Category='Security & Dependabot'; Label='Dependabot Alerts / Dependency Graph'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Vulnerability Alerts einschalten; aktiviert auch den Dependency Graph.' },
    [ordered]@{ Key='Security.DependabotSecurityUpdates'; Category='Security & Dependabot'; Label='Dependabot Security Updates'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Automatische Security-Update-PRs einschalten.' },
    [ordered]@{ Key='Security.DependabotVersionUpdates'; Category='Security & Dependabot'; Label='Dependabot Version Updates'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='.github/dependabot.yml automatisch erzeugen bzw. aktualisieren.' },
    [ordered]@{ Key='Security.DependabotSchedule'; Category='Security & Dependabot'; Label='Dependabot Intervall'; Type='Choice'; Values=@('daily','weekly','monthly'); DefaultApply=$true; DefaultValue='weekly'; Help='Zeitplan für erkannte Package-Ecosystems.' },
    [ordered]@{ Key='Security.DependabotPRLimit'; Category='Security & Dependabot'; Label='Max. offene Dependabot-PRs'; Type='Number'; Minimum=1; Maximum=100; DefaultApply=$true; DefaultValue=10; Help='Begrenzt parallele Version-Update-PRs je Ecosystem.' },
    [ordered]@{ Key='Security.DependabotEcosystems'; Category='Security & Dependabot'; Label='Dependabot Ecosystems'; Type='Text'; DefaultApply=$true; DefaultValue='auto'; Help='auto oder z. B. npm,github-actions,pip. Auto erkennt übliche Manifeste rekursiv und berücksichtigt Monorepo-Unterverzeichnisse.' },
    [ordered]@{ Key='Security.SecretScanning'; Category='Security & Dependabot'; Label='Secret Scanning'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Secret Scanning aktivieren, sofern für Repo/Plan verfügbar.' },
    [ordered]@{ Key='Security.PushProtection'; Category='Security & Dependabot'; Label='Secret Push Protection'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Pushes mit erkannten Secrets blockieren.' },
    [ordered]@{ Key='Security.SecretAi'; Category='Security & Dependabot'; Label='Secret Scanning AI Detection'; Type='Bool'; DefaultApply=$false; DefaultValue=$false; Help='Tarif-/Feature-abhängig; standardmäßig nicht verändert.' },
    [ordered]@{ Key='Security.SecretNonProvider'; Category='Security & Dependabot'; Label='Non-Provider Patterns'; Type='Bool'; DefaultApply=$false; DefaultValue=$false; Help='Zusätzliche Secret-Muster; tarifabhängig.' },
    [ordered]@{ Key='Security.CodeSecurity'; Category='Security & Dependabot'; Label='GitHub Code Security'; Type='Bool'; DefaultApply=$false; DefaultValue=$false; Help='Kann plan-/kostenabhängig sein. Nur bewusst aktivieren.' },
    [ordered]@{ Key='Security.PrivateVulnerability'; Category='Security & Dependabot'; Label='Private Vulnerability Reporting'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Private Meldung von Sicherheitslücken erlauben, sofern unterstützt.' },
    [ordered]@{ Key='Security.ImmutableReleases'; Category='Security & Dependabot'; Label='Immutable Releases'; Type='Bool'; DefaultApply=$false; DefaultValue=$false; Help='Nach Veröffentlichung Tags und Assets eines Releases unveränderbar machen.' },

    [ordered]@{ Key='Actions.Enabled'; Category='GitHub Actions'; Label='GitHub Actions'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Actions im Repository aktivieren.' },
    [ordered]@{ Key='Actions.Allowed'; Category='GitHub Actions'; Label='Erlaubte Actions'; Type='Choice'; Values=@('all','local_only'); DefaultApply=$true; DefaultValue='all'; Help='Alle Actions oder nur lokale Actions/Workflows zulassen.' },
    [ordered]@{ Key='Actions.ShaPinning'; Category='GitHub Actions'; Label='Actions auf vollständige SHA pinnen'; Type='Bool'; DefaultApply=$false; DefaultValue=$false; Help='Erhöht Supply-Chain-Sicherheit, erfordert aber gepflegte vollständige SHAs.' },
    [ordered]@{ Key='Actions.TokenPermission'; Category='GitHub Actions'; Label='GITHUB_TOKEN Standardrechte'; Type='Choice'; Values=@('read','write'); DefaultApply=$true; DefaultValue='read'; Help='Read ist die sicherere Grundeinstellung.' },
    [ordered]@{ Key='Actions.ApprovePR'; Category='GitHub Actions'; Label='Actions dürfen PRs genehmigen'; Type='Bool'; DefaultApply=$true; DefaultValue=$false; Help='Normalerweise aus Sicherheitsgründen deaktiviert lassen.' },
    [ordered]@{ Key='Actions.Retention'; Category='GitHub Actions'; Label='Artefakte & Logs behalten'; Type='Number'; Minimum=1; Maximum=400; DefaultApply=$true; DefaultValue=30; Help='Aufbewahrungszeit in Tagen für neu erzeugte Artefakte und Logs.' },

    [ordered]@{ Key='Rules.Enabled'; Category='Default-Branch Ruleset'; Label='Managed Ruleset'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Ein vom GitHub Manager verwaltetes Ruleset für den Default Branch anwenden.' },
    [ordered]@{ Key='Rules.Name'; Category='Default-Branch Ruleset'; Label='Ruleset-Name'; Type='Text'; DefaultApply=$true; DefaultValue='GitHub Manager - Default Branch'; Help='Vorhandenes Ruleset mit exakt diesem Namen wird aktualisiert.' },
    [ordered]@{ Key='Rules.Enforcement'; Category='Default-Branch Ruleset'; Label='Durchsetzung'; Type='Choice'; Values=@('active','disabled','evaluate'); DefaultApply=$true; DefaultValue='active'; Help='evaluate ist nur bei passenden Enterprise-Plänen verfügbar.' },
    [ordered]@{ Key='Rules.RequirePR'; Category='Default-Branch Ruleset'; Label='Pull Request vor Merge verlangen'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Direkte Änderungen am Default Branch werden verhindert.' },
    [ordered]@{ Key='Rules.Approvals'; Category='Default-Branch Ruleset'; Label='Benötigte Freigaben'; Type='Number'; Minimum=0; Maximum=10; DefaultApply=$true; DefaultValue=0; Help='0 verlangt weiterhin einen PR, aber keine zusätzliche Freigabe.' },
    [ordered]@{ Key='Rules.DismissStale'; Category='Default-Branch Ruleset'; Label='Alte Freigaben bei Push verwerfen'; Type='Bool'; DefaultApply=$true; DefaultValue=$false; Help='Strenger Schutz gegen nachträglich geänderte PRs.' },
    [ordered]@{ Key='Rules.LastPushApproval'; Category='Default-Branch Ruleset'; Label='Letzten Push separat freigeben'; Type='Bool'; DefaultApply=$true; DefaultValue=$false; Help='Letzter Push muss von einer anderen Person genehmigt werden.' },
    [ordered]@{ Key='Rules.CodeOwners'; Category='Default-Branch Ruleset'; Label='CODEOWNERS-Freigabe'; Type='Bool'; DefaultApply=$true; DefaultValue=$false; Help='Nur sinnvoll, wenn eine CODEOWNERS-Datei gepflegt wird.' },
    [ordered]@{ Key='Rules.ResolveThreads'; Category='Default-Branch Ruleset'; Label='Review-Threads auflösen'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Alle Review-Konversationen müssen vor Merge erledigt sein.' },
    [ordered]@{ Key='Rules.LinearHistory'; Category='Default-Branch Ruleset'; Label='Lineare Historie'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Verhindert Merge-Commits auf dem geschützten Branch.' },
    [ordered]@{ Key='Rules.SignedCommits'; Category='Default-Branch Ruleset'; Label='Signierte Commits verlangen'; Type='Bool'; DefaultApply=$false; DefaultValue=$false; Help='Nur aktivieren, wenn der Workflow signierte Commits zuverlässig unterstützt.' },
    [ordered]@{ Key='Rules.BlockForcePush'; Category='Default-Branch Ruleset'; Label='Force-Push blockieren'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='non_fast_forward-Regel.' },
    [ordered]@{ Key='Rules.BlockDeletion'; Category='Default-Branch Ruleset'; Label='Branch-Löschung blockieren'; Type='Bool'; DefaultApply=$true; DefaultValue=$true; Help='Default Branch kann nicht gelöscht werden.' },
    [ordered]@{ Key='Rules.StatusChecks'; Category='Default-Branch Ruleset'; Label='Erforderliche Status Checks'; Type='Text'; DefaultApply=$false; DefaultValue=''; Help='Kommagetrennte exakte Check-Namen, z. B. build,test,lint.' }
)


$script:TemplateScopeValues = @(
    'Kombiniert',
    'Repository',
    'Merge & Branches',
    'Security & Dependabot',
    'GitHub Actions',
    'Default-Branch Ruleset',
    'Release',
    'Cleanup',
    'Content / New Repo'
)

function Get-ObjectPropertyValue {
    param($Object,[string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    return $p.Value
}

function New-BuiltinTemplate {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$Description,
        [hashtable]$Settings = @{},
        [hashtable]$Extra = @{},
        [string[]]$Extends = @()
    )

    $wrappedSettings = [ordered]@{}
    foreach ($key in $Settings.Keys) {
        $wrappedSettings[$key] = [ordered]@{ Apply=$true; Value=$Settings[$key] }
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = 2
        Name          = $Name
        Scope         = $Scope
        Description   = $Description
        BuiltIn       = $true
        Extends       = @($Extends)
        Settings      = $wrappedSettings
        Extra         = $Extra
    }
}

function Get-BuiltinTemplates {
    $templates = New-Object System.Collections.ArrayList
    function Add-T($t) { [void]$templates.Add($t) }

    # Bereichsvorlagen. Profile unten werden aus diesen Bausteinen zusammengesetzt.
    Add-T (New-BuiltinTemplate -Name 'Bereich - Repository Public OSS' -Scope 'Repository' -Description 'Öffentliches OSS-Repository: Issues/PRs an, wenig genutzte Zusatzflächen aus.' -Settings @{
        'Repository.Issues'=$true; 'Repository.Projects'=$false; 'Repository.Wiki'=$false; 'Repository.Discussions'=$false; 'Repository.PullRequests'=$true; 'Repository.IsTemplate'=$false
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Repository Private' -Scope 'Repository' -Description 'Private Entwicklungs-Repositories mit Issues und PRs, ohne Wiki/Discussions.' -Settings @{
        'Repository.Issues'=$true; 'Repository.Projects'=$false; 'Repository.Wiki'=$false; 'Repository.Discussions'=$false; 'Repository.PullRequests'=$true; 'Repository.IsTemplate'=$false
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Merge Solo Maintainer' -Scope 'Merge & Branches' -Description 'Saubere lineare Historie für einen primären Maintainer ohne unnötige Review-Hürden.' -Settings @{
        'Merge.Squash'=$true; 'Merge.MergeCommit'=$false; 'Merge.Rebase'=$true; 'Merge.AutoMerge'=$true; 'Merge.DeleteBranch'=$true; 'Merge.UpdateBranch'=$true; 'Merge.WebSignoff'=$false; 'Merge.SquashTitle'='PR_TITLE'; 'Merge.SquashMessage'='PR_BODY'
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Security Standard' -Scope 'Security & Dependabot' -Description 'Dependency- und Secret-Schutz ohne kosten-/tarifabhängige Features zu erzwingen.' -Settings @{
        'Security.DependabotAlerts'=$true; 'Security.DependabotSecurityUpdates'=$true; 'Security.SecretScanning'=$true; 'Security.PushProtection'=$true; 'Security.PrivateVulnerability'=$true
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Security High Assurance' -Scope 'Security & Dependabot' -Description 'Stärkeres Sicherheitsprofil für Passwort-, Infrastruktur- und andere sensible Projekte; kostenabhängige Features bleiben bewusst unangetastet.' -Settings @{
        'Security.DependabotAlerts'=$true; 'Security.DependabotSecurityUpdates'=$true; 'Security.SecretScanning'=$true; 'Security.PushProtection'=$true; 'Security.PrivateVulnerability'=$true
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Dependabot Standard' -Scope 'Security & Dependabot' -Description 'Wöchentliche Versionsupdates mit begrenzter PR-Flut; Ecosystems/Verzeichnisse werden automatisch erkannt.' -Settings @{
        'Security.DependabotVersionUpdates'=$true; 'Security.DependabotSchedule'='weekly'; 'Security.DependabotPRLimit'=5; 'Security.DependabotEcosystems'='auto'
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Actions Secure' -Scope 'GitHub Actions' -Description 'Actions aktiviert, GITHUB_TOKEN standardmäßig read-only, keine PR-Genehmigungen durch Actions.' -Settings @{
        'Actions.Enabled'=$true; 'Actions.Allowed'='all'; 'Actions.TokenPermission'='read'; 'Actions.ApprovePR'=$false; 'Actions.Retention'=30
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Actions Strict SHA' -Scope 'GitHub Actions' -Description 'Wie Actions Secure, zusätzlich vollständige SHA-Pins. Erst verwenden, wenn alle externen Actions gepinnt sind.' -Extends @('Bereich - Actions Secure') -Settings @{
        'Actions.ShaPinning'=$true
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Ruleset Solo Maintainer' -Scope 'Default-Branch Ruleset' -Description 'PR-Pflicht ohne Fremd-Approval, lineare Historie, kein Force-Push oder Löschen des Default Branch.' -Settings @{
        'Rules.Enabled'=$true; 'Rules.Name'='GitHub Manager - Default Branch'; 'Rules.Enforcement'='active'; 'Rules.RequirePR'=$true; 'Rules.Approvals'=0; 'Rules.DismissStale'=$false; 'Rules.LastPushApproval'=$false; 'Rules.CodeOwners'=$false; 'Rules.ResolveThreads'=$true; 'Rules.LinearHistory'=$true; 'Rules.SignedCommits'=$false; 'Rules.BlockForcePush'=$true; 'Rules.BlockDeletion'=$true
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Ruleset Research' -Scope 'Default-Branch Ruleset' -Description 'Leichter Schutz für Research/Mirrors: kein Force-Push/Löschen, aber keine PR-Pflicht.' -Settings @{
        'Rules.Enabled'=$true; 'Rules.Name'='GitHub Manager - Default Branch'; 'Rules.Enforcement'='active'; 'Rules.RequirePR'=$false; 'Rules.LinearHistory'=$false; 'Rules.BlockForcePush'=$true; 'Rules.BlockDeletion'=$true
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Ruleset Mirror' -Scope 'Default-Branch Ruleset' -Description 'Deaktiviert das vom Manager verwaltete Ruleset, damit Upstream-Synchronisation nicht blockiert wird.' -Settings @{
        'Rules.Enabled'=$false; 'Rules.Name'='GitHub Manager - Default Branch'
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Release SemVer' -Scope 'Release' -Description 'SemVer-orientierte Releases mit Auto-Notes und Schutz vor leeren Releases.' -Extra @{
        Release=[ordered]@{ GenerateNotes=$true; FailNoCommits=$true; VerifyTag=$false; Draft=$false; Prerelease=$false; Latest='Automatisch'; VersionPaths="package.json`nmanifest.json" }
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Cleanup Standard' -Scope 'Cleanup' -Description 'Konservatives CI-Cleanup: genug Diagnosehistorie, aber kein unbegrenztes Wachstum.' -Extra @{
        Cleanup=[ordered]@{ KeepRuns=10; KeepPerWorkflow=$true; MinimumRunAge=14; RunsLimit=1000; CacheAge=14; ProtectDefaultCache=$true; CacheLimit=1000; ArtifactAge=30; KeepArtifacts=1; OnlyExpiredArtifacts=$false }
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Cleanup CI Heavy' -Scope 'Cleanup' -Description 'Für Repositories mit sehr vielen Runs/Artefakten; kürzere Historie bei weiterhin sicherem Mindestalter.' -Extra @{
        Cleanup=[ordered]@{ KeepRuns=7; KeepPerWorkflow=$true; MinimumRunAge=10; RunsLimit=1000; CacheAge=10; ProtectDefaultCache=$true; CacheLimit=1000; ArtifactAge=21; KeepArtifacts=1; OnlyExpiredArtifacts=$false }
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Content Public OSS' -Scope 'Content / New Repo' -Description 'Startwerte für ein öffentliches Repository. Lizenz und .gitignore bleiben projektabhängig.' -Extra @{
        Content=[ordered]@{ Visibility='public'; Readme=$true; Gitignore=''; License=''; SourceTemplate=''; ApplySettings=$true }
    })
    Add-T (New-BuiltinTemplate -Name 'Bereich - Content Private' -Scope 'Content / New Repo' -Description 'Startwerte für private Entwicklungs-/Research-Repositories.' -Extra @{
        Content=[ordered]@{ Visibility='private'; Readme=$true; Gitignore=''; License=''; SourceTemplate=''; ApplySettings=$true }
    })

    # Kombinierte Profile – nur Referenzen auf Bereichsvorlagen, keine duplizierten Regeln.
    Add-T (New-BuiltinTemplate -Name 'Profil - Public Browser Extension' -Scope 'Kombiniert' -Description 'Empfohlen für Sprachverstand und vergleichbare WebExtensions.' -Extends @('Bereich - Repository Public OSS','Bereich - Merge Solo Maintainer','Bereich - Security Standard','Bereich - Dependabot Standard','Bereich - Actions Secure','Bereich - Ruleset Solo Maintainer','Bereich - Release SemVer','Bereich - Cleanup CI Heavy','Bereich - Content Public OSS'))
    Add-T (New-BuiltinTemplate -Name 'Profil - Private Application' -Scope 'Kombiniert' -Description 'Standard für private Android-/Desktop-Anwendungen.' -Extends @('Bereich - Repository Private','Bereich - Merge Solo Maintainer','Bereich - Security Standard','Bereich - Dependabot Standard','Bereich - Actions Secure','Bereich - Ruleset Solo Maintainer','Bereich - Release SemVer','Bereich - Cleanup Standard','Bereich - Content Private'))
    Add-T (New-BuiltinTemplate -Name 'Profil - Private High Assurance' -Scope 'Kombiniert' -Description 'Für besonders sensible Apps wie Passwortmanager. Stärkeres Sicherheitsprofil; SHA-Pinning und irreversible Release-Härtung bleiben bewusst separat.' -Extends @('Bereich - Repository Private','Bereich - Merge Solo Maintainer','Bereich - Security High Assurance','Bereich - Dependabot Standard','Bereich - Actions Secure','Bereich - Ruleset Solo Maintainer','Bereich - Release SemVer','Bereich - Cleanup Standard','Bereich - Content Private'))
    Add-T (New-BuiltinTemplate -Name 'Profil - Private Research' -Scope 'Kombiniert' -Description 'Research/Analyse: Security-Basics und leichter Branchschutz, aber keine automatische Dependency-PR-Flut.' -Extends @('Bereich - Repository Private','Bereich - Merge Solo Maintainer','Bereich - Security Standard','Bereich - Actions Secure','Bereich - Ruleset Research','Bereich - Cleanup Standard','Bereich - Content Private'))
    Add-T (New-BuiltinTemplate -Name 'Profil - Private Engineering Framework' -Scope 'Kombiniert' -Description 'Private Engineering-/Dokumentations-Frameworks: sichere Repo- und Actions-Defaults ohne erzwungene Dependency- oder Release-Automatik.' -Extends @('Bereich - Repository Private','Bereich - Merge Solo Maintainer','Bereich - Security Standard','Bereich - Actions Secure','Bereich - Ruleset Solo Maintainer','Bereich - Cleanup Standard','Bereich - Content Private'))
    Add-T (New-BuiltinTemplate -Name 'Profil - Public Library Framework' -Scope 'Kombiniert' -Description 'Öffentliche Bibliotheken/Frameworks mit CI, Dependabot und SemVer-Releases.' -Extends @('Bereich - Repository Public OSS','Bereich - Merge Solo Maintainer','Bereich - Security Standard','Bereich - Dependabot Standard','Bereich - Actions Secure','Bereich - Ruleset Solo Maintainer','Bereich - Release SemVer','Bereich - Cleanup Standard','Bereich - Content Public OSS'))
    Add-T (New-BuiltinTemplate -Name 'Profil - Public Data Rules Catalog' -Scope 'Kombiniert' -Description 'Regel-/Datenkataloge: PR-geschützt, Security-Basics, keine erzwungenen Dependabot-Version-PRs.' -Extends @('Bereich - Repository Public OSS','Bereich - Merge Solo Maintainer','Bereich - Security Standard','Bereich - Actions Secure','Bereich - Ruleset Solo Maintainer','Bereich - Release SemVer','Bereich - Cleanup Standard','Bereich - Content Public OSS'))
    Add-T (New-BuiltinTemplate -Name 'Profil - Public Home Assistant Add-on' -Scope 'Kombiniert' -Description 'Home-Assistant-Add-on-Repositories, einschließlich verschachtelter Dockerfile-Erkennung für Dependabot.' -Extends @('Bereich - Repository Public OSS','Bereich - Merge Solo Maintainer','Bereich - Security Standard','Bereich - Dependabot Standard','Bereich - Actions Secure','Bereich - Ruleset Solo Maintainer','Bereich - Release SemVer','Bereich - Cleanup Standard','Bereich - Content Public OSS'))
    Add-T (New-BuiltinTemplate -Name 'Profil - Private Infrastructure' -Scope 'Kombiniert' -Description 'Private Deployment-/Container-Repositories mit starkem Secret-Schutz und Dependency-Updates.' -Extends @('Bereich - Repository Private','Bereich - Merge Solo Maintainer','Bereich - Security High Assurance','Bereich - Dependabot Standard','Bereich - Actions Secure','Bereich - Ruleset Solo Maintainer','Bereich - Cleanup Standard','Bereich - Content Private'))
    Add-T (New-BuiltinTemplate -Name 'Profil - Public Utility Scripts' -Scope 'Kombiniert' -Description 'Kleine öffentliche Tools/Skripte: solide Defaults ohne unnötige Dependency-PR-, Release- oder Governance-Last.' -Extends @('Bereich - Repository Public OSS','Bereich - Merge Solo Maintainer','Bereich - Security Standard','Bereich - Actions Secure','Bereich - Ruleset Solo Maintainer','Bereich - Cleanup Standard','Bereich - Content Public OSS'))
    Add-T (New-BuiltinTemplate -Name 'Profil - Upstream Mirror' -Scope 'Kombiniert' -Description 'Mirrors/Issue-Tracker: Upstream-Sync nicht durch Rulesets/Dependency-PRs behindern.' -Extends @('Bereich - Repository Private','Bereich - Merge Solo Maintainer','Bereich - Security Standard','Bereich - Actions Secure','Bereich - Ruleset Mirror','Bereich - Cleanup Standard','Bereich - Content Private'))

    return @($templates)
}

function Get-SetupDefinition { param([string]$Key) return @($script:SetupDefinitions | Where-Object { $_.Key -eq $Key })[0] }

function Get-SetupControlValue {
    param([string]$Key)
    $entry = $script:SetupControls[$Key]
    if ($null -eq $entry) { return $null }
    switch ($entry.Definition.Type) {
        'Bool' { return [bool]$entry.Value.Checked }
        'Number' { return [int]$entry.Value.Value }
        'Choice' { return [string]$entry.Value.SelectedItem }
        'Text' { return [string]$entry.Value.Text }
    }
}

function Test-SetupApply {
    param([string]$Key)
    $entry = $script:SetupControls[$Key]
    return ($null -ne $entry -and [bool]$entry.Apply.Checked)
}

function Set-AllSetupApply {
    param([bool]$Value)
    foreach ($entry in $script:SetupControls.Values) {
        if ($null -ne $entry -and $null -ne $entry.Apply) { $entry.Apply.Checked = $Value }
    }
}

function New-SetupCategoryGroup {
    param([Parameter(Mandatory)][string]$Category)

    $definitions = @($script:SetupDefinitions | Where-Object { $_.Category -eq $Category })
    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = $Category
    $group.Width = 1160
    $group.Height = 34 + ($definitions.Count * 35)
    $group.Margin = New-Object System.Windows.Forms.Padding(6)

    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.Dock = 'Fill'
    $table.Padding = New-Object System.Windows.Forms.Padding(8,6,8,8)
    $table.ColumnCount = 4
    $table.RowCount = $definitions.Count + 1
    [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 86)))
    [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 260)))
    [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 220)))
    [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $group.Controls.Add($table)

    foreach ($header in @(@('Anwenden',0),@('Einstellung',1),@('Wert',2),@('Hinweis',3))) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $header[0]
        $label.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
        $label.Dock = 'Fill'
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $table.Controls.Add($label,[int]$header[1],0)
    }

    $row = 1
    foreach ($definition in $definitions) {
        [void]$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
        $apply = New-Object System.Windows.Forms.CheckBox
        $apply.Text = 'Ja'
        $apply.Checked = [bool]$definition.DefaultApply
        $apply.Dock = 'Fill'
        $table.Controls.Add($apply,0,$row)

        $name = New-Object System.Windows.Forms.Label
        $name.Text = [string]$definition.Label
        $name.Dock = 'Fill'
        $name.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $name.AutoEllipsis = $true
        $table.Controls.Add($name,1,$row)

        $value = $null
        switch ($definition.Type) {
            'Bool' {
                $value = New-Object System.Windows.Forms.CheckBox
                $value.Text = if ([bool]$definition.DefaultValue) { 'Ein' } else { 'Aus' }
                $value.Checked = [bool]$definition.DefaultValue
                $value.Dock = 'Fill'
                $value.Add_CheckedChanged({ param($sender,$e) $sender.Text = if ($sender.Checked) { 'Ein' } else { 'Aus' } })
            }
            'Choice' {
                $value = New-Object System.Windows.Forms.ComboBox
                $value.DropDownStyle = 'DropDownList'
                $value.Dock = 'Fill'
                foreach ($item in $definition.Values) { [void]$value.Items.Add([string]$item) }
                $value.SelectedItem = [string]$definition.DefaultValue
                if ($value.SelectedIndex -lt 0 -and $value.Items.Count -gt 0) { $value.SelectedIndex = 0 }
            }
            'Number' {
                $value = New-Object System.Windows.Forms.NumericUpDown
                $value.Minimum = [decimal]$definition.Minimum
                $value.Maximum = [decimal]$definition.Maximum
                $value.Value = [decimal]$definition.DefaultValue
                $value.Dock = 'Fill'
            }
            'Text' {
                $value = New-Object System.Windows.Forms.TextBox
                $value.Text = [string]$definition.DefaultValue
                $value.Dock = 'Fill'
            }
        }
        $value.Margin = New-Object System.Windows.Forms.Padding(3,4,8,4)
        $table.Controls.Add($value,2,$row)

        $help = New-Object System.Windows.Forms.Label
        $help.Text = [string]$definition.Help
        $help.Dock = 'Fill'
        $help.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $help.AutoEllipsis = $true
        $table.Controls.Add($help,3,$row)

        $script:SetupControls[$definition.Key] = [pscustomobject]@{ Apply=$apply; Value=$value; Definition=$definition }
        $row++
    }

    $script:SetupGroups += $group
    return $group
}

function Update-SetupGroupWidths {
    if ($null -eq $setupSettingsFlow) { return }
    $width = [Math]::Max(780, $setupSettingsFlow.ClientSize.Width - 28)
    foreach ($group in $script:SetupGroups) { $group.Width = $width }
}

function New-DefaultSetupTemplate {
    return @(Get-BuiltinTemplates | Where-Object { $_.Name -eq 'Profil - Private Application' })[0]
}

function Save-TemplateStore {
    if (-not (Test-Path -LiteralPath $script:AppDataPath)) { [void](New-Item -ItemType Directory -Path $script:AppDataPath -Force) }
    # Built-ins werden aus dem Programm geladen und nicht in die Benutzerdaten dupliziert.
    $custom = @($script:State.Templates | Where-Object { -not [bool](Get-ObjectPropertyValue $_ 'BuiltIn' $false) })
    $store = [ordered]@{ SchemaVersion=2; Templates=$custom }
    $json = $store | ConvertTo-Json -Depth 30
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($script:TemplatesPath,$json,$utf8NoBom)
}

function Refresh-TemplateCombo {
    $selected = [string]$templateComboBox.SelectedItem
    $templateComboBox.Items.Clear()
    foreach ($template in @($script:State.Templates | Sort-Object @{Expression={ if ([bool](Get-ObjectPropertyValue $_ 'BuiltIn' $false)) {0}else{1} }}, Scope, Name)) {
        [void]$templateComboBox.Items.Add([string]$template.Name)
    }
    if (-not [string]::IsNullOrWhiteSpace($selected) -and $templateComboBox.Items.Contains($selected)) { $templateComboBox.SelectedItem = $selected }
    elseif ($templateComboBox.Items.Count -gt 0) { $templateComboBox.SelectedIndex = 0 }
}

function Initialize-TemplateSystem {
    try {
        $custom = @()
        if (Test-Path -LiteralPath $script:TemplatesPath) {
            $raw = Get-Content -LiteralPath $script:TemplatesPath -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = ConvertFrom-Json -InputObject $raw
                $schema = Get-ObjectPropertyValue $parsed 'SchemaVersion' 1
                if ([int]$schema -ge 2) { $custom = @(Get-ObjectPropertyValue $parsed 'Templates' @()) }
                else { $custom = @($parsed) }
            }
        }
        foreach ($t in $custom) {
            if ($null -eq $t.PSObject.Properties['SchemaVersion']) { Add-Member -InputObject $t -NotePropertyName SchemaVersion -NotePropertyValue 1 }
            if ($null -eq $t.PSObject.Properties['Scope']) { Add-Member -InputObject $t -NotePropertyName Scope -NotePropertyValue 'Kombiniert' }
            if ($null -eq $t.PSObject.Properties['Description']) { Add-Member -InputObject $t -NotePropertyName Description -NotePropertyValue 'Aus einer früheren GitHub-Manager-Version übernommen.' }
            if ($null -eq $t.PSObject.Properties['BuiltIn']) { Add-Member -InputObject $t -NotePropertyName BuiltIn -NotePropertyValue $false }
            if ($null -eq $t.PSObject.Properties['Extends']) { Add-Member -InputObject $t -NotePropertyName Extends -NotePropertyValue @() }
            if ($null -eq $t.PSObject.Properties['Extra']) { Add-Member -InputObject $t -NotePropertyName Extra -NotePropertyValue ([pscustomobject]@{}) }
        }
        $script:State.Templates = @((Get-BuiltinTemplates) + $custom)

        $templateScopeComboBox.Items.Clear()
        foreach ($scope in $script:TemplateScopeValues) { [void]$templateScopeComboBox.Items.Add($scope) }
        $templateScopeComboBox.SelectedItem = 'Kombiniert'

        Refresh-TemplateCombo
        if ($templateComboBox.Items.Contains('Profil - Private Application')) { $templateComboBox.SelectedItem = 'Profil - Private Application' }
        Load-SelectedTemplate
    }
    catch {
        Write-Log -Level ERROR -Message "Templates konnten nicht geladen werden: $($_.Exception.Message)"
        $script:State.Templates = @(Get-BuiltinTemplates)
        Refresh-TemplateCombo
        Load-SelectedTemplate
    }
}

function Get-TemplateByName {
    param([string]$Name)
    return @($script:State.Templates | Where-Object { [string]$_.Name -eq $Name }) | Select-Object -First 1
}

function Merge-TemplateLayer {
    param([System.Collections.IDictionary]$TargetSettings,[System.Collections.IDictionary]$TargetExtra,$Layer)
    $settings = Get-ObjectPropertyValue $Layer 'Settings' $null
    if ($null -ne $settings) {
        if ($settings -is [System.Collections.IDictionary]) { foreach ($k in $settings.Keys) { $TargetSettings[$k] = $settings[$k] } }
        else { foreach ($p in $settings.PSObject.Properties) { $TargetSettings[$p.Name] = $p.Value } }
    }
    $extra = Get-ObjectPropertyValue $Layer 'Extra' $null
    if ($null -ne $extra) {
        foreach ($area in @('Release','Cleanup','Content')) {
            $areaValue = Get-ObjectPropertyValue $extra $area $null
            if ($null -eq $areaValue) { continue }
            if (-not $TargetExtra.Contains($area)) { $TargetExtra[$area] = [ordered]@{} }
            if ($areaValue -is [System.Collections.IDictionary]) {
                foreach ($k in $areaValue.Keys) { $TargetExtra[$area][$k] = $areaValue[$k] }
            }
            else {
                foreach ($p in $areaValue.PSObject.Properties) { $TargetExtra[$area][$p.Name] = $p.Value }
            }
        }
    }
}

function Get-EffectiveTemplate {
    param([Parameter(Mandatory)]$Template,[string[]]$Stack=@())
    $name = [string](Get-ObjectPropertyValue $Template 'Name' '')
    if ($Stack -contains $name) { throw "Template-Vererbungszyklus erkannt: $($Stack -join ' -> ') -> $name" }
    $settings = [ordered]@{}
    $extra = [ordered]@{}
    $nextStack = @($Stack + $name)
    foreach ($baseName in @(Get-ObjectPropertyValue $Template 'Extends' @())) {
        $base = Get-TemplateByName -Name ([string]$baseName)
        if ($null -eq $base) { throw "Basis-Template '$baseName' für '$name' wurde nicht gefunden." }
        $resolved = Get-EffectiveTemplate -Template $base -Stack $nextStack
        Merge-TemplateLayer -TargetSettings $settings -TargetExtra $extra -Layer $resolved
    }
    Merge-TemplateLayer -TargetSettings $settings -TargetExtra $extra -Layer $Template
    return [pscustomobject][ordered]@{
        Name=$name; Scope=(Get-ObjectPropertyValue $Template 'Scope' 'Kombiniert'); Description=(Get-ObjectPropertyValue $Template 'Description' ''); BuiltIn=[bool](Get-ObjectPropertyValue $Template 'BuiltIn' $false); Extends=@(Get-ObjectPropertyValue $Template 'Extends' @()); Settings=$settings; Extra=$extra
    }
}

function Get-TemplateEntry {
    param([object]$Template,[string]$Key)
    if ($null -eq $Template -or $null -eq $Template.Settings) { return $null }
    if ($Template.Settings -is [System.Collections.IDictionary]) { return $Template.Settings[$Key] }
    $property = $Template.Settings.PSObject.Properties[$Key]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-SetupControlValue {
    param([string]$Key,[bool]$Apply,$Value)
    $entry = $script:SetupControls[$Key]
    if ($null -eq $entry) { return }
    $entry.Apply.Checked = $Apply
    switch ($entry.Definition.Type) {
        'Bool' { $entry.Value.Checked = [bool]$Value }
        'Number' {
            $n = [decimal]$Value
            if ($n -lt $entry.Value.Minimum) { $n = $entry.Value.Minimum }
            if ($n -gt $entry.Value.Maximum) { $n = $entry.Value.Maximum }
            $entry.Value.Value = $n
        }
        'Choice' {
            $entry.Value.SelectedItem = [string]$Value
            if ($entry.Value.SelectedIndex -lt 0 -and $entry.Value.Items.Count -gt 0) { $entry.Value.SelectedIndex = 0 }
        }
        'Text' { $entry.Value.Text = [string]$Value }
    }
}

function Set-NumericControlSafely { param($Control,$Value) if ($null -eq $Control -or $null -eq $Value) { return }; $n=[decimal]$Value; if($n -lt $Control.Minimum){$n=$Control.Minimum}; if($n -gt $Control.Maximum){$n=$Control.Maximum}; $Control.Value=$n }

function Apply-TemplateExtraToUi {
    param($Extra)
    if ($null -eq $Extra) { return }
    $release = Get-ObjectPropertyValue $Extra 'Release' $null
    if ($null -ne $release) {
        $v=Get-ObjectPropertyValue $release 'GenerateNotes' $null; if($null-ne$v){$releaseGenerateNotesCheckBox.Checked=[bool]$v}
        $v=Get-ObjectPropertyValue $release 'FailNoCommits' $null; if($null-ne$v){$releaseFailNoCommitsCheckBox.Checked=[bool]$v}
        $v=Get-ObjectPropertyValue $release 'VerifyTag' $null; if($null-ne$v){$releaseVerifyTagCheckBox.Checked=[bool]$v}
        $v=Get-ObjectPropertyValue $release 'Draft' $null; if($null-ne$v){$releaseDraftCheckBox.Checked=[bool]$v}
        $v=Get-ObjectPropertyValue $release 'Prerelease' $null; if($null-ne$v){$releasePrereleaseCheckBox.Checked=[bool]$v}
        $v=Get-ObjectPropertyValue $release 'Latest' $null; if($null-ne$v -and $releaseLatestComboBox.Items.Contains([string]$v)){$releaseLatestComboBox.SelectedItem=[string]$v}
        $v=Get-ObjectPropertyValue $release 'VersionPaths' $null; if($null-ne$v){$releaseVersionPathsTextBox.Text=([string]$v -replace "`n","`r`n")}
    }
    $cleanup = Get-ObjectPropertyValue $Extra 'Cleanup' $null
    if ($null -ne $cleanup) {
        Set-NumericControlSafely $keepRunsNumeric (Get-ObjectPropertyValue $cleanup 'KeepRuns' $null)
        $v=Get-ObjectPropertyValue $cleanup 'KeepPerWorkflow' $null; if($null-ne$v){$keepPerWorkflowCheckBox.Checked=[bool]$v}
        Set-NumericControlSafely $minimumRunAgeNumeric (Get-ObjectPropertyValue $cleanup 'MinimumRunAge' $null)
        Set-NumericControlSafely $runsLimitNumeric (Get-ObjectPropertyValue $cleanup 'RunsLimit' $null)
        Set-NumericControlSafely $cacheAgeNumeric (Get-ObjectPropertyValue $cleanup 'CacheAge' $null)
        $v=Get-ObjectPropertyValue $cleanup 'ProtectDefaultCache' $null; if($null-ne$v){$protectDefaultBranchCacheCheckBox.Checked=[bool]$v}
        Set-NumericControlSafely $cacheLimitNumeric (Get-ObjectPropertyValue $cleanup 'CacheLimit' $null)
        Set-NumericControlSafely $artifactAgeNumeric (Get-ObjectPropertyValue $cleanup 'ArtifactAge' $null)
        Set-NumericControlSafely $keepArtifactsNumeric (Get-ObjectPropertyValue $cleanup 'KeepArtifacts' $null)
        $v=Get-ObjectPropertyValue $cleanup 'OnlyExpiredArtifacts' $null; if($null-ne$v){$onlyExpiredArtifactsCheckBox.Checked=[bool]$v}
    }
    $content = Get-ObjectPropertyValue $Extra 'Content' $null
    if ($null -ne $content) {
        $v=Get-ObjectPropertyValue $content 'Visibility' $null; if($null-ne$v -and $newRepoVisibilityComboBox.Items.Contains([string]$v)){$newRepoVisibilityComboBox.SelectedItem=[string]$v}
        $v=Get-ObjectPropertyValue $content 'Readme' $null; if($null-ne$v){$newRepoReadmeCheckBox.Checked=[bool]$v}
        $v=Get-ObjectPropertyValue $content 'Gitignore' $null; if($null-ne$v){$newRepoGitignoreTextBox.Text=[string]$v}
        $v=Get-ObjectPropertyValue $content 'License' $null; if($null-ne$v){$newRepoLicenseTextBox.Text=[string]$v}
        $v=Get-ObjectPropertyValue $content 'SourceTemplate' $null; if($null-ne$v){$newRepoSourceTemplateTextBox.Text=[string]$v}
        $v=Get-ObjectPropertyValue $content 'ApplySettings' $null; if($null-ne$v){$applyTemplateAfterCreateCheckBox.Checked=[bool]$v}
    }
}

function Get-CurrentTemplateExtra {
    return [ordered]@{
        Release=[ordered]@{ GenerateNotes=[bool]$releaseGenerateNotesCheckBox.Checked; FailNoCommits=[bool]$releaseFailNoCommitsCheckBox.Checked; VerifyTag=[bool]$releaseVerifyTagCheckBox.Checked; Draft=[bool]$releaseDraftCheckBox.Checked; Prerelease=[bool]$releasePrereleaseCheckBox.Checked; Latest=[string]$releaseLatestComboBox.SelectedItem; VersionPaths=([string]$releaseVersionPathsTextBox.Text -replace "`r`n","`n") }
        Cleanup=[ordered]@{ KeepRuns=[int]$keepRunsNumeric.Value; KeepPerWorkflow=[bool]$keepPerWorkflowCheckBox.Checked; MinimumRunAge=[int]$minimumRunAgeNumeric.Value; RunsLimit=[int]$runsLimitNumeric.Value; CacheAge=[int]$cacheAgeNumeric.Value; ProtectDefaultCache=[bool]$protectDefaultBranchCacheCheckBox.Checked; CacheLimit=[int]$cacheLimitNumeric.Value; ArtifactAge=[int]$artifactAgeNumeric.Value; KeepArtifacts=[int]$keepArtifactsNumeric.Value; OnlyExpiredArtifacts=[bool]$onlyExpiredArtifactsCheckBox.Checked }
        Content=[ordered]@{ Visibility=[string]$newRepoVisibilityComboBox.SelectedItem; Readme=[bool]$newRepoReadmeCheckBox.Checked; Gitignore=[string]$newRepoGitignoreTextBox.Text; License=[string]$newRepoLicenseTextBox.Text; SourceTemplate=[string]$newRepoSourceTemplateTextBox.Text; ApplySettings=[bool]$applyTemplateAfterCreateCheckBox.Checked }
    }
}

function Load-SelectedTemplate {
    $name = [string]$templateComboBox.SelectedItem
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $template = Get-TemplateByName -Name $name
    if ($null -eq $template) { return }
    $effective = Get-EffectiveTemplate -Template $template

    foreach ($definition in $script:SetupDefinitions) {
        $item = Get-TemplateEntry -Template $effective -Key $definition.Key
        if ($null -eq $item) { Set-SetupControlValue -Key $definition.Key -Apply $false -Value $definition.DefaultValue }
        else { Set-SetupControlValue -Key $definition.Key -Apply ([bool](Get-ObjectPropertyValue $item 'Apply' $true)) -Value (Get-ObjectPropertyValue $item 'Value' $definition.DefaultValue) }
    }
    Apply-TemplateExtraToUi -Extra $effective.Extra
    $templateNameTextBox.Text = $name
    $scope = [string](Get-ObjectPropertyValue $template 'Scope' 'Kombiniert'); if($templateScopeComboBox.Items.Contains($scope)){$templateScopeComboBox.SelectedItem=$scope}
    $templateDescriptionTextBox.Text = [string](Get-ObjectPropertyValue $template 'Description' '')
    $isBuiltIn = [bool](Get-ObjectPropertyValue $template 'BuiltIn' $false)
    $templateDeleteButton.Enabled = -not $isBuiltIn
    $templateNameTextBox.ReadOnly = $isBuiltIn
    $templateDescriptionTextBox.ReadOnly = $isBuiltIn
    $templateSaveButton.Text = if ($isBuiltIn) { 'Als Kopie speichern' } else { 'Speichern' }
    $bases = @($effective.Extends)
    $suffix = if ($bases.Count -gt 0) { " Bausteine: $($bases -join ', ')." } else { '' }
    Append-SetupLog "Template '$name' geladen. Bereich: $scope.$suffix" -Clear
}

function Save-CurrentTemplate {
    try {
        $selected = Get-TemplateByName -Name ([string]$templateComboBox.SelectedItem)
        $isBuiltIn = ($null -ne $selected -and [bool](Get-ObjectPropertyValue $selected 'BuiltIn' $false))
        $name = $templateNameTextBox.Text.Trim()
        if ($isBuiltIn -and $name -eq [string]$selected.Name) { $name = "$name - Kopie"; $templateNameTextBox.Text=$name }
        if ([string]::IsNullOrWhiteSpace($name)) { throw 'Gib einen Template-Namen an.' }
        if (@(Get-BuiltinTemplates | Where-Object { $_.Name -eq $name }).Count -gt 0) { throw 'Der Name eines eingebauten Templates kann nicht überschrieben werden. Verwende einen anderen Namen.' }
        $settings = [ordered]@{}
        foreach ($definition in $script:SetupDefinitions) {
            $settings[$definition.Key] = [ordered]@{ Apply=(Test-SetupApply $definition.Key); Value=(Get-SetupControlValue $definition.Key) }
        }
        $newTemplate = [pscustomobject][ordered]@{ SchemaVersion=2; Name=$name; Scope=[string]$templateScopeComboBox.SelectedItem; Description=$templateDescriptionTextBox.Text.Trim(); BuiltIn=$false; Extends=@(); Settings=$settings; Extra=(Get-CurrentTemplateExtra) }
        $remaining = @($script:State.Templates | Where-Object { [bool](Get-ObjectPropertyValue $_ 'BuiltIn' $false) -or [string]$_.Name -ne $name })
        $script:State.Templates = @($remaining + $newTemplate)
        Save-TemplateStore
        Refresh-TemplateCombo
        $templateComboBox.SelectedItem = $name
        Append-SetupLog "Template '$name' gespeichert." -Clear
    }
    catch { Show-Error -Title 'Template konnte nicht gespeichert werden' -ErrorObject $_ }
}

function Delete-SelectedTemplate {
    $name = [string]$templateComboBox.SelectedItem
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $template = Get-TemplateByName -Name $name
    if ($null -ne $template -and [bool](Get-ObjectPropertyValue $template 'BuiltIn' $false)) {
        [void][System.Windows.Forms.MessageBox]::Show($form,'Eingebaute Templates können nicht gelöscht werden. Speichere stattdessen eine angepasste Kopie.','Template geschützt',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    $answer = [System.Windows.Forms.MessageBox]::Show($form,"Template '$name' wirklich löschen?",'Template löschen',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $script:State.Templates = @($script:State.Templates | Where-Object { [string]$_.Name -ne $name })
    Save-TemplateStore
    Refresh-TemplateCombo
    Load-SelectedTemplate
}

function Get-RecommendedTemplateName {
    param([string]$RepositoryName)
    $meta = Invoke-GhApiJson -Endpoint "repos/$RepositoryName"
    $name = [string]$meta.name
    $desc = [string]$meta.description
    $private = [bool]$meta.private
    $topics = @($meta.topics | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $root = @(Invoke-GhApiJson -Endpoint "repos/$RepositoryName/contents?ref=$([System.Uri]::EscapeDataString([string]$meta.default_branch))")
    $names = @($root | ForEach-Object { [string]$_.name })

    if ($name -match '(?i)upstream|mirror' -or $desc -match '(?i)mirror|upstream') { return 'Profil - Upstream Mirror' }
    if ($name -match '(?i)Engineering-Framework|Software-Engineering' -or $desc -match '(?i)software engineering framework') { return 'Profil - Private Engineering Framework' }
    if ($names -contains 'repository.json') { return 'Profil - Public Home Assistant Add-on' }
    if ($name -match '(?i)kdbx|password|vault|fortress' -or $desc -match '(?i)password|credential|vault') { return 'Profil - Private High Assurance' }
    if ($desc -match '(?i)R&D|research|analysis|analyse' -or $name -match '(?i)Analyse|Research') { return 'Profil - Private Research' }
    if ($topics -contains 'browser-extension' -or $topics -contains 'firefox-extension' -or $names -contains 'manifests') { return 'Profil - Public Browser Extension' }
    if ($private -and (($names -contains 'Dockerfile') -or @($names | Where-Object { $_ -match '(?i)^fly.*\.toml$' }).Count -gt 0)) { return 'Profil - Private Infrastructure' }
    if (-not $private -and ($name -match '(?i)rules|catalog' -or $desc -match '(?i)rules|catalog')) { return 'Profil - Public Data Rules Catalog' }
    if (-not $private -and ($name -match '(?i)Toolz|Tools|Scripts|Bubble-Card-Modules')) { return 'Profil - Public Utility Scripts' }
    $developmentManifests = @('package.json','pyproject.toml','requirements.txt','Cargo.toml','go.mod','pom.xml','build.gradle','build.gradle.kts','composer.json','Gemfile')
    if (-not $private -and @($developmentManifests | Where-Object { $names -contains $_ }).Count -gt 0) { return 'Profil - Public Library Framework' }
    if ($private) { return 'Profil - Private Application' }
    return 'Profil - Public Utility Scripts'
}

function Select-RecommendedTemplateForCurrentRepository {
    try {
        $repo = Get-SelectedRepositoryName
        $name = Get-RecommendedTemplateName -RepositoryName $repo
        if (-not $templateComboBox.Items.Contains($name)) { throw "Empfohlenes Template '$name' ist nicht verfügbar." }
        $templateComboBox.SelectedItem = $name
        Load-SelectedTemplate
        Append-SetupLog "Empfehlung für ${repo}: $name. Die Empfehlung basiert auf Sichtbarkeit, Beschreibung, Topics und Repository-Struktur; vor Anwendung prüfen." -Clear
    }
    catch { Show-Error -Title 'Profil konnte nicht empfohlen werden' -ErrorObject $_ }
}

function Import-SelectedRepositoryAsTemplate {
    try {
        $repo = Get-SelectedRepositoryName
        Append-SetupLog "Lese unterstützte Einstellungen aus $repo ..." -Clear
        $meta = Invoke-GhApiJson -Endpoint "repos/$repo"
        $map = [ordered]@{
            'Repository.Issues'='has_issues'; 'Repository.Projects'='has_projects'; 'Repository.Wiki'='has_wiki'; 'Repository.Discussions'='has_discussions';
            'Repository.PullRequests'='has_pull_requests'; 'Repository.PRPolicy'='pull_request_creation_policy'; 'Repository.IsTemplate'='is_template';
            'Merge.Squash'='allow_squash_merge'; 'Merge.MergeCommit'='allow_merge_commit'; 'Merge.Rebase'='allow_rebase_merge'; 'Merge.AutoMerge'='allow_auto_merge'; 'Merge.DeleteBranch'='delete_branch_on_merge'; 'Merge.UpdateBranch'='allow_update_branch'; 'Merge.WebSignoff'='web_commit_signoff_required'; 'Merge.SquashTitle'='squash_merge_commit_title'; 'Merge.SquashMessage'='squash_merge_commit_message'
        }
        Set-AllSetupApply -Value $false
        if ($newRepoVisibilityComboBox.Items.Contains([string]$meta.visibility)) { $newRepoVisibilityComboBox.SelectedItem=[string]$meta.visibility }
        $newRepoSourceTemplateTextBox.Text=$repo
        foreach ($key in $map.Keys) {
            $prop = $meta.PSObject.Properties[$map[$key]]
            if ($null -ne $prop -and $null -ne $prop.Value) { Set-SetupControlValue -Key $key -Apply $true -Value $prop.Value }
        }
        $sa = Get-ObjectPropertyValue $meta 'security_and_analysis' $null
        foreach ($pair in @(@('Security.SecretScanning','secret_scanning'),@('Security.PushProtection','secret_scanning_push_protection'),@('Security.SecretAi','secret_scanning_ai_detection'),@('Security.SecretNonProvider','secret_scanning_non_provider_patterns'),@('Security.CodeSecurity','code_security'))) {
            $o = Get-ObjectPropertyValue $sa $pair[1] $null
            $status = Get-ObjectPropertyValue $o 'status' $null
            if ($null -ne $status) { Set-SetupControlValue -Key $pair[0] -Apply $true -Value ([string]$status -eq 'enabled') }
        }
        try {
            $ap = Invoke-GhApiJson -Endpoint "repos/$repo/actions/permissions"
            if ($null -ne $ap) {
                if ($null -ne $ap.PSObject.Properties['enabled']) { Set-SetupControlValue 'Actions.Enabled' $true ([bool]$ap.enabled) }
                if ($null -ne $ap.PSObject.Properties['allowed_actions']) { Set-SetupControlValue 'Actions.Allowed' $true ([string]$ap.allowed_actions) }
                if ($null -ne $ap.PSObject.Properties['sha_pinning_required']) { Set-SetupControlValue 'Actions.ShaPinning' $true ([bool]$ap.sha_pinning_required) }
            }
        } catch { Append-SetupLog 'HINWEIS  Actions-Berechtigungen konnten nicht gelesen werden.' }
        try {
            $wp = Invoke-GhApiJson -Endpoint "repos/$repo/actions/permissions/workflow"
            if ($null -ne $wp) {
                Set-SetupControlValue 'Actions.TokenPermission' $true ([string]$wp.default_workflow_permissions)
                Set-SetupControlValue 'Actions.ApprovePR' $true ([bool]$wp.can_approve_pull_request_reviews)
            }
        } catch { Append-SetupLog 'HINWEIS  Workflow-Tokenrechte konnten nicht gelesen werden.' }
        try {
            $ret = Invoke-GhApiJson -Endpoint "repos/$repo/actions/permissions/artifact-and-log-retention"
            if ($null -ne $ret -and $null -ne $ret.PSObject.Properties['days']) { Set-SetupControlValue 'Actions.Retention' $true ([int]$ret.days) }
        } catch { Append-SetupLog 'HINWEIS  Actions-Retention konnte nicht gelesen werden.' }
        try {
            $rulesets = @(Invoke-GhApiJson -Endpoint "repos/$repo/rulesets?includes_parents=false")
            $managed = @($rulesets | Where-Object { [string]$_.name -eq 'GitHub Manager - Default Branch' -and [string]$_.target -eq 'branch' }) | Select-Object -First 1
            if ($null -ne $managed) {
                $detail = Invoke-GhApiJson -Endpoint "repos/$repo/rulesets/$($managed.id)"
                Set-SetupControlValue 'Rules.Enabled' $true ([string]$detail.enforcement -ne 'disabled')
                Set-SetupControlValue 'Rules.Name' $true ([string]$detail.name)
                Set-SetupControlValue 'Rules.Enforcement' $true ([string]$detail.enforcement)
                $rr=@($detail.rules)
                Set-SetupControlValue 'Rules.BlockDeletion' $true (@($rr | Where-Object { $_.type -eq 'deletion' }).Count -gt 0)
                Set-SetupControlValue 'Rules.LinearHistory' $true (@($rr | Where-Object { $_.type -eq 'required_linear_history' }).Count -gt 0)
                Set-SetupControlValue 'Rules.SignedCommits' $true (@($rr | Where-Object { $_.type -eq 'required_signatures' }).Count -gt 0)
                Set-SetupControlValue 'Rules.BlockForcePush' $true (@($rr | Where-Object { $_.type -eq 'non_fast_forward' }).Count -gt 0)
                $pr=@($rr | Where-Object { $_.type -eq 'pull_request' }) | Select-Object -First 1
                Set-SetupControlValue 'Rules.RequirePR' $true ($null -ne $pr)
                if($null-ne$pr){
                    $pp=$pr.parameters
                    Set-SetupControlValue 'Rules.Approvals' $true ([int](Get-ObjectPropertyValue $pp 'required_approving_review_count' 0))
                    Set-SetupControlValue 'Rules.DismissStale' $true ([bool](Get-ObjectPropertyValue $pp 'dismiss_stale_reviews_on_push' $false))
                    Set-SetupControlValue 'Rules.LastPushApproval' $true ([bool](Get-ObjectPropertyValue $pp 'require_last_push_approval' $false))
                    Set-SetupControlValue 'Rules.CodeOwners' $true ([bool](Get-ObjectPropertyValue $pp 'require_code_owner_review' $false))
                    Set-SetupControlValue 'Rules.ResolveThreads' $true ([bool](Get-ObjectPropertyValue $pp 'required_review_thread_resolution' $false))
                }
                $sc=@($rr | Where-Object { $_.type -eq 'required_status_checks' }) | Select-Object -First 1
                if($null-ne$sc){ $contexts=@($sc.parameters.required_status_checks | ForEach-Object { [string]$_.context } | Where-Object { $_ }); Set-SetupControlValue 'Rules.StatusChecks' $true ($contexts -join ',') }
            }
        } catch { Append-SetupLog 'HINWEIS  Managed Ruleset konnte nicht vollständig importiert werden.' }

        try {
            $dep = Get-RepositoryFileContent -RepositoryName $repo -Path '.github/dependabot.yml' -Ref ([string]$meta.default_branch) -AllowMissing
            if ($null -ne $dep) { Set-SetupControlValue 'Security.DependabotVersionUpdates' $true $true }
        } catch { }

        $templateNameTextBox.ReadOnly=$false; $templateDescriptionTextBox.ReadOnly=$false; $templateDeleteButton.Enabled=$true
        $templateNameTextBox.Text = "Import - $repo"
        $templateScopeComboBox.SelectedItem = 'Kombiniert'
        $templateDescriptionTextBox.Text = "Aus den über die GitHub API zuverlässig lesbaren Einstellungen von $repo importiert. Nicht lesbare/planabhängige Werte bleiben auf 'Anwenden = Nein'."
        Append-SetupLog "Import abgeschlossen. Prüfe die markierten Werte und klicke 'Speichern', um daraus ein eigenes Template zu machen."
    }
    catch { Show-Error -Title 'Repository-Einstellungen konnten nicht importiert werden' -ErrorObject $_ }
}

function Append-SetupLog {
    param([string]$Message,[switch]$Clear)
    if ($null -eq $setupResultTextBox) { return }
    if ($Clear) { $setupResultTextBox.Clear() }
    if ($setupResultTextBox.TextLength -gt 0) { $setupResultTextBox.AppendText("`r`n") }
    $setupResultTextBox.AppendText($Message)
    $setupResultTextBox.SelectionStart = $setupResultTextBox.TextLength
    $setupResultTextBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-SetupStep {
    param([string]$Name,[scriptblock]$Action)
    try {
        & $Action
        Append-SetupLog "OK  $Name"
        return $true
    }
    catch {
        Append-SetupLog "FEHLER  $Name`r`n        $($_.Exception.Message)"
        Write-Log -Level ERROR -Message "${Name}: $($_.Exception.Message)"
        return $false
    }
}

function Get-DetectedDependabotTargets {
    param([string]$RepositoryName,[string]$Branch)

    $encodedBranch = [System.Uri]::EscapeDataString($Branch)
    $treeResult = Invoke-GhApiJson -Endpoint "repos/$RepositoryName/git/trees/$encodedBranch?recursive=1"
    $items = @()
    if ($null -ne $treeResult -and $null -ne $treeResult.PSObject.Properties['tree']) { $items = @($treeResult.tree) }
    if ($items.Count -eq 0) {
        $items = @(Invoke-GhApiJson -Endpoint "repos/$RepositoryName/contents?ref=$encodedBranch" | ForEach-Object { [pscustomobject]@{ path=[string]$_.name; type=[string]$_.type } })
    }

    $targets = New-Object System.Collections.ArrayList
    $seen = @{}
    function Add-Target([string]$ecosystem,[string]$directory) {
        if ([string]::IsNullOrWhiteSpace($directory)) { $directory='/' }
        if (-not $directory.StartsWith('/')) { $directory='/' + $directory }
        $directory=$directory.TrimEnd('/'); if([string]::IsNullOrWhiteSpace($directory)){$directory='/'}
        $key="$ecosystem|$directory"
        if (-not $seen.ContainsKey($key)) { $seen[$key]=$true; [void]$targets.Add([pscustomobject]@{ Ecosystem=$ecosystem; Directory=$directory }) }
    }
    function Parent-Directory([string]$path) {
        $normalized=$path -replace '\\','/'
        $i=$normalized.LastIndexOf('/')
        if($i -lt 0){return '/'}
        $d=$normalized.Substring(0,$i)
        if([string]::IsNullOrWhiteSpace($d)){return '/'}
        return '/' + $d.Trim('/')
    }

    foreach ($item in $items) {
        if ([string](Get-ObjectPropertyValue $item 'type' '') -ne 'blob' -and [string](Get-ObjectPropertyValue $item 'type' '') -ne 'file') { continue }
        $path=[string](Get-ObjectPropertyValue $item 'path' '')
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ($path -match '(?i)(^|/)(node_modules|vendor|third_party|third-party|fixtures|test-fixtures)(/|$)') { continue }
        $file=[System.IO.Path]::GetFileName($path)
        $dir=Parent-Directory $path
        switch -Regex ($file) {
            '^package\.json$' { Add-Target 'npm' $dir; break }
            '^(pyproject\.toml|requirements[^/]*\.txt|Pipfile|setup\.py)$' { Add-Target 'pip' $dir; break }
            '^pom\.xml$' { Add-Target 'maven' $dir; break }
            '^build\.gradle(\.kts)?$' { Add-Target 'gradle' $dir; break }
            '^go\.mod$' { Add-Target 'gomod' $dir; break }
            '^Cargo\.toml$' { Add-Target 'cargo' $dir; break }
            '^composer\.json$' { Add-Target 'composer' $dir; break }
            '^Gemfile$' { Add-Target 'bundler' $dir; break }
            '^(packages\.config|Directory\.Packages\.props)$' { Add-Target 'nuget' $dir; break }
            '\.(csproj|fsproj|vbproj)$' { Add-Target 'nuget' $dir; break }
            '^Dockerfile$' { Add-Target 'docker' $dir; break }
        }
        if ($path -match '^\.github/workflows/[^/]+\.(yml|yaml)$') { Add-Target 'github-actions' '/' }
    }
    return @($targets)
}

function New-DependabotYaml {
    param([string]$RepositoryName,[string]$Branch)
    $schedule = [string](Get-SetupControlValue 'Security.DependabotSchedule')
    $limit = [int](Get-SetupControlValue 'Security.DependabotPRLimit')
    $ecoSetting = ([string](Get-SetupControlValue 'Security.DependabotEcosystems')).Trim()

    if ([string]::IsNullOrWhiteSpace($ecoSetting) -or $ecoSetting -eq 'auto') {
        $targets = @(Get-DetectedDependabotTargets -RepositoryName $RepositoryName -Branch $Branch)
    }
    else {
        $targets = @($ecoSetting.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { [pscustomobject]@{ Ecosystem=$_; Directory='/' } })
    }
    if ($targets.Count -eq 0) { throw 'Es wurde kein unterstütztes Package-Ecosystem erkannt. Trage die Ecosystems manuell ein oder deaktiviere Dependabot-Version-Updates für dieses Repository.' }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('version: 2')
    $lines.Add('updates:')
    foreach ($target in $targets) {
        $eco=[string]$target.Ecosystem; $dir=[string]$target.Directory
        $lines.Add("  - package-ecosystem: `"$eco`"")
        $lines.Add("    directory: `"$dir`"")
        $lines.Add('    schedule:')
        $lines.Add("      interval: `"$schedule`"")
        $lines.Add("    open-pull-requests-limit: $limit")
    }
    return (($lines -join "`n") + "`n")
}

function Set-DependabotConfiguration {
    param([string]$RepositoryName)
    $branch = Get-RepositoryDefaultBranchName -RepositoryName $RepositoryName
    $yaml = New-DependabotYaml -RepositoryName $RepositoryName -Branch $branch
    $path = '.github/dependabot.yml'
    $existing = Get-RepositoryFileContent -RepositoryName $RepositoryName -Path $path -Ref $branch -AllowMissing
    $sha = if ($null -ne $existing) { $existing.Sha } else { '' }
    try {
        [void](Set-RepositoryFileContent -RepositoryName $RepositoryName -Path $path -Content $yaml -CommitMessage 'chore: configure Dependabot' -Branch $branch -Sha $sha)
        Append-SetupLog "    dependabot.yml direkt auf '$branch' geschrieben."
    }
    catch {
        if ($_.Exception.Message -notmatch '(?i)protected|ruleset|pull request|422|changes must be made') { throw }
        $configBranch = "chore/dependabot-config-$((Get-Date).ToString('yyyyMMddHHmmss'))"
        [void](New-RepositoryBranch -RepositoryName $RepositoryName -BranchName $configBranch -BaseBranch $branch)
        [void](Set-RepositoryFileContent -RepositoryName $RepositoryName -Path $path -Content $yaml -CommitMessage 'chore: configure Dependabot' -Branch $configBranch -Sha $sha)
        $url = Invoke-Gh -Arguments @('pr','create','--repo',$RepositoryName,'--base',$branch,'--head',$configBranch,'--title','chore: configure Dependabot','--body','Automatisch vom GitHub Manager erzeugte Dependabot-Konfiguration.')
        Append-SetupLog "    Default Branch ist geschützt; Dependabot-Konfiguration als PR erstellt: $(([string]$url).Trim())"
    }
}

function Set-ManagedRuleset {
    param([string]$RepositoryName)
    $enabled = [bool](Get-SetupControlValue 'Rules.Enabled')
    $name = ([string](Get-SetupControlValue 'Rules.Name')).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'GitHub Manager - Default Branch' }

    $existing = @(Invoke-GhApiJson -Endpoint "repos/$RepositoryName/rulesets?includes_parents=false" | Where-Object { [string]$_.name -eq $name -and [string]$_.source_type -eq 'Repository' }) | Select-Object -First 1
    if (-not $enabled) {
        if ($null -ne $existing) {
            [void](Invoke-GhApiBody -Endpoint "repos/$RepositoryName/rulesets/$($existing.id)" -Method PUT -Body @{ enforcement='disabled' } -AllowEmpty)
        }
        return
    }

    $rules = New-Object System.Collections.ArrayList
    if ((Test-SetupApply 'Rules.BlockDeletion') -and [bool](Get-SetupControlValue 'Rules.BlockDeletion')) { [void]$rules.Add(@{type='deletion'}) }
    if ((Test-SetupApply 'Rules.LinearHistory') -and [bool](Get-SetupControlValue 'Rules.LinearHistory')) { [void]$rules.Add(@{type='required_linear_history'}) }
    if ((Test-SetupApply 'Rules.SignedCommits') -and [bool](Get-SetupControlValue 'Rules.SignedCommits')) { [void]$rules.Add(@{type='required_signatures'}) }
    if ((Test-SetupApply 'Rules.BlockForcePush') -and [bool](Get-SetupControlValue 'Rules.BlockForcePush')) { [void]$rules.Add(@{type='non_fast_forward'}) }

    if ((Test-SetupApply 'Rules.RequirePR') -and [bool](Get-SetupControlValue 'Rules.RequirePR')) {
        $allowed = New-Object System.Collections.ArrayList
        if ([bool](Get-SetupControlValue 'Merge.Squash')) { [void]$allowed.Add('squash') }
        if ([bool](Get-SetupControlValue 'Merge.Rebase')) { [void]$allowed.Add('rebase') }
        if ([bool](Get-SetupControlValue 'Merge.MergeCommit')) { [void]$allowed.Add('merge') }
        if ($allowed.Count -eq 0) { [void]$allowed.Add('squash') }
        $params = [ordered]@{
            allowed_merge_methods = @($allowed)
            dismiss_stale_reviews_on_push = [bool](Get-SetupControlValue 'Rules.DismissStale')
            dismissal_restriction = @{ enabled=$false; allowed_actors=@() }
            require_code_owner_review = [bool](Get-SetupControlValue 'Rules.CodeOwners')
            require_last_push_approval = [bool](Get-SetupControlValue 'Rules.LastPushApproval')
            required_approving_review_count = [int](Get-SetupControlValue 'Rules.Approvals')
            required_review_thread_resolution = [bool](Get-SetupControlValue 'Rules.ResolveThreads')
        }
        [void]$rules.Add(@{type='pull_request';parameters=$params})
    }

    if (Test-SetupApply 'Rules.StatusChecks') {
        $contexts = @(([string](Get-SetupControlValue 'Rules.StatusChecks')).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($contexts.Count -gt 0) {
            $checks = @($contexts | ForEach-Object { @{context=$_} })
            [void]$rules.Add(@{type='required_status_checks';parameters=@{do_not_enforce_on_create=$true;required_status_checks=$checks;strict_required_status_checks_policy=$false}})
        }
    }

    $body = [ordered]@{
        name = $name
        target = 'branch'
        enforcement = [string](Get-SetupControlValue 'Rules.Enforcement')
        conditions = @{ ref_name = @{ include=@('~DEFAULT_BRANCH'); exclude=@() } }
        rules = @($rules)
    }
    if ($null -ne $existing) {
        [void](Invoke-GhApiBody -Endpoint "repos/$RepositoryName/rulesets/$($existing.id)" -Method PUT -Body $body)
    }
    else {
        [void](Invoke-GhApiBody -Endpoint "repos/$RepositoryName/rulesets" -Method POST -Body $body)
    }
}

function Apply-SetupTemplateToRepository {
    param([string]$RepositoryName)
    if ([string]::IsNullOrWhiteSpace($RepositoryName)) { $RepositoryName = Get-SelectedRepositoryName }
    Append-SetupLog "Wende Einstellungen auf $RepositoryName an ..." -Clear
    Set-Status "Wende Repository-Template an ..."
    $form.UseWaitCursor = $true
    $ok = 0; $failed = 0

    try {
        $repoMetadata = $null
        try { $repoMetadata = Invoke-GhApiJson -Endpoint "repos/$RepositoryName" } catch { }

        $repoBody = [ordered]@{}
        $repoMap = [ordered]@{
            'Repository.Issues'='has_issues'; 'Repository.Projects'='has_projects'; 'Repository.Wiki'='has_wiki'; 'Repository.Discussions'='has_discussions';
            'Repository.PullRequests'='has_pull_requests'; 'Repository.PRPolicy'='pull_request_creation_policy'; 'Repository.IsTemplate'='is_template';
            'Merge.Squash'='allow_squash_merge'; 'Merge.MergeCommit'='allow_merge_commit'; 'Merge.Rebase'='allow_rebase_merge'; 'Merge.AutoMerge'='allow_auto_merge';
            'Merge.DeleteBranch'='delete_branch_on_merge'; 'Merge.UpdateBranch'='allow_update_branch'; 'Merge.WebSignoff'='web_commit_signoff_required';
            'Merge.SquashTitle'='squash_merge_commit_title'; 'Merge.SquashMessage'='squash_merge_commit_message'
        }
        foreach ($key in $repoMap.Keys) { if (Test-SetupApply $key) { $repoBody[$repoMap[$key]] = Get-SetupControlValue $key } }
        if ($repoBody.Count -gt 0) { if (Invoke-SetupStep 'Repository- und Merge-Einstellungen' { [void](Invoke-GhApiBody -Endpoint "repos/$RepositoryName" -Method PATCH -Body $repoBody) }) { $ok++ } else { $failed++ } }

        if (Test-SetupApply 'Security.DependabotAlerts') {
            $enable = [bool](Get-SetupControlValue 'Security.DependabotAlerts')
            if (Invoke-SetupStep 'Dependabot Alerts / Dependency Graph' { Invoke-GhApiNoContent -Endpoint "repos/$RepositoryName/vulnerability-alerts" -Method $(if($enable){'PUT'}else{'DELETE'}) }) { $ok++ } else { $failed++ }
        }
        if (Test-SetupApply 'Security.DependabotSecurityUpdates') {
            $enable = [bool](Get-SetupControlValue 'Security.DependabotSecurityUpdates')
            if (Invoke-SetupStep 'Dependabot Security Updates' { Invoke-GhApiNoContent -Endpoint "repos/$RepositoryName/automated-security-fixes" -Method $(if($enable){'PUT'}else{'DELETE'}) }) { $ok++ } else { $failed++ }
        }

        $security = [ordered]@{}
        $securityMap = [ordered]@{
            'Security.SecretScanning'='secret_scanning'; 'Security.PushProtection'='secret_scanning_push_protection';
            'Security.SecretAi'='secret_scanning_ai_detection'; 'Security.SecretNonProvider'='secret_scanning_non_provider_patterns'; 'Security.CodeSecurity'='code_security'
        }
        foreach ($key in $securityMap.Keys) { if (Test-SetupApply $key) { $security[$securityMap[$key]] = @{status=$(if([bool](Get-SetupControlValue $key)){'enabled'}else{'disabled'})} } }
        if ($security.Count -gt 0) { if (Invoke-SetupStep 'Security & Analysis' { [void](Invoke-GhApiBody -Endpoint "repos/$RepositoryName" -Method PATCH -Body @{security_and_analysis=$security}) }) { $ok++ } else { $failed++ } }

        if (Test-SetupApply 'Security.PrivateVulnerability') {
            $enable = [bool](Get-SetupControlValue 'Security.PrivateVulnerability')
            $isPublic = ($null -ne $repoMetadata -and [string]$repoMetadata.visibility -eq 'public')
            if ($enable -and -not $isPublic) {
                Append-SetupLog 'ÜBERSPRUNGEN  Private Vulnerability Reporting ist auf GitHub.com für öffentliche Repositories vorgesehen.'
            }
            else {
                if (Invoke-SetupStep 'Private Vulnerability Reporting' { Invoke-GhApiNoContent -Endpoint "repos/$RepositoryName/private-vulnerability-reporting" -Method $(if($enable){'PUT'}else{'DELETE'}) }) { $ok++ } else { $failed++ }
            }
        }
        if (Test-SetupApply 'Security.ImmutableReleases') {
            $enable = [bool](Get-SetupControlValue 'Security.ImmutableReleases')
            if (Invoke-SetupStep 'Immutable Releases' { Invoke-GhApiNoContent -Endpoint "repos/$RepositoryName/immutable-releases" -Method $(if($enable){'PUT'}else{'DELETE'}) }) { $ok++ } else { $failed++ }
        }

        if ((Test-SetupApply 'Actions.Enabled') -or (Test-SetupApply 'Actions.Allowed') -or (Test-SetupApply 'Actions.ShaPinning')) {
            if (Invoke-SetupStep 'GitHub Actions Berechtigungen' {
                $current = Invoke-GhApiJson -Endpoint "repos/$RepositoryName/actions/permissions"
                $body = [ordered]@{
                    enabled = if (Test-SetupApply 'Actions.Enabled') { [bool](Get-SetupControlValue 'Actions.Enabled') } else { [bool]$current.enabled }
                }

                if (Test-SetupApply 'Actions.Allowed') {
                    $body['allowed_actions'] = [string](Get-SetupControlValue 'Actions.Allowed')
                }
                elseif ($null -ne $current.PSObject.Properties['allowed_actions'] -and -not [string]::IsNullOrWhiteSpace([string]$current.allowed_actions)) {
                    $body['allowed_actions'] = [string]$current.allowed_actions
                }

                if (Test-SetupApply 'Actions.ShaPinning') {
                    $body['sha_pinning_required'] = [bool](Get-SetupControlValue 'Actions.ShaPinning')
                }
                elseif ($null -ne $current.PSObject.Properties['sha_pinning_required']) {
                    $body['sha_pinning_required'] = [bool]$current.sha_pinning_required
                }

                [void](Invoke-GhApiBody -Endpoint "repos/$RepositoryName/actions/permissions" -Method PUT -Body $body -AllowEmpty)
            }) { $ok++ } else { $failed++ }
        }

        if ((Test-SetupApply 'Actions.TokenPermission') -or (Test-SetupApply 'Actions.ApprovePR')) {
            if (Invoke-SetupStep 'GITHUB_TOKEN Standardrechte' {
                $current = Invoke-GhApiJson -Endpoint "repos/$RepositoryName/actions/permissions/workflow"
                $body = [ordered]@{
                    default_workflow_permissions = if (Test-SetupApply 'Actions.TokenPermission') { [string](Get-SetupControlValue 'Actions.TokenPermission') } else { [string]$current.default_workflow_permissions }
                    can_approve_pull_request_reviews = if (Test-SetupApply 'Actions.ApprovePR') { [bool](Get-SetupControlValue 'Actions.ApprovePR') } else { [bool]$current.can_approve_pull_request_reviews }
                }
                [void](Invoke-GhApiBody -Endpoint "repos/$RepositoryName/actions/permissions/workflow" -Method PUT -Body $body -AllowEmpty)
            }) { $ok++ } else { $failed++ }
        }
        if (Test-SetupApply 'Actions.Retention') {
            $days = [int](Get-SetupControlValue 'Actions.Retention')
            if (Invoke-SetupStep 'Actions Artefakt-/Log-Aufbewahrung' { Invoke-GhApiNoContent -Endpoint "repos/$RepositoryName/actions/permissions/artifact-and-log-retention" -Method PUT -Fields @("days=$days") }) { $ok++ } else { $failed++ }
        }

        if (Test-SetupApply 'Security.DependabotVersionUpdates') {
            if ([bool](Get-SetupControlValue 'Security.DependabotVersionUpdates')) {
                if (Invoke-SetupStep 'Dependabot Version Updates (dependabot.yml)' { Set-DependabotConfiguration -RepositoryName $RepositoryName }) { $ok++ } else { $failed++ }
            }
            else { Append-SetupLog 'HINWEIS  Dependabot-Version-Updates: Datei wird nicht automatisch gelöscht; Wert steht auf Aus.' }
        }

        if (Test-SetupApply 'Rules.Enabled') {
            if (Invoke-SetupStep 'Default-Branch Ruleset' { Set-ManagedRuleset -RepositoryName $RepositoryName }) { $ok++ } else { $failed++ }
        }

        Append-SetupLog "`r`nFertig: $ok Schritte erfolgreich, $failed fehlgeschlagen."
        Set-Status "Template angewendet: $ok erfolgreich, $failed fehlgeschlagen."
        if ($failed -gt 0) {
            [void][System.Windows.Forms.MessageBox]::Show($form,"Template wurde teilweise angewendet. $failed Schritt(e) sind fehlgeschlagen. Details stehen im Ergebnisfeld und Diagnoselog.",'Template teilweise angewendet',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }
    finally { $form.UseWaitCursor = $false }
}

function Apply-CurrentSetupTemplate {
    try {
        $repo = Get-SelectedRepositoryName
        $count = @($script:SetupDefinitions | Where-Object { Test-SetupApply $_.Key }).Count
        $answer = [System.Windows.Forms.MessageBox]::Show($form,"$count markierte Einstellungen auf '$repo' anwenden?",'Repository-Template anwenden',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { Apply-SetupTemplateToRepository -RepositoryName $repo }
    }
    catch { Show-Error -Title 'Template konnte nicht angewendet werden' -ErrorObject $_ }
}

function Create-RepositoryFromUi {
    try {
        if (-not (Update-AuthenticationState -Quiet)) { Start-GhAuthentication; return }
        $owner = $newRepoOwnerTextBox.Text.Trim(); if ([string]::IsNullOrWhiteSpace($owner)) { $owner = $script:State.Login }
        $name = $newRepoNameTextBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($owner)) { throw 'Gib Benutzer oder Organisation an.' }
        if ([string]::IsNullOrWhiteSpace($name)) { throw 'Gib einen Repository-Namen an.' }
        $fullName = "$owner/$name"
        $args = @('repo','create',$fullName,"--$([string]$newRepoVisibilityComboBox.SelectedItem)")
        if (-not [string]::IsNullOrWhiteSpace($newRepoDescriptionTextBox.Text)) { $args += @('--description',$newRepoDescriptionTextBox.Text.Trim()) }
        $templateRepo = $newRepoSourceTemplateTextBox.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($templateRepo)) {
            $args += @('--template',$templateRepo)
        }
        else {
            if ($newRepoReadmeCheckBox.Checked) { $args += '--add-readme' }
            if (-not [string]::IsNullOrWhiteSpace($newRepoGitignoreTextBox.Text)) { $args += @('--gitignore',$newRepoGitignoreTextBox.Text.Trim()) }
            if (-not [string]::IsNullOrWhiteSpace($newRepoLicenseTextBox.Text)) { $args += @('--license',$newRepoLicenseTextBox.Text.Trim()) }
        }
        Set-Status "Erstelle Repository $fullName ..."
        [void](Invoke-Gh -Arguments $args -AllowEmpty)
        Append-SetupLog "Repository '$fullName' erstellt." -Clear

        $ownerTextBox.Text = $owner
        Load-Repositories
        $repositoryCombo.SelectedItem = $fullName
        if ($applyTemplateAfterCreateCheckBox.Checked) { Apply-SetupTemplateToRepository -RepositoryName $fullName }
        Set-Status "Repository $fullName wurde erstellt."
    }
    catch {
        Set-Status 'Repository konnte nicht erstellt werden.'
        Show-Error -Title 'Repository konnte nicht erstellt werden' -ErrorObject $_
    }
}
