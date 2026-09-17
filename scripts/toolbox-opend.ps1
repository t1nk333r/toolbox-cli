<#
.SYNOPSIS
    Local listener that opens files sent by `open` inside the toolbox container.

.DESCRIPTION
    Run this on YOUR Windows machine, then connect with a reverse tunnel so
    that localhost:17654 inside the container points back here:

        .\scripts\toolbox-opend.ps1
        ssh -R 17654:127.0.0.1:17654 -p 2222 toolbox@<host>

    Then, inside the container:

        open report.pdf

    Binds 127.0.0.1 only, so nothing on your network can reach it — the only
    way in is the SSH reverse tunnel you created.

.PARAMETER Port
    TCP port to listen on. Default: $env:TOOLBOX_OPEN_PORT, else 17654.

.PARAMETER Once
    Serve a single file, then exit.
#>
param(
    [int]$Port = $(if ($env:TOOLBOX_OPEN_PORT) { [int]$env:TOOLBOX_OPEN_PORT } else { 17654 }),
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$MaxBytes = 512MB

function Get-SafeName([string]$raw) {
    $name = $raw.Trim() -replace "`0", ''
    $name = Split-Path -Leaf $name
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
        $name = $name.Replace($c, '_')
    }
    if ([string]::IsNullOrWhiteSpace($name)) { return 'toolbox-file' }
    return $name
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
try {
    $listener.Start()
} catch {
    Write-Error "toolbox-opend: cannot bind 127.0.0.1:${Port}: $_"
    exit 1
}

Write-Host "toolbox-opend: listening on 127.0.0.1:$Port (Ctrl-C to stop)"
Write-Host "toolbox-opend: connect with  ssh -R ${Port}:127.0.0.1:$Port -p 2222 toolbox@<host>"

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $stream.ReadTimeout = 300000

            # Read bytes up to the first newline: that is the file name.
            $headerBytes = [System.Collections.Generic.List[byte]]::new()
            $one = [byte[]]::new(1)
            while ($true) {
                if ($stream.Read($one, 0, 1) -le 0) { break }
                if ($one[0] -eq 10) { break }   # \n
                $headerBytes.Add($one[0])
                if ($headerBytes.Count -gt 8192) {
                    Write-Warning 'toolbox-opend: malformed header, dropping'
                    break
                }
            }

            $name = Get-SafeName ([System.Text.Encoding]::UTF8.GetString($headerBytes.ToArray()))
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("toolbox-open-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            $path = Join-Path $dir $name

            $fs = [System.IO.File]::Create($path)
            try {
                $buf = [byte[]]::new(65536)
                $total = 0
                while ($true) {
                    $read = $stream.Read($buf, 0, $buf.Length)
                    if ($read -le 0) { break }
                    $total += $read
                    if ($total -gt $MaxBytes) {
                        Write-Warning "toolbox-opend: $name exceeds size limit, aborting"
                        break
                    }
                    $fs.Write($buf, 0, $read)
                }
            } finally {
                $fs.Close()
            }

            Write-Host "toolbox-opend: received $name ($total bytes) -> $path"
            try {
                Start-Process $path
            } catch {
                Write-Warning "toolbox-opend: could not open ${path}: $_"
            }
        } finally {
            $client.Close()
        }

        if ($Once) { break }
    }
} finally {
    $listener.Stop()
}
