# Project Profile – GitHub Manager

**Product:** Windows-Desktoptool zur flotten, nachvollziehbaren GitHub-Repositorien-Verwaltung.

**Status:** Öffentliche 4.2.0-Preview-Quellbasis; kein produktionsvalidierter Release.Die v5-Roadmap ist kein Nachweis implementierter Features.

## Nutzer und Aufgaben
- Maintainer mit mehreren Repositories oder Organisationen.
- Viele wiederkehrende GitHub-Einstellungen konsistent setzen.
- Workflow-Runs, Caches, Artefakte und alte Drafts/Prereleases mit Vorschau bereinigen.
- Reusable Repository-Policies, Release-Workflows, Fleet Audit und Drift-Behebung weiterentwickeln.

## Technische Umgebung
- Windows 10/11, Windows PowerShell 5.1, WinForms.
- GitHub CLI (`gh`) für Anmeldung und einzelne Verwaltungsoperationen.
- GitHub REST API für Batch- und Cleanup-Operationen.
- PowerShell Runspaces für den neuen Bulk-Cleanup; weitere UI-Bereiche teilweise noch synchron.

## Qualitätsgrenzen und Schutz
- Standardmäßig keine irreversible GitHub-Operation ohne explizite Vorschau, konkrete Kandidaten und erneute Ausführungsprüfung.
- Scope- und Feature-Verfügbarkeit GitHub-tarifabhängig; Fehler sichtbar anzeigen, nicht ignorieren.
- Keine Credentials oder sensiblen Repo-Inventare committen.
- CI auf Windows mit nativem Parser. Windows-GUI-Smoke- und API-Mock-Tests als noch offene Release-Gates.

## Quelle der Wahrheit
- GitHub `main` und Pull Requests. Historische ZIPs sind Quellenhinweise, keine parallel gepflegten Projektzweige.
- Geplante v5-Fähigkeiten sind in `docs/ROADMAP.md` und Issues festgehalten, bis Code und Tests sie nachweisen.
