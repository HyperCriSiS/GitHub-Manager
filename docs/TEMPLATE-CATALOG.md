# GitHub Manager 4.1 – Template-Katalog

Die Vorlagen sind absichtlich in **Bereichs-Templates** und daraus zusammengesetzte **Profile** getrennt. Dadurch bleibt jede Policy nur einmal definiert und Profile können ohne Copy/Paste kombiniert werden.

## Bereichs-Templates

### Repository
- **Bereich - Repository Public OSS** – Issues und Pull Requests an; Projects, Wiki und Discussions standardmäßig aus.
- **Bereich - Repository Private** – gleiche schlanke Arbeitsfläche für private Entwicklungs- und Research-Repositories.

### Merge & Branches
- **Bereich - Merge Solo Maintainer** – Squash + Rebase, keine Merge-Commits, Auto-Merge, Branch nach Merge löschen, Branch-Update erlauben.

### Security & Dependabot
- **Bereich - Security Standard** – Dependabot Alerts/Security Updates, Secret Scanning, Push Protection und – soweit unterstützt – Private Vulnerability Reporting.
- **Bereich - Security High Assurance** – Sicherheitsbasis für sensible Projekte; kosten-/planabhängige oder irreversible Härtungen werden nicht automatisch erzwungen.
- **Bereich - Dependabot Standard** – wöchentlich, maximal 5 offene PRs, Ecosystems und Verzeichnisse automatisch erkennen.

### GitHub Actions
- **Bereich - Actions Secure** – Actions an, `GITHUB_TOKEN` read-only, Actions dürfen PRs nicht genehmigen, 30 Tage Retention.
- **Bereich - Actions Strict SHA** – zusätzlich vollständiges SHA-Pinning. Bewusst nur als Opt-in, weil bestehende Workflows sonst brechen können.

### Default-Branch Ruleset
- **Bereich - Ruleset Solo Maintainer** – PR-Pflicht, aber 0 Fremd-Approvals; Threads auflösen, lineare Historie, kein Force-Push/Löschen.
- **Bereich - Ruleset Research** – leichter Schutz ohne PR-Zwang.
- **Bereich - Ruleset Mirror** – vom Manager verwaltetes Ruleset aus, damit Upstream-Sync nicht blockiert wird.

### Release
- **Bereich - Release SemVer** – SemVer, Auto-Notes, kein leerer Release, Versionspfade als Startwert.

### Cleanup
- **Bereich - Cleanup Standard** – 10 Runs pro Workflow, Mindestalter 14 Tage, Caches 14 Tage, Artefakte 30 Tage.
- **Bereich - Cleanup CI Heavy** – 7 Runs pro Workflow, Mindestalter 10 Tage, Caches 10 Tage, Artefakte 21 Tage.

### Content / New Repo
- **Bereich - Content Public OSS** – public + README, projektabhängige Lizenz/.gitignore bleiben leer.
- **Bereich - Content Private** – private + README.

## Zusammengesetzte Profile

- **Profil - Public Browser Extension**
- **Profil - Private Application**
- **Profil - Private High Assurance**
- **Profil - Private Research**
- **Profil - Private Engineering Framework**
- **Profil - Public Library Framework**
- **Profil - Public Data Rules Catalog**
- **Profil - Public Home Assistant Add-on**
- **Profil - Private Infrastructure**
- **Profil - Public Utility Scripts**
- **Profil - Upstream Mirror**

## Warum nicht ein Profil pro Repository?

Die aktuell vorhandenen Repositories benötigen mehrere **Policy-Klassen**, aber keine 15 individuellen Policy-Kopien. Ein neues Profil wird nur dann gerechtfertigt, wenn sich die tatsächlichen GitHub-Regeln unterscheiden – nicht nur, weil das Projekt einen anderen Namen oder eine andere Programmiersprache hat.

## Bestehendes Repository als Template

Es gibt zwei getrennte Mechanismen:

1. **Content-Basis** – das ausgewählte Repository wird als GitHub-Template-Quelle für ein neues Repository übernommen.
2. **Repo importieren** – zuverlässig lesbare GitHub-Einstellungen des ausgewählten Repositories werden in die GUI importiert. Nach Prüfung können sie als eigenes Settings-Template gespeichert werden.

Ein Combined Template kann dadurch Content-Startpunkt, Repository-Policy, Security, Actions, Ruleset, Release und Cleanup gemeinsam abbilden.