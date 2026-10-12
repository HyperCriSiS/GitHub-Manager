# Contributing

Dieses Repository befindet sich in der Preview-Phase. Änderungen erfolgen über kleine, überprüfbare Pull Requests.

1. Beginne mit einem Issue oder verlinke eine bestehende Roadmap-Aufgabe.
2. Gib bei Fehlern Windows-Version, PowerShell-Version, Schritte zur Reproduktion und anonymisierte Logs an. **Keine Tokens oder privaten Repository-Inhalte posten.**
3. Bei GitHub API-Änderungen: Read-only Vorschau und Destructive-Execute separat testen.
4. Jede neue DELETE-Funktion benötigt Kandidatenschutz, Live-Recheck, explizite Bestätigung, Pagination, Backoff und deterministische Tests.
5. Vor einem PR `scripts/Validate-Package.ps1` ausführen und für GUI-Änderungen einen Windows-Smoke-Test dokumentieren.
6. Keine Änderungen am `main`-Branch per destruktivem Script erzwingen; Merge erst nach grüner CI.

Bis eine Lizenz beschlossen und veröffentlicht ist, werden externe Codebeiträge nicht als frei nachnutzbarer Open-Source-Code ausgewiesen.