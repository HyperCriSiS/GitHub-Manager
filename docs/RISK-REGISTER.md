# Risk Register – GitHub Manager

| Risiko | Auswirkung | Gegenmaßnahme | Status |
| --- | --- | --- | --- |
| Irreversible Bulk-DELETEs | Datenverlust über viele Repos | explizite Preview, bestätigte IDs, Execute-Time-Recheck, Default-Schutzeinstellungen, Tests | im 4.2-Code vorhanden, Integrationstest offen |
| API-Rate-Limits | Abbruch, Teilfortschritt | begrenzte globale Request-Parallelität, Retry/Backoff, fortsetzbare Fehlerberichte | im Code vorhanden, Stresstest offen |
| Blockierte GUI | Bedienung nicht möglich, Windows meldet Keine Rückmeldung | alle Netzwerkoperationen in unabhängigen Runspaces/Tasks; UI nur auf UI-Thread aktualisieren | Bulk-Cleanup umgesetzt, Altbereiche offen |
| Runspace-/Cancellation-Races | inkonsistente Jobzustände | Mock- und Abbruchtests, seriell pro tatsächlicher Ressourcenkollision | offen |
| Parserfehler/fehlende Dateien | Programm startet nicht | native Parserprüfung, Start-Validator, Windows-CI | CI eingerichtet, Ergebnis prüfen |
| Veröffentlichung von Zugangsdaten | Konto-/Repo-Kompromittierung | statische Secret-Prüfung vor Import, keine lokalen Konfigurationen, erneute Prüfung pro PR | Erstprüfung ohne Secret-Fund; laufende Assurance offen |
| GitHub-Plan-/API-Unterschiede | falsche oder unvollständige Policies | Feature Discovery, explizite Unsupported/Unknown Zustände, Test-Mocks | offen |
| CodeQL/Workflow-Duplikate | doppelte CI-Kosten / fehlende Abdeckung | CodeQL Import, Diagnose bestehender Konfigurationen, PR-basierter Advanced Setup | Roadmap, noch nicht in öffentlichem Code |
| Versions-/Branch-Drift | ZIP und GitHub divergieren | versionierte Releases ausschließlich aus GitHub-CI, keine manuellen divergierenden Builds | vorbereitete Build-Skripte, Releases offen |
| Private Reponamen in Analyseberichten | Metadaten-Offenlegung | private Inventare nicht hochladen, Bezeichner im Quellcode generalisieren | für Initialimport geprüft |

## Release-Gates
1. Parser-Test unter Windows PowerShell 5.1 (und PowerShell 7, soweit kompatibel).
2. WinForms-Start auf Windows.
3. API-Fixtures für Pagination, Schutz, Rate-Limit und Lösch-Schnittmengen.
4. Multi-Repo-Fairness, Race-, Cancel- und UI-Responsivitätstests.
5. Abnahme von Lizenz, Dokumentation, Artefakt-SHA-256 und Quellenbezug.
