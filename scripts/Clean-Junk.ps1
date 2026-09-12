<#
.SYNOPSIS
    Safe Windows cache and junk-file cleaner with a dry-run default.

.DESCRIPTION
    Reports how much space each cleanup category would reclaim, then deletes
    only the categories you approve. Deletes NOTHING unless -Run is supplied.

    Design principles:
      * Dry run by default. Nothing is touched without -Run.
      * Every category is previewed with its size before any deletion.
      * Files in use are skipped rather than forced, so the profile is safe.
      * No registry cleaning. Ever. It reclaims ~0 MB and can break Windows.

.PARAMETER Run
    Actually delete. Without this switch the script only measures and reports.

.PARAMETER IncludeRecycleBin
    Also empty the Recycle Bin. Off by default so you can still change your mind.

.PARAMETER IncludeAppCaches
    Also clear third-party app caches (Teams, Slack, Spotify, Discord, npm,
    pip, NuGet, etc.). These re-download on next launch — slower first start.

.PARAMETER IncludeWindowsUpdateCache
    Also clear C:\Windows\SoftwareDistribution\Download. Requires stopping
    wuauserv and bits first; the script does this and restarts them.

.PARAMETER IncludeDism
    Also run DISM /StartComponentCleanup to shrink WinSxS. This is the biggest
    single win (commonly 5-15 GB) but takes 10-40 minutes and is NOT reversible
    (you lose the ability to uninstall previously installed updates).

.PARAMETER IncludeHibernation
    Also disable the hibernation file (hiberfil.sys), reclaiming roughly your
    RAM size. You lose hibernate and Fast Startup.

.EXAMPLE
    # Report only — safe, read-only
    .\Clean-Junk.ps1

.EXAMPLE
    # Interactive wipe of the safe categories
    .\Clean-Junk.ps1 -Run

.EXAMPLE
    # Everything except the irreversible DISM step
    .\Clean-Junk.ps1 -Run -IncludeRecycleBin -IncludeAppCaches -IncludeWindowsUpdateCache

.NOTES
    Requires PowerShell 5.1+ and, for the machine-wide steps, an elevated shell.
    Review the script before running it. Back up anything irreplaceable first.
#>

