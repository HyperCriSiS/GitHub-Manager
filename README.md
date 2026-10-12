# GitHub Manager

Windows-Desktoptool für **GitHub Fleet Management, sichere Bulk-Bereinigung, Repository-Konfiguration, wiederverwendbare Policy-Templates und Release-Workflows**.

> **Entwicklungsstatus: Preview.** Der aktuelle Quellstand ist `4.2.0-preview`, übernommen aus dem letzten vorhandenen Bulk-Cleanup-Paket. Frühere v5-Entwicklungsbeschreibungen sind in [der Roadmap](docs/ROADMAP.md) festgehalten, nicht als getestete Features veröffentlicht. **Destruktive Operationen noch nicht produktiv einsetzen.**

## Wofür das Tool gedacht ist

GitHub.com soll nicht nachgebaut werden. Der Schwerpunkt liegt auf Funktionen, die dort fehlen oder viele wiederholte Schritte erfordern:

- Workflow-Runs, Caches und Artefakte über **mehrere Repositories** mit Vorschau bereinigen.
- Alte Drafts und Prereleases konservativ bereinigen; Latest, Stable und Immutable schützen.
- Einstellungen und Sicherheitsvorgaben als wiederverwendbare Templates anwenden.
- Releases und Versionierungs-Pull-Requests vorbereiten.
- Perspektivisch: generisches Bulk-Settings, CodeQL-Automatisierung, Policy-Audit und Drift-Behebung.

## Erste Schritte (Windows 10/11)

1. [GitHub CLI](https://cli.github.com/) installieren und mit `gh auth login` anmelden.
2. Dieses Repository klonen oder den **Source-Code** als ZIP herunterladen.
3. `scripts/Validate-Package.ps1` ausführen, um alle PowerShell-Dateien und Paketverweise zu prüfen.
4. Mit `Start-GitHub-Manager-Debug.cmd` starten. Die GUI verwendet Windows PowerShell 5.1/WinForms; andere PowerShell-Versionen müssen separat verifiziert werden.
5. Zunächst nur **Vorschau / Dry-Run** verwenden. Sicherheitsregeln und API-Berechtigungen vor jeder Löschung prüfen.

## Architektur

| Pfad | Funktion |
| --- | --- |
| `GitHub-Manager-v4.2.0.ps1` | Hauptfenster und Einzelrepository-Funktionen |
| `Modules/GitHubManager.BulkCleanup.ps1` | Bulk-Cleanup-Steuerung und Hintergrundjobs |
| `Modules/GitHubManager.BulkCleanup.Worker.ps1` | API-Pagination und Bereinigungskandidaten |
| `Modules/GitHubManager.Templates.ps1` | Repository-Policies/Templates |
| `Modules/GitHubManager.Release.ps1` | Release-Verwaltung |
| `Modules/GitHubManager.Extensions.ps1` | Gemeinsame GitHub-API-Helfer |
| `scripts/Validate-Package.ps1` | Native PowerShell-Parser- und Strukturprüfung |
| `scripts/Build-Package.ps1` | Reproduzierbares Source-ZIP mit SHA-256 |

Die Bulk-Bereinigung verarbeitet voneinander unabhängige Repositories parallel mit begrenzten REST-Aufrufen. Bestehende Einzelrepository-Funktionen sind noch nicht durchgehend asynchron; dies ist ausdrücklich offen.

## Entwicklungsprozess

- **`main`:** integrierte Quellcodebasis, die die vorhandenen automatisierten Prüfungen erfüllt. Das bedeutet noch keine produktive Freigabe.
- **Issues:** Roadmap-Aufgaben mit nachvollziehbaren Akzeptanzkriterien und Testergebnissen.
- **Pull Requests:** Änderungen in kleinen, testbaren Einheiten statt separater nicht rückverfolgbarer ZIP-Versionen.
- **CI:** native Parserprüfung unter Windows PowerShell 5.1 sowie PowerShell 7; Build-Verifikation (keine echten Lösch-API-Aufrufe in CI).
- **Releases:** erst nach erfolgreicher Windows-GUI- und API-Schutzprüfung; keine Preview als stabile Version taggen.

Siehe [Roadmap](docs/ROADMAP.md), [Projektprofil](docs/PROJECT-PROFILE.md), [Risiken](docs/RISK-REGISTER.md), [Bulk-Cleanup](docs/BULK-CLEANUP.md) und [Mitwirken](CONTRIBUTING.md).

## Datenschutz und Berechtigungen

- Authentifizierung erfolgt über `gh`; Tokens dürfen nie eingecheckt oder in Logs kopiert werden.
- Keine Zugangsdaten im Repository hinterlegen. Lokale Benutzerkonfiguration unter `%APPDATA%` bleibt außerhalb der Versionsverwaltung.
- Für öffentliche Repositories gilt: **Die Veröffentlichung allein erteilt noch keine Open-Source-Nutzungslizenz.** Eine Lizenzentscheidung ist als Issue geplant.

## Status der Sicherheitsprüfung

Vor Erstveröffentlichung wurden Paketdateien nach typischen Token-/Private-Key-Mustern untersucht und Repository-spezifische private Inventare ausgeschlossen. Ein vollständiges Secret-Scanning-System oder unabhängiger Security-Audit ist das nicht.
