# Framework Review – repositoryübergreifende Bereinigung

Bezug: Software-Engineering-Framework / Project Discovery, Roadmap Design, Feature Implementation, Project Completion Review, Risk-Based CI.

## Problem / Capabilities

Die GitHub-Weboberfläche erlaubt oft nur Einzelfallpflege. Die bestehende Version verwaltete Runs, Caches und Artefakte je Repository synchron. Das Ziel für diesen Arbeitsblock ist das gleichzeitige Prüfen und Bereinigen beliebig vieler geladener Repositories bei responsiver GUI.

## Getroffene Architekturentscheidungen

- Wiederverwendung bestehender Anmeldung (`gh`) und WinForms-Hostoberfläche statt parallelem Authentifizierungsstapel.
- Asynchrone Isolation aller neuen Netzwerkarbeiten in PowerShell-Runspaces. Kein Zugriff auf WinForms-Controls aus diesen Runspaces.
- Gemeinsamer HTTP-Client und globaler Netzwerklimiter. Repositories unabhängig, Arten innerhalb desselben Repositories seriell. DELETE-Startfrequenz zusätzlich begrenzt.
- Vorschau als expliziter `Repository × ResourceType → {Candidate IDs, PolicySnapshot}`-Plan.
- Löschung nur nach ausdrücklicher Bestätigung, mit vollständigem Live-Policy-Recheck plus Schnittmenge von alten und neuen Candidate-IDs.
- Fehlende oder unklare Metadaten führen zu **Nicht-Löschen**; 404 bei Nicht-Löschaufruf wird nicht als Erfolg akzeptiert. Fehler sind im Grid und CSV-Bericht erkennbar.
- Stable/Latest/Immutable Releases und Default-Branch-Caches konservativ geschützt.

## Capability / Acceptance

| ID | Kriterium | Stand | Evidenz |
| --- | --- | --- | --- |
| BC-01 | Alle aktuell geladenen Repositories per Checkbox, Alle, Gefilterte | Implementiert, Windows-Test offen | Bulk UI Modul |
| BC-02 | Runs/Caches/Artifacts/Release-Drafts und Prereleases in einem Lauf | Implementiert, API-Test offen | Worker Candidate-Logik |
| BC-03 | Kein Netzwerkanruf im neuen Bulk-UI-Eventhandler | Implementiert, Profiling offen | Background Runspace und UI-Poll |
| BC-04 | Unabhängige Repositories gleichzeitig | Implementiert, Stresstest offen | RunspacePool 1–32 |
| BC-05 | Gemeinsame Limits und GitHub Backoff | Implementiert, HTTP-Fixture-Test offen | Shared Semaphore, paced DELETE |
| BC-06 | Vorschau vor Löschung, Live-Recheck, Snapshot-IDs | Implementiert, Race-Test offen | Execute-Worker |
| BC-07 | Explizite Mehrfachbestätigung | Implementiert, GUI-Test offen | `Confirm-Deletion` mit `DELETE N` |
| BC-08 | Fehlersichtbarkeit pro Repository/Kategorie, CSV | Implementiert, GUI-Test offen | Grid und Export |
| BC-09 | Echter PowerShell-Parser + WinForms-Laufzeit auf Windows | **Offen** | `scripts/Validate-Package.ps1` vorhanden, noch nicht ausgeführt |
| BC-10 | Gleicher Background-Scheduler für alle alten Tabs | **Offen** | weiteres M1-Arbeitspaket |
| BC-11 | Orphan Tags/Packages/Branches mit verifizierter Referenznutzung | **Offen** | separates M8-Arbeitspaket |

## Risikoanalyse

1. **Falsche Löschmenge durch Race Conditions:** Re-fetch im Execute und ID-Schnittmenge; nur Typen mit validierten Schutzregeln.
2. **Sekundäre Rate Limits:** 5 globale REST-Requests, getaktete DELETE-Starts, exponentieller Backoff, expliziter `Retry-After`-/Reset-Respekt.
3. **UI-Hänger:** Jobs in Runspaces, UI-Poll nur für fertige Ergebnisse; alte Einzeltabs ausgenommen.
4. **Mehrfachzustandsänderung desselben Repositories:** Eine Worker-Session je Repo, Ressourcentypen geordnet; Alt-DELETE-Funktionen blockieren Konflikte mit laufenden Bulk-Deletes.
5. **Irreversible Löschung:** Release-Tags nur expliziter Opt-in; noch kein orphan-tag oder stabile-release-Massenlöschung.
6. **Unbekannte PowerShell- oder WinForms-Runtime-Eigenheiten:** Paket bleibt Preview, bis Parser-/GUI-/API-Tests auf Windows bestanden wurden.

## Nächste Gates (priorisiert)

1. Auf Windows `scripts/Validate-Package.ps1` und GUI-Smoke-Test ohne Löschung.
2. GitHub-Integration mit Read-only-Test-Repository: Runs > 1000, leere Seiten, eingeschränkte Zugriffsrechte, gemischte Release-/Tag-Zustände.
3. Isolierte Löschtests in einem Test-Repository einschließlich Abbruch, Rate-Limit, Tags-Sicherheit und Recheck nach Änderungen.
4. UI-Responsivität bei mindestens 15 parallelen Repositories prüfen.
5. Gleiche Hintergrundarchitektur auf alte Single-Repo-Tabs, Auth- und Setup-Pfade übertragen.
6. Weitere Bulk-Operationen nach Risikoeinstufung: Stale Branches, Orphan Tags, Packages, Environments/Deployments.