[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$IncludeRecycleBin,
    [switch]$IncludeAppCaches,
    [switch]$IncludeWindowsUpdateCache,
    [switch]$IncludeDism,
    [switch]$IncludeHibernation
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------- helpers ----

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-EntrySize {
    param([string[]]$Path)
    $sum = 0
    foreach ($p in $Path) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($item -and -not $item.PSIsContainer) {
            $sum += $item.Length
            continue
        }
        $sum += (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
    }
    return [int64]$sum
}

function Format-Size {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

# Categories are declared up front so the whole run can be measured and shown
# as one report before a single file is touched.
$appCachePaths = @(
    "$env:LOCALAPPDATA\Microsoft\Teams\Cache"
    "$env:LOCALAPPDATA\Microsoft\Teams\GPUCache"
    "$env:APPDATA\Slack\Cache"
    "$env:APPDATA\Slack\Code Cache"
    "$env:LOCALAPPDATA\Spotify\Storage"
    "$env:APPDATA\discord\Cache"
    "$env:APPDATA\discord\Code Cache"
    "$env:LOCALAPPDATA\pip\Cache"
    "$env:LOCALAPPDATA\npm-cache"
    "$env:USERPROFILE\.nuget\packages"
    "$env:LOCALAPPDATA\Yarn\Cache"
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
)

$categories = [ordered]@{
    'User temp files'          = @($env:TEMP)
    'Windows temp files'       = @("$env:SystemRoot\Temp")
    'Windows error reports'    = @("$env:ProgramData\Microsoft\Windows\WER\ReportQueue", "$env:ProgramData\Microsoft\Windows\WER\ReportArchive")
    'Thumbnail & icon cache'   = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer")
    'DirectX shader cache'     = @("$env:LOCALAPPDATA\D3DSCache")
    'Delivery Optimization'    = @("$env:SystemRoot\SoftwareDistribution\DeliveryOptimization")
    'Windows Update downloads' = @("$env:SystemRoot\SoftwareDistribution\Download")
    'Crash dumps'              = @("$env:LOCALAPPDATA\CrashDumps", "$env:SystemRoot\Minidump", "$env:SystemRoot\LiveKernelReports")
}

if ($IncludeAppCaches) { $categories['Third-party app caches'] = $appCachePaths }

# ------------------------------------------------------------- 1. measure ----

if (-not (Test-Admin)) {
    Write-Warning 'Not elevated. Machine-wide paths (Windows\Temp, WinSxS, Update cache) will be skipped or fail.'
}

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host '  Windows junk-file report' -ForegroundColor Cyan
if (-not $Run) { Write-Host '  DRY RUN - nothing will be deleted' -ForegroundColor Yellow }
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host ''

$report = [ordered]@{}
foreach ($name in $categories.Keys) {
    if ($name -eq 'Thumbnail & icon cache') {
        # Measure only the cache databases, not the whole Explorer data folder.
        $report[$name] = (Get-ChildItem -LiteralPath "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" `
                            -Force -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -like 'thumbcache_*.db' -or $_.Name -like 'iconcache_*.db' } |
                          Measure-Object -Property Length -Sum).Sum
        if (-not $report[$name]) { $report[$name] = 0 }
        continue
    }
    $report[$name] = Get-EntrySize -Path $categories[$name]
}

if ($IncludeRecycleBin) {
    $report['Recycle Bin'] = Get-EntrySize -Path @("$env:SystemDrive\`$Recycle.Bin")
}
if ($IncludeHibernation) {
    $hiber = Get-Item "$env:SystemDrive\hiberfil.sys" -Force -ErrorAction SilentlyContinue
    if ($hiber) { $report['Hibernation file (hiberfil.sys)'] = $hiber.Length }
}

$total = 0
foreach ($name in $report.Keys) {
    $size = $report[$name]
    $total += $size
    '  {0,-28} {1,12}' -f $name, (Format-Size $size) | Write-Host
}
Write-Host ''
'  {0,-28} {1,12}' -f 'TOTAL RECLAIMABLE', (Format-Size $total) | Write-Host -ForegroundColor Green

if ($IncludeDism) {
    Write-Host ''
    Write-Host '  DISM WinSxS cleanup is enabled and will run separately (10-40 min).' -ForegroundColor Yellow
    Write-Host '  Not reversible: previously installed updates can no longer be removed.' -ForegroundColor Yellow
}

Write-Host ''
if (-not $Run) {
    Write-Host 'Dry run complete. Re-run with -Run to delete the safe categories.' -ForegroundColor Cyan
    Write-Host 'Add -IncludeRecycleBin -IncludeAppCaches -IncludeWindowsUpdateCache for more.' -ForegroundColor Cyan
    Write-Host ''
    exit 0
}

# --------------------------------------------------------- 2. confirmation ---

$answer = Read-Host 'Proceed with deletion of the categories above? Type Y to continue'
if ($answer -notmatch '^[Yy]') { Write-Host 'Aborted. Nothing was deleted.' -ForegroundColor Yellow; exit 1 }

# ----------------------------------------------------------- 3. the wiping ---

function Clear-PathContents {
    <#
        Deletes the CONTENTS of a path, never the path itself. Files in use are
        skipped rather than forced, so a live profile is not damaged.

        Safety guards:
          * Never operates on a drive root.
          * Skips reparse points (junctions / symlinks) entirely. Recursing
            through a junction can delete data outside the intended target --
            the classic cleaner disaster.
          * Optional -NameLike limits deletion to matching filename patterns,
            so shared folders are filtered rather than emptied wholesale.
    #>
    param(
        [string]$Path,
        [string]$Label,
        [string[]]$NameLike
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($Path.TrimEnd('\') -eq $env:SystemDrive) { return }

    Write-Host ("  cleaning: {0}" -f $Label) -ForegroundColor DarkGray
    $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
             Where-Object {
                 $_.Name -ne 'desktop.ini' -and
                 -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
             }

    if ($NameLike) {
        $items = $items | Where-Object {
            $n = $_.Name
            ($NameLike | Where-Object { $n -like $_ }).Count -gt 0
        }
    }

    foreach ($item in $items) {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host 'Cleaning...' -ForegroundColor Cyan
Write-Host ''

# Stop explorer briefly for the thumbnail cache, then restart it.
$explorerStopped = $false
if ($report.Contains('Thumbnail & icon cache') -and $report['Thumbnail & icon cache'] -gt 0) {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $explorerStopped = $true
}

foreach ($name in $categories.Keys) {
    if ($name -eq 'Windows Update downloads' -and -not $IncludeWindowsUpdateCache) { continue }
    foreach ($path in $categories[$name]) {
        if (Test-Path -LiteralPath $path) {
            # Shared folders get filtered instead of emptied: the Explorer data
            # folder holds more than cache, so only the cache DBs are removed.
            $nameLike = $null
            if ($name -eq 'Thumbnail & icon cache') {
                $nameLike = @('thumbcache_*.db', 'iconcache_*.db')
            }
            Clear-PathContents -Path $path -Label "$name -> $path" -NameLike $nameLike
        }
    }
}

if ($explorerStopped) {
    Start-Process explorer.exe -ErrorAction SilentlyContinue
    Write-Host '  Explorer restarted.' -ForegroundColor DarkGray
}

if ($IncludeRecycleBin) {
    Write-Host '  emptying: Recycle Bin' -ForegroundColor DarkGray
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
}

if ($IncludeWindowsUpdateCache) {
    Write-Host '  stopping: Windows Update services' -ForegroundColor DarkGray
    Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Clear-PathContents -Path "$env:SystemRoot\SoftwareDistribution\Download" -Label 'Windows Update download cache'
    Start-Service wuauserv, bits -ErrorAction SilentlyContinue
    Write-Host '  Windows Update services restarted.' -ForegroundColor DarkGray
}

if ($IncludeDism) {
    Write-Host ''
    Write-Host '  Running DISM component cleanup. This can take 10-40 minutes...' -ForegroundColor Yellow
    & dism.exe /Online /Cleanup-Image /StartComponentCleanup
}

if ($IncludeHibernation) {
    Write-Host '  disabling: hibernation (removes hiberfil.sys)' -ForegroundColor DarkGray
    & powercfg.exe /hibernate off
}

# ------------------------------------------------------------- 4. summary ---

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host '  Done.' -ForegroundColor Green
Write-Host '========================================================' -ForegroundColor Cyan

$free = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
if ($free) {
    '  Free space now on {0}: {1}' -f $env:SystemDrive, (Format-Size $free.Free) | Write-Host
}
Write-Host ''
Write-Host 'Recommended follow-ups (not automated here):' -ForegroundColor Cyan
Write-Host '  * Settings > System > Storage > Storage Sense - enable automatic cleanup'
Write-Host '  * WizTree or TreeSize Free - find the large files a cleaner cannot remove'
Write-Host '  * Do NOT run a registry cleaner as a follow-up. It frees nothing.'
Write-Host ''
