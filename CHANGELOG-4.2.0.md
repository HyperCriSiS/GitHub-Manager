# 4.2.0 Bulk Cleanup Preview

- Bulk Cleanup Tab für alle geladenen Repositories mit mehrfacher Kategorienauswahl.
- Eigener runspacebasierter Preview-/Execute-Worker; GUI bleibt beim Bulk-Job responsive.
- Runs paginiert über Actions REST API statt `gh run list --status completed`.
- Caches/Artifacts/Releases-Typ-spezifische Schutzregeln sowie zweiter Live-Schutzcheck vor DELETE.
- Optionaler Tag-Delete nur nach gesonderter Bestätigung/Option, für Draft-/Prerelease-Release-Tags.
- Globale API-Parallelitätsgrenze, Delete-Pacing, Retry, Cancel und pro-Repo-Ergebnisse.
- Bestehende Einzelrepo-Löschungen auf gleichzeitige Bulk-Konflikte abgesichert.
- `gh repo list --limit` auf 10000 erhöht.
- Native PowerShell-Parserprüfung als Release-Gate-Skript ergänzt.

## Noch nicht erfüllt

- Windows 5.1 Parser- und GUI-Laufzeittest in dieser Umgebung nicht ausführbar.
- Alle bestehenden Tabs über denselben Hintergrund-Jobmanager zu betreiben bleibt Roadmap-Arbeit.
- Verwaiste Tags sowie Cleanup für weitere GitHub-Ressourcen stehen noch aus.
- Die übrigen früher diskutierten v5-Funktionen sind in diesem Paket **nicht** enthalten.

- CSV-Report für Vorschau und Löschlauf ergänzt.
- Fail-closed bei fehlenden Zeitstempeln, zusätzlicher Referenzschutz für optionale Release-Tags.
