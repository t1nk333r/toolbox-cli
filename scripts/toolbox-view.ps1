<#
.SYNOPSIS
    Open a file from the remote toolbox container in your LOCAL Windows environment.

.DESCRIPTION
    Streams a file off the toolbox container over SSH
    and opens it with the Windows default application. Nothing is installed on the
    container. Images can render inline when run inside a graphics-capable terminal
    (WezTerm via `wezterm imgcat`); otherwise the file is downloaded and opened.

    Requires the OpenSSH client that ships with Windows 10/11 (ssh.exe on PATH).

.PARAMETER RemotePath
    Absolute path of the file inside the container, e.g. /mnt/tank/docs/report.pdf

.PARAMETER SshHost
    SSH destination. Default: $env:TOOLBOX_HOST, else toolbox@10.10.10.9

.PARAMETER Port
    SSH port. Default: $env:TOOLBOX_PORT, else 2222

.PARAMETER Identity
    Optional SSH identity file.

.PARAMETER Download
    Force download+open even for images (skip inline rendering).

.EXAMPLE
    .\toolbox-view.ps1 /mnt/tank/pics/photo.png

.EXAMPLE
    .\toolbox-view.ps1 -SshHost toolbox@nas.local -Port 2222 /mnt/tank/docs/report.pdf
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RemotePath,
    [string]$SshHost = $(if ($env:TOOLBOX_HOST) { $env:TOOLBOX_HOST } else { 'toolbox@10.10.10.9' }),
    [int]$Port = $(if ($env:TOOLBOX_PORT) { [int]$env:TOOLBOX_PORT } else { 2222 }),
    [string]$Identity,
    [switch]$Download
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Error "ssh.exe not found. Install the Windows OpenSSH client (Settings > Optional features)."
    exit 1
}

$sshArgs = @('-p', "$Port")
if ($Identity) { $sshArgs += @('-i', $Identity) }
$sshArgs += $SshHost

$base = Split-Path -Leaf $RemotePath
$ext  = [System.IO.Path]::GetExtension($base).TrimStart('.').ToLower()
$imageExt = @('png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'tiff', 'tif', 'avif', 'heic')
$isImage = $imageExt -contains $ext

# Inline rendering only inside WezTerm, which ships imgcat on Windows.
if (-not $Download -and $isImage -and $env:WEZTERM_PANE -and (Get-Command wezterm -ErrorAction SilentlyContinue)) {
    & ssh @sshArgs "cat -- '$RemotePath'" | wezterm imgcat
    exit 0
}

# Download to a temp file, then open with the default Windows application.
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("toolbox-view-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$local = Join-Path $tmp $base

# Use scp for a clean binary copy (avoids PowerShell pipeline byte mangling).
$scpArgs = @('-P', "$Port")
if ($Identity) { $scpArgs += @('-i', $Identity) }
$scpArgs += @("${SshHost}:$RemotePath", $local)
& scp @scpArgs

if (Test-Path $local) {
    Start-Process $local
    Write-Host "toolbox-view: opened $base ($local)"
} else {
    Write-Error "toolbox-view: download failed for $RemotePath"
    exit 1
}
