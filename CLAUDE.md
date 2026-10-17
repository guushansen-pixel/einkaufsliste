# Einkaufsliste

Offline Android-App (Haushalts-Einkaufsliste mit adaptierbaren Kategorien,
Vorlagen-Katalog und Laden-Reihenfolgen), reine Web-App in einer Datei, die
per [apk-builder](../apk-builder) zur APK wird. Datenmodell, Funktionen und
die Paste-Import-Heuristik stehen in [README.md](README.md) - dort
nachlesen statt hier duplizieren.

## Build & Test

Kein Bundler, kein Build-Step für die Web-App selbst. Zum Testen **immer
über http**, nie per `file://` - dort ist localStorage still abgeschaltet
und jede Liste verschwindet beim Neuladen, ohne Fehlermeldung:

```powershell
.\tools\serve.ps1            # http://localhost:8101
```

Manuelle Test-Checkliste im Browser:
- Kategorie/Artikel in der Liste anlegen, umbenennen, löschen, per
  Auf/Ab-Pfeilen sortieren.
- Artikel abhaken (wandert ans Ende der Kategorie) und wieder aufheben.
- Vorlage-Tab: Artikel antippen (fügt der aktiven Liste hinzu / entfernt ihn
  wieder), Menü → "Aus Vorlage befüllen (alles)".
- Favoriten-Chip antippen, Stern an einem Listen-Artikel setzen.
- "Liste importieren" mit einem Textausschnitt im Format
  `KATEGORIE\n  Artikel\n  Artikel` **und** einmal mit einer flachen Liste
  ganz ohne Kategorie-Zeilen (muss unter "Unsortiert" landen).
- "Nach Laden sortieren" / "Laden-Reihenfolgen bearbeiten" mit mindestens
  zwei Kategorien und zwei Profilen.
- "Liste leeren" gefolgt von "Letzte Liste erneut verwenden".
- Reload-Test: Seite neu laden, geprüft dass localStorage-Stand
  (Liste, Vorlage, Favoriten, Laden-Profile) erhalten bleibt.
- PDF-Import: "Liste importieren" → "PDF oder Bild wählen" mit einem echten
  Samsung-Notes-Export (Backups unter
  `D:\sicherung pixel 9 ...\Download\Einkaufsliste_*.pdf`), Prüfliste gegen das
  gerenderte PDF abgleichen. Testdateien nie nach `web/` legen (landen sonst
  in der APK) - einen zweiten Server nutzen, der sie unter eigenem Pfad
  ausliefert. **Browser-Pane muss sichtbar sein**: pdf.js rendert über
  requestAnimationFrame und bleibt in einem versteckten Tab einfach stehen.

APK bauen - **immer über den Wrapper**, nie direkt mit apk-builder (er patcht
Teilen-Intent, `singleTask` und die Datei-Brücke nach, Details im Kopf von
`build.ps1`):

```powershell
.\build.ps1 -VersionName 1.3 -VersionCode <hochzaehlen>            # Debug
.\build.ps1 -VersionName 1.3 -VersionCode <hochzaehlen> -Release   # signiert -> dist\
```

`-Release` legt die APK als `dist\einkaufsliste-<Version>.apk` ab (alte werden
entfernt) - den Link oben im README mitziehen. Repo auf GitHub
(`guushansen-pixel/einkaufsliste`, öffentlich): jede Änderung committen und
pushen, die APK in `dist/` gehört mit ins Repo.

Was sich nur auf dem echten Gerät verifizieren lässt: WebView-Force-Dark-
Verhalten, Zurück-Wischgeste, Touch-/Scroll-Verhalten in den Overlays
(Menü, Import, Laden-Reihenfolgen), Dateiauswahl und "Teilen" (native
Brücke `window.ElAndroid`), OCR-Dauer auf dem Handy.

## Konventionen

- Alles in `web/index.html` (HTML+CSS+JS inline), kein Framework, keine
  externen Abhängigkeiten - muss offline funktionieren. Einzige Ausnahme:
  die OCR-Bibliotheken in `web/vendor/` (lokal mitgeliefert, Quellen und
  SHA-256 in `web/vendor/README.md`). Dort nur klassische Skripte - kein
  `fetch()`, kein Worker, kein ES-Modul: die APK läuft unter
  `file:///android_asset/`, wo all das am `null`-Origin scheitert. **Den
  Origin nicht ändern** (z.B. auf einen https-Asset-Loader): localStorage
  hängt daran, Liste und Vorlage auf dem Gerät wären weg. `new-app.ps1` ohne
  `-Online` aufrufen.
