<#
.SYNOPSIS
    Baut die Einkaufsliste ueber apk-builder und patcht danach nach, was das
    WebView-Template selbst nicht kann: Datei-Import (PDF/Bild) ueber Android.
.DESCRIPTION
    apps\Einkaufsliste unter apk-builder wird bei jedem Lauf per -Force neu
    aus dem Template erzeugt - die Patches unten laufen deshalb bei jedem
    Build erneut. Throw-Guards: aendert sich das Template, bricht der Build
    laut ab statt still eine APK ohne Import zu bauen.

    Gepatcht wird:
    - Manifest: "Teilen -> Einkaufsliste" fuer PDFs und Bilder
      (ACTION_SEND), launchMode singleTask statt singleTop - sonst startet
      Android beim Teilen eine ZWEITE Instanz im Task der teilenden App, und
      die alte Instanz ueberschreibt spaeter mit ihrem veralteten Stand den
      frisch importierten localStorage.
    - MainActivity: JS-Bruecke "ElAndroid" mit pickFile() (System-
      Dateiauswahl) und getSharedFile() (Datei als Base64 abholen). Beide
      Wege lesen die Datei nativ ueber den ContentResolver - so bleibt
      setAllowContentAccess(false) im WebView unangetastet, und es braucht
      keinen WebChromeClient (der wuerde nebenbei native alert()/confirm()
      wieder einschalten).

    Mit -Release wird die signierte APK zusaetzlich als
    dist\einkaufsliste-<Version>.apk abgelegt (aeltere dist-APKs werden
    entfernt) - die liegt im Git-Repo und ist im README verlinkt.
.EXAMPLE
    .\build.ps1 -VersionName 1.3 -VersionCode 4 -Release -Install
#>
[CmdletBinding()]
param(
    [string]$VersionName = '1.3',
    [int]$VersionCode = 4,
    [switch]$Release,
    [switch]$Install
)

$ErrorActionPreference = 'Stop'

# javac lehnt eine UTF-8-BOM ab, Set-Content -Encoding utf8 schreibt in
# PowerShell 5.1 aber immer eine - deshalb ueber .NET BOM-frei schreiben.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-TextNoBom {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}
function Replace-Once {
    param([string]$Text, [string]$Needle, [string]$Replacement, [string]$What)
    $idx = $Text.IndexOf($Needle)
    if ($idx -lt 0) {
        throw "Patchziel '$What' nicht gefunden - hat sich das apk-builder-Template geaendert?"
    }
    return $Text.Substring(0, $idx) + $Replacement + $Text.Substring($idx + $Needle.Length)
}

$ProjectRoot = $PSScriptRoot
$ApkBuilder  = "D:\claude code projects\apk-builder"
$PackageId   = "com.daniel.einkaufsliste"
$AppName     = "Einkaufsliste"
$appDir      = Join-Path $ApkBuilder "apps\$AppName"

& "$ApkBuilder\new-app.ps1" -Name $AppName -PackageId $PackageId `
    -WebRoot (Join-Path $ProjectRoot 'web') `
    -Icon (Join-Path $ProjectRoot 'icon.xml') `
    -IconBackground "#1F2A1F" -Portrait `
    -VersionName $VersionName -VersionCode $VersionCode -Force

# --- AndroidManifest.xml ---------------------------------------------------
$manifestPath = Join-Path $appDir 'app\src\main\AndroidManifest.xml'
$manifest = [System.IO.File]::ReadAllText($manifestPath)

$manifest = Replace-Once $manifest 'android:launchMode="singleTop">' 'android:launchMode="singleTask">' 'launchMode'
$manifest = Replace-Once $manifest '</intent-filter>' @'
</intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="application/pdf" />
                <data android:mimeType="image/*" />
            </intent-filter>
'@.TrimEnd() 'intent-filter'

Write-TextNoBom -Path $manifestPath -Content $manifest

