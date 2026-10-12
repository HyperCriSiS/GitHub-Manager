# Initialimport: Herkunft und Prüfgrenzen

- **Quellbasis:** `GitHub-Manager-v4.2.0-bulk-preview.zip` (vorliegendes, bisher nur statisch geprüftes Testpaket). Die bisher erwähnte v5-Entwicklung ist kein verfügbarer, durchgehend integrierter Quellbaum.
- **Übernommen:** Windows-PowerShell-Hauptskript, Bulk-Cleanup/Worker, Templates, Release-/API-Module, CMD-Starter und ausgewählte öffentliche Projektdokumentation.
- **Nicht übernommen:** lokale Benutzerkonfigurationen, gesonderte private Repository-Empfehlungsinventare, historische defekte ZIPs und überholte Patchnotes.
- **Vor Import gesucht:** typische GitHub-Tokenpräfixe, Cloud-Access-IDs, private Schlüsselblöcke, statische Secret-Zuweisungen, URL-Credentials, E-Mails sowie projektbezogene private Repo-Namen.
- **Treffer:** keine eingebetteten Zugangsdaten gefunden; Laufzeit-Zuweisungen an `$token` und generierte GitHub-URLs wurden manuell als Nicht-Secrets geprüft. Projektspezifische Heuristiken generalisiert.
- **Prüfgrenzen:** heuristische/regexbasierte Quellprüfung ist kein Ersatz für vollständiges Secret Scanning. Weder WinForms-Laufzeittest noch GitHub-DELETE-Integrationstest wurden vor dem Import ausgeführt.
- **Freigabestatus:** Source-Preview ohne produktive Löschfreigabe. PR-CI-Resultat und manuelle Review sind vor Merge zu prüfen.
