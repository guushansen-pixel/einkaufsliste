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

APK bauen:

```powershell
cd "D:\claude code projects\apk-builder"
.\new-app.ps1 -Name Einkaufsliste -PackageId com.daniel.einkaufsliste `
              -WebRoot "D:\claude code projects\einkaufsliste\web" `
              -Icon "D:\claude code projects\einkaufsliste\icon.xml" `
              -IconBackground "#1F2A1F" -Portrait `
              -VersionName "1.0" -VersionCode <hochzaehlen> -Force
.\build-apk.ps1 -App Einkaufsliste          # Debug
.\build-apk.ps1 -App Einkaufsliste -Release # signiert, fuer echten Gebrauch
```

Was sich nur auf dem echten Gerät verifizieren lässt: WebView-Force-Dark-
Verhalten, Zurück-Wischgeste, Touch-/Scroll-Verhalten in den Overlays
(Menü, Import, Laden-Reihenfolgen).

## Konventionen

- Alles in `web/index.html` (HTML+CSS+JS inline), kein Framework, keine
  externen Abhängigkeiten - muss offline funktionieren. `new-app.ps1` ohne
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

Noch nicht gebaut/getestet: Debug-APK auf echtem Gerät. Geplant, aber
bewusst nicht in v1: Sync zwischen Geräten, KI/Foto-Import (siehe README).
