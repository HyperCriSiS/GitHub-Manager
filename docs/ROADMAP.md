# GitHub Manager – Roadmap

Status: 2026-09-08  
Roadmap-Modell: Software-Engineering-Framework (`PROJECT-DISCOVERY`, `ROADMAP-DESIGN`, `FEATURE-IMPLEMENTATION`, `PROJECT-COMPLETION-REVIEW`)

## Produktziel

GitHub Manager ist **kein Ersatz für github.com**. Das Tool konzentriert sich auf Aufgaben, bei denen die GitHub-Weboberfläche unnötig viele Klicks benötigt, keine brauchbare Bulk-Funktion bietet oder wiederkehrende Repository-Policy nicht als wiederverwendbares Profil ausdrücken kann.

Kernjobs:

1. viele Repositories konsistent konfigurieren,
2. wiederkehrende Einstellungen als Templates/Policies speichern,
3. aktuellen Zustand gegen gewünschte Policy vergleichen,
4. sichere Bulk-Operationen mit Vorschau ausführen,
5. GitHub Actions/Release-Daten gezielt bereinigen,
6. Releases schneller und konsistenter vorbereiten,
7. Security-Features wie CodeQL repository-spezifisch einrichten,
8. lange Operationen parallel im Hintergrund ausführen, ohne die GUI zu blockieren.

## Leitplanken

- **Evidence before prose:** Änderungen zeigen vor Ausführung den aktuellen und gewünschten Zustand, soweit GitHub ihn zuverlässig lesbar macht.
- **Risk determines depth:** Löschungen, Rulesets, Release- und Security-Änderungen erhalten stärkere Schutzmechanismen als rein kosmetische Einstellungen.
- **Compose, don’t duplicate:** Bereichstemplates werden zu Profilen kombiniert; keine Repository-spezifischen Kopien derselben Policy.
- **Execute-path safety:** Schutzregeln werden unmittelbar vor destruktiven API-Aufrufen erneut geprüft.
- **Repository write serialization:** pro Repository maximal ein schreibender Hintergrundjob; unabhängige Repositories dürfen parallel bearbeitet werden.
- **Bounded concurrency:** Netzwerkparallelität ist begrenzt und berücksichtigt GitHub Secondary Rate Limits.
- **No hidden destructive automation:** Git-History-Rewrites, LFS-Bereinigung und Package-Löschungen sind eigene Hochrisiko-Workflows, keine Nebenoption eines allgemeinen Cleanup-Buttons.

---

## M0 – Reliability Foundation — P0

**Ziel:** Das Tool muss zuverlässig starten und Fehler transparent diagnostizieren, bevor weitere Features zählen.

### Umfang
- PowerShell-Parserprüfung für jede `.ps1` vor Paketierung.
- StrictMode-kompatibler Code.
- zentrale API-/CLI-Fehlerbehandlung.
- Diagnose-Log und sichtbarer GitHub-Authentifizierungsstatus.
- Versionsnummer in Fenster, Dateiname, Launcher und Paket konsistent.
- statische Integritätsprüfung für fehlende UI-Variablen und Modulimporte.

### Acceptance / Evidence
- 0 Parserfehler in allen `.ps1`.
- Startskripte referenzieren exakt die ausgelieferte Hauptdatei.
- Authentifizierungsfehler führen nicht zu einer leeren, scheinbar erfolgreichen Repo-Liste.
- Regressionstest für `$variable:`-Interpolationsfehler.

---

## M1 – Responsive UX & Background Operations — P0

**Ziel:** Lange Jobs dürfen die GUI nicht blockieren; der nutzbare Arbeitsbereich soll maximiert werden.

### Umfang
- kompakte globale Toolbar.
- Hauptbereiche `Bereinigung`, `Konfiguration`, `Release Manager`.
- Konfiguration über Kategorienavigation statt langer Formularseite.
- feste Aktionsleiste; nur Inhaltsbereich scrollt.
- zentraler Job Manager mit Queue, Fortschritt, Fehlerstatus und Abschlussmeldung.
- mehrere Jobs aus verschiedenen Bereichen gleichzeitig.
- Repository-Schreib-Lock.
- begrenzte Parallelität innerhalb großer Löschjobs.
- Jobdetails/Fehlerprotokoll und Abbrechen für laufende Worker.

