<#
.SYNOPSIS
    Read-only check of the Windows host prerequisites for tp-local.

.DESCRIPTION
    Run in Windows PowerShell or PowerShell 7 (no administrator rights needed):
        .\tp-local\scripts\host\Test-WslHost.ps1 [-Distribution Ubuntu-24.04]

    Checks that WSL is installed, that the distribution exists and runs as
    WSL 2, and reports the .wslconfig resource settings. It changes nothing.
#>
[CmdletBinding()]
param(
    [string] $Distribution = 'Ubuntu-24.04'
)

$ErrorActionPreference = 'Stop'
$failed = $false

function Write-Check([string] $Status, [string] $Message) {
    $color = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red' }[$Status]
    Write-Host ('[{0,-4}] {1}' -f $Status, $Message) -ForegroundColor $color
}

# wsl.exe writes UTF-16LE: decode it explicitly.
function Invoke-Wsl([string[]] $Arguments) {
    $previous = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $output = & wsl.exe @Arguments 2>&1
        return @{ ExitCode = $LASTEXITCODE; Lines = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) }
    }
    finally {
        [Console]::OutputEncoding = $previous
    }
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Check FAIL 'wsl.exe not found. Install WSL: wsl --install --no-distribution (administrator).'
    exit 1
}

$version = Invoke-Wsl @('--version')
if ($version.ExitCode -eq 0 -and $version.Lines.Count -gt 0) {
    Write-Check OK ("WSL present: {0}" -f $version.Lines[0])
}
else {
    Write-Check WARN 'Inbox WSL detected (no --version). Update it: wsl --update'
}

$list = Invoke-Wsl @('--list', '--verbose')
$row = $list.Lines | Where-Object { $_ -match "^\*?\s*$([regex]::Escape($Distribution))\s+" } | Select-Object -First 1
if (-not $row) {
    Write-Check FAIL "Distribution '$Distribution' not installed. Install it: wsl --install -d $Distribution"
    $failed = $true
}
else {
    $wslVersion = ($row -split '\s+')[-1]
    if ($wslVersion -eq '2') {
        Write-Check OK "Distribution '$Distribution' runs as WSL 2"
    }
    else {
        Write-Check FAIL "Distribution '$Distribution' runs as WSL $wslVersion. Convert it: wsl --set-version $Distribution 2"
        $failed = $true
    }
}

$wslConfig = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $wslConfig) {
    $settings = Get-Content $wslConfig | Where-Object { $_ -match '^\s*(memory|processors|swap|networkingMode)\s*=' }
    Write-Check OK (".wslconfig found: {0}" -f (($settings | ForEach-Object { $_.Trim() }) -join ', '))
}
else {
    Write-Check WARN '.wslconfig absent: WSL uses 50% of RAM by default. See tp-local/scripts/host/wslconfig.example'
}

if ($failed) { exit 1 }
Write-Check OK "Host ready. Next, inside WSL: sudo tp-local/scripts/wsl/prepare-wsl.sh"
