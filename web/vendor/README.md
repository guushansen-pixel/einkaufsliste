# Vendored Bibliotheken (offline, fuer den PDF-/Bild-Import)

Werden erst beim ersten PDF-Import per `<script>`-Tag nachgeladen. Bewusst
alles als klassische Skripte, kein `fetch()`, kein Worker, kein ES-Modul:
die APK laedt die App unter `file:///android_asset/`, dort scheitern
`fetch()`, `new Worker(url)` und `<script type=module>` am `null`-Origin.

| Datei | Quelle | SHA-256 |
|---|---|---|
| `pdf.min.js` | npm `pdfjs-dist@3.11.174`, `legacy/build/` | `978fd1b2d134a98e98966186a97777bebf87d8e770dadab1ece3687e21a5aa6c` |
| `pdf.worker.min.js` | npm `pdfjs-dist@3.11.174`, `legacy/build/` | `38cde5311957b86bc3669f93e7d2566de333a90055ed6635bef60d9bf00e96f2` |
| `tesseract-core-simd-lstm.wasm.js` | npm `tesseract.js-core@5.1.1` (wasm als Base64 eingebettet) | `ce20eda9533cbed1e6c2b4276fbae1e0adc61b6754b5513084be601787b457cf` |
| `deu.traineddata.js` | `deu.traineddata` aus github.com/tesseract-ocr/tessdata_fast (main, 2026-10-17), als Base64 in `window.EL_DEU_TRAINEDDATA_B64` verpackt | Original: `19d219bbb6672c869d20a9636c6816a81eb9a71796cb93ebe0cb1530e2cdb22d` |

Warum pdf.js 3.x und nicht 4.x: ab 4.0 gibt es nur noch ES-Module (`.mjs`).
3.11.174 hat CVE-2024-4367 (Code-Ausfuehrung ueber praeparierte Fonts) -
abgeschaltet ueber `isEvalSupported: false` beim Laden, wie vom pdf.js-Team
als Workaround empfohlen. pdf.js laeuft ohne Worker: `pdf.worker.min.js` wird
als normales Skript geladen und setzt `globalThis.pdfjsWorker`, das pdf.js
dann direkt im Hauptthread nutzt.

Tesseract: es wird nur der Emscripten-Kern genutzt (`TessBaseAPI` direkt),
nicht der `tesseract.js`-Wrapper - der braucht zwingend einen Web Worker.
Lizenzen: `LICENSE.pdfjs` (Apache 2.0), `LICENSE.tesseract-core` (Apache 2.0);
tessdata ist ebenfalls Apache 2.0.