### Acceptance / Evidence
- Cleanup kann laufen, während ein Bulk-Konfigurationsjob gestartet und die GUI weiter bedient wird.
- zwei Schreibjobs auf dasselbe Repo laufen nie gleichzeitig.
- zwei unabhängige Repositories können parallel verarbeitet werden.
- Jobs bleiben beim Tabwechsel aktiv.

---

## M2 – Complete Safe Cleanup — P0

**Ziel:** GitHub Actions und Release-Lifecycle schnell bereinigen, ohne schützenswerte Veröffentlichungen zu gefährden.

### Umfang
- Workflow-Runs vollständig REST-paginieren; kein 1.000er Search-Cap.
- Runs: Schutz nach Anzahl, Workflow, Alter, Conclusion.
- Actions-Caches: Alter, Branchschutz, Größe.
- Workflow-Artefakte: Alter, Name, Größe.
- Releases & Tags:
  - Draft/Prerelease/Stable getrennt,
  - Latest schützen,
  - Immutable Releases schützen,
  - Mindestalter,
  - neueste N behalten,
  - Release + zugehörigen Tag optional gemeinsam löschen,
  - verwaiste Tags erkennen,
  - Stable/Nicht-SemVer-Tags nie automatisch markieren.
- Cleanup-Templates.
- tatsächliche Zähler: API gesamt / geladen / geschützt / Kandidaten / markiert.

### Späterer Hochrisiko-Unterbereich
- Packages/Container Lifecycle als separates Modul mit Usage-/Download-/Version-Schutz.
- Git-History/LFS nur als expliziter Expert-Workflow.

### Acceptance / Evidence
- >1.000 Workflow-Runs werden nachweislich geladen.
- Latest/Immutable kann auch durch manuelles Markieren nicht gelöscht werden.
- Cleanup-Operationen sind wiederholbar und 404 beim bereits entfernten Objekt gilt als idempotenter Erfolg.

---

## M3 – Policy Templates, Diff & Bulk Configuration — P0

**Ziel:** Eine Einstellung oder ein ganzes Profil kontrolliert auf viele Repositories anwenden.

### Umfang
- Bereichstemplates für Repository, Merge/Branches, Security/Dependabot, Actions, CodeQL, Rulesets, Release, Cleanup, Content.
- Combined Profiles über `Extends`.
- bestehendes Repository als Settings-Template importieren.
- bestehendes GitHub-Template-Repo als Content-Basis.
- Bulk-Auswahl mehrerer Repositories.
- nur ausgewählte Settings anwenden; alle anderen unverändert lassen.
- realer Diff `Ist → Soll` vor Ausführung.
- unveränderte Werte überspringen.
- Repository-Gruppen speichern:
  - alle,
  - öffentlich,
  - privat,
  - eigene Gruppen.
- Bulk-Vorlagen/Profiles.
- Ergebnisübersicht pro Repository und Setting.

### Acceptance / Evidence
- `Branch nach Merge löschen = Ein` kann in einem Lauf auf alle ausgewählten Repositories angewendet werden.
- Repositories, die bereits `Ein` sind, erzeugen keinen unnötigen PATCH.
- Fehler in einem Repo stoppen nicht die übrigen Repositories.
- Bulk-Ergebnis listet `geändert / unverändert / übersprungen / fehlgeschlagen`.

---

## M4 – Security & CodeQL Automation — P0/P1

**Ziel:** Security-Setup nicht nur einschalten, sondern passend zur Repository-Struktur konfigurieren.

### Umfang
- CodeQL-Analyse aus Repository-Tree, Sprachen, Builddateien und vorhandener CI-Evidenz.
- Default Setup lesen/setzen.
- Query Suite, Threat Model und Sprachen.
- Advanced Setup Generator.
- manuelle Builds für kompilierte Sprachen.
- bestehende CodeQL-Workflows importieren und vergleichen.
- doppelte CodeQL-Konfigurationen erkennen.
- Advanced-Änderungen standardmäßig über Branch + PR.
- optionale SHA-Auflösung verwendeter Actions.
- CodeQL-Bereichstemplates:
  - Simple JS/TS,
  - Browser Extension,
  - Android/Gradle,
  - Kotlin Manual,
  - Python,
  - Mixed Monorepo,
  - High Assurance.
- Dependabot rekursiv/monorepo-fähig.
- Secret Scanning, Push Protection, selected-actions policy, GITHUB_TOKEN policy.

