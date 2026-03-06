#!/usr/bin/env pwsh
# Creates and pushes a new release tag based on current date.
# Version format: YY.M.D or YY.M.D.B if the base tag already exists.
#
# Usage:
#   .\scripts\release.ps1               # interactive
#   .\scripts\release.ps1 -DryRun       # show tag without creating it
#   .\scripts\release.ps1 -NoPause      # skip "press any key" at the end

param(
    [switch]$DryRun,
    [switch]$NoPause
)

function Exit-WithPause {
    param([int]$ExitCode = 0)
    if (-not $NoPause) {
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit $ExitCode
}

# Build base version from current date (no leading zeros)
$now = Get-Date
$year = $now.ToString("yy")
$month = $now.Month
$day = $now.Day
$baseVersion = "$year.$month.$day"

Write-Host "Determining release version..." -ForegroundColor Cyan
Write-Host "Base version: $baseVersion" -ForegroundColor Gray

# Fetch all tags from remote
Write-Host "Fetching tags from remote..." -ForegroundColor Gray
git fetch --tags 2>$null

# Collect existing tags (strip 'v' prefix for comparison)
$allTags = git tag -l | ForEach-Object { $_.Trim() -replace '^v', '' } | Where-Object { $_ -ne '' }

function Test-TagExists([string]$tag) {
    return $allTags -contains $tag
}

# Determine final version — increment build number if base already exists
$version = $baseVersion
if (Test-TagExists $version) {
    Write-Host "Tag 'v$version' already exists, checking build numbers..." -ForegroundColor Yellow
    $build = 1
    while (Test-TagExists "$baseVersion.$build") {
        $build++
    }
    $version = "$baseVersion.$build"
    Write-Host "Found available version: $version (build #$build)" -ForegroundColor Green
} else {
    Write-Host "Version '$version' is available" -ForegroundColor Green
}

$tag = "v$version"

Write-Host ""
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Release version: $tag" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN: Would create and push tag '$tag'" -ForegroundColor Yellow
    Exit-WithPause 0
}

# Confirm with user (default is Yes)
Write-Host "Create and push tag '$tag'? [Y/n]: " -NoNewline -ForegroundColor Yellow
$confirmation = Read-Host
if ($confirmation -eq 'n' -or $confirmation -eq 'N') {
    Write-Host "Release cancelled" -ForegroundColor Yellow
    Exit-WithPause 0
}

# Warn about uncommitted changes
$status = git status --porcelain
if ($status) {
    Write-Host ""
    Write-Host "WARNING: You have uncommitted changes:" -ForegroundColor Yellow
    Write-Host $status
    Write-Host ""
    $proceed = Read-Host "Continue anyway? [y/N]"
    if ($proceed -ne 'y' -and $proceed -ne 'Y') {
        Write-Host "Release cancelled" -ForegroundColor Yellow
        Exit-WithPause 0
    }
}

# Create tag
Write-Host ""
Write-Host "Creating tag '$tag'..." -ForegroundColor Cyan
git tag -a $tag -m "Release $tag"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create tag" -ForegroundColor Red
    Exit-WithPause 1
}
Write-Host "Tag created successfully" -ForegroundColor Green

# Push tag
Write-Host "Pushing tag to remote..." -ForegroundColor Cyan
git push origin $tag
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to push tag" -ForegroundColor Red
    Write-Host "You can manually push it later with: git push origin $tag" -ForegroundColor Yellow
    Exit-WithPause 1
}

Write-Host ""
Write-Host "==================================" -ForegroundColor Green
Write-Host "Release $tag created successfully!" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Green
Write-Host ""
Write-Host "GitHub Actions will now build and publish the release." -ForegroundColor Cyan
Write-Host "Check progress at: https://github.com/powertech-center/crossler/actions" -ForegroundColor Cyan
Write-Host ""

Exit-WithPause 0