# --- MainActivity.java -----------------------------------------------------
$javaDir = Join-Path $appDir ("app\src\main\java\" + $PackageId.Replace('.', '\'))
$mainActivityPath = Join-Path $javaDir 'MainActivity.java'
$java = [System.IO.File]::ReadAllText($mainActivityPath)

$java = Replace-Once $java 'import android.view.KeyEvent;' @'
import android.view.KeyEvent;
import android.database.Cursor;
import android.provider.OpenableColumns;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import org.json.JSONObject;
'@.TrimEnd() 'import KeyEvent'

$java = Replace-Once $java 'webView.setWebViewClient(new LocalWebViewClient());' @'
webView.setWebViewClient(new LocalWebViewClient());

        // Datei-Import (PDF/Bild): siehe build.ps1 im Einkaufsliste-Repo.
        webView.addJavascriptInterface(new FileBridge(), "ElAndroid");
        readSharedFile(getIntent());
'@.TrimEnd() 'setWebViewClient'

$java = Replace-Once $java '    /** Haelt lokale Seiten im WebView' @'
    // ---- Datei-Import (eingefuegt von einkaufsliste\build.ps1) ----------
    private static final int REQ_PICK_FILE = 4711;
    private static final int MAX_FILE_BYTES = 40 * 1024 * 1024;
    private final Object pendingLock = new Object();
    private String pendingFileJson = null;

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (readSharedFile(intent)) notifyWebFileReady();
    }

    @SuppressWarnings("deprecation")
    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQ_PICK_FILE || resultCode != RESULT_OK || data == null) return;
        Uri uri = data.getData();
        if (uri != null && readUri(uri, data.getType())) notifyWebFileReady();
    }

    private void notifyWebFileReady() {
        webView.evaluateJavascript("window.elCheckSharedFile && window.elCheckSharedFile()", null);
    }

    @SuppressWarnings("deprecation")
    private boolean readSharedFile(Intent intent) {
        if (intent == null || !Intent.ACTION_SEND.equals(intent.getAction())) return false;
        Uri uri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
        // Nur einmal verarbeiten, auch wenn die Activity neu erzeugt wird.
        setIntent(new Intent(Intent.ACTION_MAIN));
        return uri != null && readUri(uri, intent.getType());
    }

    private boolean readUri(Uri uri, String mimeHint) {
        try {
            String mime = getContentResolver().getType(uri);
            if (mime == null) mime = mimeHint;
            String name = null;
            Cursor c = getContentResolver().query(uri, new String[] { OpenableColumns.DISPLAY_NAME }, null, null, null);
            if (c != null) {
                try { if (c.moveToFirst()) name = c.getString(0); } finally { c.close(); }
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            InputStream in = getContentResolver().openInputStream(uri);
            if (in == null) throw new java.io.IOException("kein Stream");
            try {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) {
                    out.write(buf, 0, n);
                    if (out.size() > MAX_FILE_BYTES) throw new java.io.IOException("Datei zu gross");
                }
            } finally {
                in.close();
            }
            JSONObject o = new JSONObject();
            o.put("name", name == null ? "" : name);
            o.put("mime", mime == null ? "" : mime);
            o.put("b64", Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP));
            synchronized (pendingLock) { pendingFileJson = o.toString(); }
            return true;
        } catch (Exception e) {
            Toast.makeText(this, "Datei konnte nicht gelesen werden", Toast.LENGTH_LONG).show();
            return false;
        }
    }

    /** Von der Web-App aus erreichbar als window.ElAndroid. */
    private class FileBridge {
        @JavascriptInterface
        public String getSharedFile() {
            synchronized (pendingLock) {
                String s = pendingFileJson;
                pendingFileJson = null;
                return s == null ? "" : s;
            }
        }

        @JavascriptInterface
        public void pickFile() {
            runOnUiThread(new Runnable() {
                @SuppressWarnings("deprecation")
                @Override
                public void run() {
                    Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                    i.addCategory(Intent.CATEGORY_OPENABLE);
                    i.setType("*/*");
                    i.putExtra(Intent.EXTRA_MIME_TYPES, new String[] { "application/pdf", "image/*" });
                    try {
                        startActivityForResult(i, REQ_PICK_FILE);
                    } catch (ActivityNotFoundException e) {
                        Toast.makeText(MainActivity.this, "Keine Dateiauswahl verfuegbar", Toast.LENGTH_SHORT).show();
                    }
                }
            });
        }
    }

    /** Haelt lokale Seiten im WebView
'@ 'LocalWebViewClient-Kommentar'

Write-TextNoBom -Path $mainActivityPath -Content $java

Write-Host "  [ok] Patches angewendet (Teilen-Intent, singleTask, Datei-Bruecke)" -ForegroundColor Green

$buildArgs = @{ App = $AppName }
if ($Release) { $buildArgs.Release = $true }
if ($Install) { $buildArgs.Install = $true }
& "$ApkBuilder\build-apk.ps1" @buildArgs

if ($Release) {
    $latest = Get-ChildItem (Join-Path $ApkBuilder 'out') -Filter "$AppName-release-*.apk" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "Keine Release-APK in apk-builder\out gefunden" }
    $dist = Join-Path $ProjectRoot 'dist'
    if (-not (Test-Path $dist)) { New-Item -ItemType Directory -Path $dist | Out-Null }
    Get-ChildItem $dist -Filter 'einkaufsliste-*.apk' | Remove-Item -Force
    $target = Join-Path $dist "einkaufsliste-$VersionName.apk"
    Copy-Item $latest.FullName $target -Force
    Write-Host "  [ok] $target" -ForegroundColor Green
}