### Acceptance / Evidence
- GUI-Framework wird als Mixed-Stack erkannt und vorhandene doppelte CodeQL-Workflows werden angezeigt.
- projektspezifischer Build (`npm run check:maven-artifacts`) kann übernommen werden.
- Advanced Setup wird nicht direkt auf einen geschützten Default Branch geschrieben.

---

## M5 – Release Lifecycle Manager — P1

**Ziel:** Release-Erstellung und Versionspflege mit deutlich weniger manuellen Schritten als github.com.

### Umfang
- SemVer-Vorschläge Patch/Minor/Major/Beta/RC/Stable.
- Titel/Notes aus vorherigem Release ableiten bzw. automatisch generieren.
- Draft/Prerelease/Latest.
- Release-Assets.
- Versionsdateien erkennen und über PR aktualisieren.
- Tag-Existenz und Zielbranch validieren.
- Release-Profile je Repository-Klasse.
- Preflight-Check:
  - offene Release-blockierende Checks,
  - CodeQL/CI-Status,
  - Version konsistent,
  - Tag noch frei,
  - optional Changelog.
- Post-Release Cleanup/Retention optional verknüpfen.

### Acceptance / Evidence
- Version, Tag und Release können nicht versehentlich auseinanderlaufen.
- Release-Preflight zeigt Blocker vor Erstellung.

---

## M6 – Repository Bootstrap — P1

**Ziel:** neues Repository in einem Ablauf erstellen und vollständig auf den gewünschten Standard bringen.

### Umfang
- Repository erstellen.
- Content-Basis aus GitHub Template Repo.
- Settings-Profil anwenden.
- Standarddateien über Content Template.
- Dependabot/CodeQL/Ruleset nach Repository-Evidenz erzeugen.
- Bootstrap-Preview vor Änderungen.
- optional Topics/Homepage/Visibility.

### Acceptance / Evidence
- neues Repo kann aus `Content + Settings + Security + Release/Cleanup Policy` in einem geführten Ablauf entstehen.

---

## M7 – Policy Audit & Drift — P1

**Ziel:** Nicht nur konfigurieren, sondern Abweichungen über alle Repositories erkennen.

### Umfang
- Repository Fleet Audit.
- Policy Drift Matrix.
- Security-/Actions-/Merge-/Ruleset-Status.
- fehlende Dependabot-/CodeQL-Konfiguration.
- veraltete Action-Versionen / ungepinnte Actions optional.
- Export JSON/CSV/Markdown.
- `Nur Abweichungen`-Ansicht.
- Fix-selected / Fix-all-from-profile.

### Acceptance / Evidence
- ein Lauf zeigt, welche Repositories von ihrem zugewiesenen Profil abweichen.
- Audit selbst ist read-only.

---

## M8 – Advanced Operations — P2

Nur wenn der konkrete Nutzen gegenüber github.com hoch genug ist:

- Labels bulk synchronisieren.
- Repository Topics bulk verwalten.
- Variables/Secrets-Metadaten auditieren; Secret-Werte nie exportieren.
- Environments/Protection Rules verwalten.
- Webhooks/Deploy Keys auditieren.
- Collaborators/Teams read-only Fleet Audit; Writes mit extra Bestätigung.
- stale branches analysieren und sichere Kandidaten anbieten.
- Packages Lifecycle Manager.
- wiederverwendbare Workflow-/Content-Bausteine.

---

## Bewusste Nicht-Ziele

- Issues/PRs/Discussions als vollständige GitHub-UI nachbauen.
- Git-Client ersetzen.
- Secrets im Klartext sichern oder zwischen Repositories kopieren.
- automatische Force-Push-/History-Rewrites als Standardfunktion.
- Enterprise-Funktionen vortäuschen, wenn der Account/Plan sie nicht unterstützt.

## Priorisierungskriterium für neue Features

Ein Feature wird bevorzugt aufgenommen, wenn mindestens eines gilt:

1. GitHub bietet keine entsprechende UI-Funktion,
2. eine Aktion muss regelmäßig über mehrere Repositories erfolgen,
3. die Weboberfläche benötigt viele wiederholte Klicks,
4. eine sichere Vorschau/Diff/Policy-Automation schafft klaren Mehrwert,
5. mehrere GitHub-APIs müssen für einen sinnvollen Workflow orchestriert werden.

Ein Feature wird zurückgestellt, wenn es nur eine bereits komfortable GitHub-Seite dupliziert.