- `icon.xml` liegt bewusst **neben** `web/`, nicht darin.
- localStorage-Keys sind versioniert (`el_list_v1`, `el_template_v1`,
  `el_favorites_v1`, `el_last_list_v1`, `el_storeProfiles_v1`,
  `el_settings_v1`) - bei einer Schemaänderung neue Versionsnummer statt
  stiller Migration.
- Artikel bleiben **ein einziges Freitextfeld** (Text inkl. Menge/Notiz wie
  "10x Eier", "sprite nicht zero!") - bewusste Entscheidung nach Abgleich
  mit einer echten Einkaufsliste, kein separates Mengen-/Einheitenfeld
  einführen.
- **Native `alert()`/`confirm()`/`prompt()` funktionieren in dieser WebView
  nicht** (kein `WebChromeClient` im apk-builder-Template registriert) -
  deshalb gibt es eigene Overlay-Dialoge (`confirmDialog()` /
  `textInputDialog()` in `index.html`). Neue Bestätigungen/Texteingaben
  immer darüber, nie über native Dialoge.
- Kein Netzwerkzugriff, keine KI/API-Anbindung (bewusst v1-Scope, siehe
  README "Zukünftige Phasen").

## Aktueller Stand

v1 fertig und im Browser durchgetestet (Playwright-artige Tool-Interaktion):
Kategorie-/Artikel-CRUD, Abhaken mit Sortierung ans Kategorie-Ende,
Favoriten (auto + manuell angepinnt), Vorlage-Tab mit Tap-to-Add/-Remove
und Verknüpfung zu bestehenden unverknüpften Artikeln (kein Duplikat mehr,
Bug beim ersten Testlauf gefunden und behoben), Paste-Import (Ziel Liste/
Vorlage/beides, mit Undo), Laden-Profile (anlegen/Reihenfolge bearbeiten/
anwenden), Letzte-Liste-Duplizieren, Liste leeren mit Snapshot.

v1.0 (Debug + signierte Release-APK) am 2026-09-26 gebaut und installiert.
Erstes Gerätefeedback ergab drei echte Bugs/Verbesserungen, alle behoben in
v1.1 (code 2, signiert installiert): Import-Heuristik erkannte eingerückte
Artikel mit Doppelpunkt ("Baguette:") fälschlich als Kategorie, und ein
angehängtes kleines "etc" in echten Kategorienamen ("MÜSLI BROT etc") ließ
die Großschreibungs-Erkennung fehlschlagen; Kategorie-/Artikel-Zeilen hatten
zu viele kleine Icons (jetzt ein "⋮"-Aktions-Sheet mit Textlabels); neu:
Artikel↔Kategorie hoch-/herabstufen zum manuellen Korrigieren von
Fehlklassifizierungen, plus ein Mengen-Stepper (+/-) am Artikel. Noch offen:
weiteres Gerätefeedback. Import des vollständigen Originaldokuments wurde
im Browser getestet: alle 15 echten Kategorien korrekt erkannt, 235 Artikel,
Mengen automatisch übernommen, Duplikat automatisch zusammengeführt - einzige
Restauffälligkeit sind ein paar durch die PDF-Textextraktion umgebrochene
Sätze, die als zwei Artikel ankommen (kein Parser-Bug, manuell in Sekunden
korrigierbar). v1.2 (code 3, signiert installiert): rein optisches Redesign
auf Wunsch (Schatten, Farbverläufe, Animationen, Icons), keine
Funktionsänderung. Geplant, aber bewusst nicht in v1: Sync zwischen
Geräten, KI-Import (siehe README).

v1.3 (code 4, 2026-10-17): PDF-/Bild-Import für Samsung-Notes-Exporte
(Offline-OCR, offen/abgehakt aus den Pixeln, Abgleich mit der Vorlage,
Prüfliste) plus "Teilen → Einkaufsliste". Im Browser gegen einen echten
12-Seiten-Export und einen Screenshot getestet; signierte APK in `dist/`.
Gerätetest 2026-10-17 (Pixel 11 Pro, 14-Seiten-Export): "Teilen" funktioniert,
Erkennung stimmt, aber 14 Seiten dauerten auf dem Handy spürbar lange.

v1.4 (code 5): schneller Import. Standardmäßig werden abgehakte Zeilen nicht
per OCR gelesen (Schalter "auch abgehakte Zeilen lesen"). Rohpixel gehen
direkt an Tesseract statt über PNG, das war der größte Einzelposten. Fix:
Zwei-Buchstaben-Kategorien ("TK") wurden vom Screenshot-Filter verworfen.
Desktop 12 Seiten: 11 s → ~4 s. Auf dem Handy bestätigt (2026-10-17): "geht
viel schneller".
Auch als GitHub-Release `v1.4` mit APK veröffentlicht. Künftige Versionen:
Tag pushen, Release mit `dist/`-APK als Asset anlegen.
