<#
.SYNOPSIS
    Winziger statischer Webserver fuer web\ - zum Testen im Browser.
.DESCRIPTION
    Die App MUSS ueber http getestet werden, nicht per file://: Browser
    schalten localStorage fuer file://-Seiten still ab, und dann verschwindet
    jede Liste beim Neuladen, ohne dass ein Fehler erscheint.

    Auf diesem Rechner gibt es weder Python noch Node, deshalb ein eigener
    Server auf Basis von System.Net.Sockets (wie bei vokabeltrainer/
    latein-trainer) - HttpListener braucht je nach Windows-Konfiguration eine
    URL-Reservierung mit Administratorrechten, ein roher TcpListener nicht.

    Mit Strg+C beenden.
.EXAMPLE
    .\tools\serve.ps1
    .\tools\serve.ps1 -Port 8101
#>
[CmdletBinding()]
param(
    [int]$Port = 8101
)

$ErrorActionPreference = 'Stop'

$root = Join-Path (Split-Path -Parent $PSScriptRoot) 'web'
if (-not (Test-Path $root)) { throw "web\ nicht gefunden unter $root" }

$types = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.svg'  = 'image/svg+xml'
    '.png'  = 'image/png'
    '.ico'  = 'image/x-icon'
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Host "  Einkaufsliste laeuft auf http://localhost:$Port/  (Strg+C beendet)" -ForegroundColor Green

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream)

            $requestLine = $reader.ReadLine()
            if (-not $requestLine) { $client.Close(); continue }
            while ($reader.Peek() -ge 0) {
                $h = $reader.ReadLine()
                if ($h -eq '' -or $null -eq $h) { break }
            }

            $parts = $requestLine -split ' '
            $path  = if ($parts.Count -ge 2) { $parts[1] } else { '/' }
            $path  = ($path -split '\?')[0]
            if ($path -eq '/') { $path = '/index.html' }

            $rel  = $path.TrimStart('/') -replace '/', '\'
            $file = Join-Path $root $rel

            $full = [System.IO.Path]::GetFullPath($file)
            $base = [System.IO.Path]::GetFullPath($root)
            if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $full -PathType Leaf)) {
                $body   = [System.Text.Encoding]::UTF8.GetBytes("404 - $path")
                $header = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
                Write-Host "  404 $path" -ForegroundColor DarkYellow
            } else {
                $body = [System.IO.File]::ReadAllBytes($full)
                $ext  = [System.IO.Path]::GetExtension($full).ToLower()
                $ct   = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
                $header = "HTTP/1.1 200 OK`r`nContent-Type: $ct`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
                Write-Host "  200 $path" -ForegroundColor DarkGray
            }

            $hb = [System.Text.Encoding]::ASCII.GetBytes($header)
            $stream.Write($hb, 0, $hb.Length)
            $stream.Write($body, 0, $body.Length)
            $stream.Flush()
        } catch {
            Write-Host "  [warn] $($_.Exception.Message)" -ForegroundColor DarkYellow
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}
