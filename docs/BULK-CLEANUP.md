# Bulk-Bereinigung – Architektur und Sicherheitsmodell

## Benutzerablauf

1. In der Hauptansicht **Repositories laden**, ggf. Forks/Archivierte einbeziehen.
2. Tab **Bulk-Bereinigung** öffnen. Mit **Alle**, **Gefilterte** oder einzeln Repositories auswählen.
3. Kategorien auswählen: **Workflow-Runs, Caches, Artefakte, Drafts/Prereleases**.
4. Alter, Retention und Schutzoptionen anpassen.
5. **Vorschau aller Repos**. Für jede Kombination `Repository × Kategorie` werden Anzahl, Schutz und Fehlermeldungen angezeigt.
6. Im Ergebnisgrid unerwünschte Repository/Kategorie-Zeilen abwählen.
7. **Ausgewählte Kandidaten löschen**, dann die konkrete Zeichenfolge `DELETE N` eintippen.
8. Fortschritt und Resultate im Grid verfolgen; andere Tabs dürfen währenddessen benutzt werden.
9. Optional mit **CSV exportieren** ein Protokoll der Vorschau oder des Ergebnisses sichern.

## Mehrstufige Sicherheitsprüfung

- Der Preview-Plan enthält eine feste Liste konkreter API-IDs. Aus dem aktualisierten Repository werden beim tatsächlichen Löschlauf **alle Kandidaten erneut berechnet**.
- Es wird ausschließlich die **Schnittmenge** aus vorher bestätigter ID-Liste und erneut erlaubten Kandidaten gelöscht. Neue Einträge nach der Vorschau werden nie mitgelöscht.
- Runs: nur abgeschlossene, mindestens N Tage alte Runs mit bekannten Ergebnissen. Neueste N **pro Workflow** bleiben geschützt.
- Caches: letzte Verwendung, N neueste pro `Key+Ref`; Default-Branch-Caches standardmäßig komplett geschützt.
- Artefakte: Mindestalter und neueste N **je Name**.
- Releases: nur Drafts und Prereleases, mit Mindestalter. Neueste N Releases, GitHubs **Latest** und `immutable` Releases geschützt. Stabile Releases sind vom Auto-Cleanup ausgeschlossen.
- Das Löschen eines zugehörigen Tags ist eine getrennte **Opt-in-Einstellung**. Der Worker löscht keinen Tag, den ein weiterer Release benutzt. Verwaiste Tags werden in dieser Version **nicht** bearbeitet.
- Fehlende Leseberechtigung führt zu einer Fehlerzeile statt zu blindem Löschen.
- GitHub verfügt für diese Arten von Löschungen nicht durchgehend über Wiederherstellung. Vorschau, Typisierung und explizite Bestätigung sind verbindlich.

## Parallelität

- Ein Background-Job pro Repository, bis zu 32 parallele Runspaces.
- Alle markierten Bereinigungsarten innerhalb eines Repository-Jobs werden geordnet abgearbeitet; Repositories laufen unabhängig voneinander.
- Ein globales `SemaphoreSlim` begrenzt REST-Requests auf 5 gleichzeitig.
- DELETE-Starts sind **global auf etwa 2,8 pro Sekunde getaktet**, mehrere Requests können trotzdem gleichzeitig in Bearbeitung sein. Das reduziert GitHubs Secondary Rate Limits.
- Retry für HTTP 429, einschlägige HTTP 403 und temporäre 5xx; `Retry-After` und `X-RateLimit-Reset` werden berücksichtigt.
- Zugriffstoken wird einmal im **Hintergrund** durch `gh auth token` bezogen; UI und Worker teilen keine WinForms-Controls.
- UI-Timer liest Fortschrittsereignisse/Ergebnisse ohne blockierende GitHub-Aufrufe aus.
- Cancel signalisiert einen kooperativen Abbruch; bereits erfolgreich gelöschte Daten bleiben gelöscht.
- Alte synchrone Einzelrepo-Funktionen sind **nicht** vollständig in diese Architektur migriert. Während einer Bulk-Löschung verhindern die drei alten Cleanup-Funktionen konkurrierende Deletes auf demselben Repo. Eine vollständige einheitliche Jobverwaltung für alle Bereiche bleibt Roadmap-Arbeit.

## Grenzen und offene Tests

- Die Repository-Auswahl beruht auf der **aktuell geladenen Benutzer- oder Organisationsliste**, nicht auf sämtlichen Organisationen gleichzeitig.
- „Alle“ meint alle nach den globalen Repository-Filtern geladenen Repositories. Der ursprüngliche `gh repo list`-Abruf wurde von 1.000 auf 10.000 erhöht.
- Releases mit aufgelösten komplexen Tag-Verweisen, Packages, orphaned Git Tags, Branches, Deployment-Runs und LFS gehören zu späteren separaten Cleanup-Operationen.
- Der Bulk-Run-Parser nutzt ausdrücklich `GET /actions/runs` **ohne** `status`-Suchparameter und prüft `completed` lokal. Der ältere Einzelrepo-Tab arbeitet noch nach dem älteren Verfahren.
- Native Parserprüfung unter Windows: `powershell.exe -NoProfile -File scripts/Validate-Package.ps1`.
- End-to-End-GUI-, Auth-/HTTP-Integration-, Cancel-/Race- und Rate-Limit-Tests auf einem Windows-System müssen vor Produktionsfreigabe erfolgen.
