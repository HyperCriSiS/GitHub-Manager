# Security Policy

Dieses Tool benötigt Zugriff auf GitHub-Repositories und kann unwiederbringliche Löschungen ausführen. Derzeit handelt es sich um einen **nicht produktionsvalidierten Preview-Stand**.

**Bitte Sicherheitslücken nicht als öffentliche Issues mit Exploit-Details oder Tokens melden.** Verwende GitHubs private Vulnerability-Reporting-Funktion, falls sie für dieses Repository aktiviert ist, oder kontaktiere den Repository-Eigentümer über einen privaten Kanal.

In Berichten keine PATs, `gh auth token`-Ausgaben, privaten Repository-Inhalte oder Secrets hochladen. Ein einmal veröffentlichtes Secret sofort widerrufen und ersetzen.

Geplante Release-Gates: Parserprüfung, WinForms-Smoke-Test auf Windows, API-Mock-Tests für Execute-Time-Schutz, Cancel/Concurrency- und Rate-Limit-Tests.