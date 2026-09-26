# Einkaufsliste

Offline Android-App für die Haushalts-Einkaufsliste: eine aktive Liste mit
frei anpassbaren Kategorien, ein wiederverwendbarer Vorlagen-Katalog zum
Anklicken, und laden-spezifische Kategorie-Reihenfolgen (Lidl ist anders
aufgebaut als Edeka). Reine Web-App (`web/index.html`), gebaut zur APK über
[apk-builder](../apk-builder). Build-/Testbefehle stehen in
[CLAUDE.md](CLAUDE.md).

## Hintergrund

Die App orientiert sich an einer echten, über Jahre gewachsenen
Einkaufsliste (Word-Dokument, als PDF exportiert): ca. 15 selbstgewählte
Kategorien in Großbuchstaben (PUTZEN WASCHEN etc, ÖL ESSIG etc, KÜHLREGAL,
OBST & GEMÜSE, GETRÄNKE, TK, APOTHEKE, KÖLLE ZOO, ...), darunter Artikel als
Freitext, oft mit Menge/Notiz direkt im Text ("10x Eier", "sprite nicht
zero!", "2x WC Reiniger: nicht gelb"). Daraus folgen zwei bewusste
Entscheidungen: Artikel bleiben ein einziges Freitextfeld (keine separate
Mengen-/Einheiten-Struktur), und der Paste-Import muss genau dieses Format
(GROSS/kurz = Kategorie, alles andere = Artikel) zuverlässig erkennen.

## Datenmodell

Alles in `localStorage`, ein JSON-Blob pro Key, versioniert
(`_v1`-Suffix - Schemaänderung = neue Version, keine stille Migration).

```
el_list_v1          -> aktive Liste (die gerade laufende Einkaufsrunde)
el_template_v1      -> Vorlage/Stammliste (wiederverwendbarer Katalog)
el_favorites_v1     -> Favoriten (automatisch + manuell angepinnt)
el_last_list_v1     -> Snapshot der zuletzt abgeschlossenen/geleerten Liste
el_storeProfiles_v1 -> benannte Kategorie-Reihenfolgen je Laden
el_settings_v1      -> UI-Zustand (aktiver Tab, eingeklappte Kategorien)
```

**Aktive Liste / Vorlage** (gleiche Form, Vorlage ohne `checked`/`checkedAt`):

```js
{
  schemaVersion: 1,
  updatedAt: "2026-09-26T10:00:00.000Z",
  categories: [
    {
      id: "cat_...", name: "OBST & GEMÜSE", order: 0,
      items: [
        {
          id: "item_...", text: "4x Äpfel: Pink Lady",
          checked: false, checkedAt: null,
          order: 0, createdAt: "...",
          fromTemplateId: "item_..."   // nur gesetzt, wenn per Vorlagen-Tap
                                        // hinzugefügt (siehe unten)
        }
      ]
    }
  ]
}
```

Stabile IDs + ISO-Timestamps sind bewusst schon da, damit eine spätere
Sync-Phase ohne Schema-Bruch andocken kann (siehe "Zukünftige Phasen").

**Favoriten:** `{ id, text, categoryHint, useCount, lastUsedAt, pinned }`.
`useCount` steigt bei jedem Hinzufügen (Freitext-Eingabe, Favoriten-Chip,
Vorlagen-Tap). Liste ist auf ~20 Einträge gedeckelt (angepinnte zuerst,
Rest nach `useCount`). Ein Stern-Klick an einem Listen-Artikel pinnt ihn
dauerhaft, unabhängig von `useCount`.

**Laden-Profile:** `{ id, name, categoryOrder: [Kategoriename, ...] }`.
`categoryOrder` referenziert **Namen** (case-insensitiv verglichen), nicht
IDs, damit ein Profil auch nach Reimport/Neuanlage der Kategorien noch
greift. Der Profil-Editor ergänzt beim Öffnen automatisch alle bekannten
Kategorien (aus Liste + Vorlage), die noch nicht im Profil stehen.

## Funktionen

- **Aktive Liste:** Kategorien/Artikel anlegen, umbenennen (Umbenennen auf
  einen bereits existierenden Namen merged die Artikel in die bestehende
  Kategorie), löschen, per Auf/Ab-Pfeilen sortieren. Artikel abhaken
  (wandert beim Rendern ans Ende der Kategorie, bleibt aber in der
  gespeicherten Reihenfolge unverändert), Text bearbeiten, löschen, sortieren,
  als Favorit anpinnen.
- **Vorlage (Katalog):** gleiche CRUD-Funktionen, aber ohne Checked-Status.
  Tap auf einen Vorlagen-Artikel fügt ihn der aktiven Liste hinzu (Kategorie
  wird bei Bedarf neu angelegt) - erneuter Tap entfernt ihn wieder. Wenn in
  der Zielkategorie schon ein unverknüpfter Artikel mit demselben Text
  existiert (z.B. aus einem Paste-Import), wird er nachträglich verknüpft
  statt einen zweiten, doppelten Artikel anzulegen.
- **Aus Vorlage befüllen (alles):** fügt in einem Schritt alle
  Vorlagen-Artikel hinzu, die noch nicht (verknüpft) in der aktiven Liste
  stehen.
- **Paste-Import:** Text einfügen, Ziel wählen (aktive Liste / Vorlage /
  beides), Ergebnis wird gemerged (nicht ersetzt), mit einmaligem Undo.
- **Nach Laden sortieren:** wendet die `categoryOrder` eines gespeicherten
  Profils auf die aktive Liste an; Kategorien, die im Profil fehlen, bleiben
  in ihrer bisherigen Reihenfolge am Ende.
- **Letzte Liste erneut verwenden:** ersetzt die aktive Liste durch eine
  frische, unchecked Kopie der zuletzt geleerten/abgeschlossenen Liste
  (neue IDs, `fromTemplateId`-Verknüpfungen gehen dabei bewusst verloren).
- **Liste leeren:** speichert den bisherigen Stand als "letzte Liste" und
  setzt die aktive Liste zurück.
- **Mengen-Stepper:** `+`/`-` neben jedem Artikel passt eine führende
  `Nx`-Menge im Freitext an (`parseQtyPrefix`/`formatQtyPrefix`), ohne den
  Text neu eintippen zu müssen. Bei Menge 1 verschwindet das Präfix wieder
  (passt zur echten Liste, die bei Einzelstück meist keine Zahl voranstellt).
- **Artikel/Kategorie hoch-/herabstufen:** über das "⋮"-Menü lässt sich ein
  fehlklassifizierter Artikel zu einer eigenen Kategorie machen
  (`item-promote`, wird direkt nach seiner bisherigen Kategorie eingefügt)
  oder eine fehlklassifizierte Kategorie zurück in die vorherige Kategorie
  eingliedern (`cat-demote`, ihr Name wird zur ersten Artikel-Zeile, ihre
  eigenen Artikel folgen danach). Das ist die manuelle Korrektur für Fälle,
  die die Paste-Import-Heuristik falsch einordnet.

## Paste-Import-Heuristik

Zeilenweise, in dieser Reihenfolge:

1. Leere Zeile → überspringen, ändert nichts an der aktuellen Kategorie.
2. Kategorie-Signal: Zeile ist kurz (≤30 Zeichen) UND kaum eingerückt
   (≤2 Leerzeichen, das ist das wichtigste Signal - Kategorien stehen in
   echten Listen bündig links, Artikel sind eingerückt) UND (endet auf `:`
   ODER enthält keine Kleinbuchstaben). Ein angehängtes kleines `etc` wird
   vor der Gross/Klein-Prüfung abgeschnitten, weil es in der echten
   Referenzliste an mehreren Kategorienamen hängt ("MÜSLI BROT etc"). Ohne
   die Einrückungs-Bedingung würde z.B. ein eingerücktes Artikel-Fragment
   wie "Baguette:" fälschlich zur Kategorie (realer Bug, gefunden beim
   ersten Gerätetest mit der vollen Referenzliste, siehe CLAUDE.md). Beide
   Fälle laufen über dieselbe Funktion (`isCategoryLine`), damit sich die
   Schwellenwerte an einer Stelle justieren lassen.
3. Alles andere → Artikel unter der aktuellen Kategorie. Führende
   Aufzählungszeichen (`- * • ☐ ▢`) werden abgeschnitten, Mengenangaben wie
   `10x` bleiben unangetastet (die Bullet-Regex matcht keine Ziffern).
4. Artikel-Zeile, bevor überhaupt eine Kategorie erkannt wurde → automatisch
   Kategorie "Unsortiert" (deckt reine Flach-Listen ohne Header ab).
5. Kategorien ohne Artikel werden nach dem Parsen verworfen.
6. Kategorie-Abgleich beim Import (gegen bestehende Kategorien im Ziel):
   Name wird `trim().toUpperCase()`-normalisiert verglichen.

`"ODER:"`-Marker und Personalisierungen ("für Ida") werden nicht
spezialbehandelt - sie landen als normaler Freitext, das reicht für v1.

Wer die Heuristik anpasst: gegen einen Ausschnitt der echten Referenzliste
(siehe "Hintergrund") testen, nicht nur gegen künstliche Beispiele - genau
dieses Format muss zuverlässig erkannt werden.

## Wichtige technische Falle: keine nativen Dialoge

Das apk-builder-WebView-Template registriert **keinen** `WebChromeClient`.
Ohne den tun `window.alert()`, `window.confirm()` und `window.prompt()` in
einer Android-WebView still gar nichts (kein Fehler, kein Effekt) - im
Desktop-Browser fallen sie dagegen nicht auf, weil sie dort normal
funktionieren. Deshalb hat diese App eigene Overlay-Dialoge
(`confirmDialog(message)` und `textInputDialog(title, initial)`, beide
Promise-basiert) für alles, was sonst über `confirm()`/`prompt()` liefe
(Kategorie umbenennen, Artikel bearbeiten, löschen bestätigen, Laden-Profil
anlegen/löschen). Neue Stellen, die eine Bestätigung oder Texteingabe
brauchen, müssen diese Overlays verwenden.

## Zukünftige Phasen (nicht Teil von v1)

- **Sync zwischen Geräten** (du + deine Frau): Datenmodell hat bereits
  stabile IDs und ISO-Timestamps - eine spätere Sync-Schicht kann darauf
  ein Last-Write-Wins/Merge-Verfahren aufbauen, ohne das Schema zu brechen.
- **KI/Foto-Import:** bewusst nicht in v1 (kein API-Key, kein
  Netzwerkzugriff). Der Paste-Parser liefert bereits die Zwischenstruktur
  `{categories: [{name, items: [text, ...]}]}`, die auch ein späterer
  OCR/Vision-Weg erzeugen müsste - die Merge-Funktion
  (`mergeParsedCategories`) ist absichtlich von der Text-Parse-Funktion
  (`parsePastedText`) getrennt, damit v3 nur eine neue Quelle für dieselbe
  Zwischenstruktur braucht.
