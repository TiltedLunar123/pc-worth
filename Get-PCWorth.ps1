<#
.SYNOPSIS
    Estimates the current market value of your PC based on its hardware specs.

.DESCRIPTION
    Automatically detects CPU, GPU, RAM, storage, battery health, and system age,
    then calculates an estimated resale value using a built-in pricing database.
    Optionally checks online sold listings to refine the estimate.

.PARAMETER SkipOnline
    Skip the online price lookup and use offline estimates only.

.EXAMPLE
    .\Get-PCWorth.ps1
    Runs full analysis with online lookup.

.EXAMPLE
    .\Get-PCWorth.ps1 -SkipOnline
    Runs offline-only analysis.

.EXAMPLE
    .\Get-PCWorth.ps1 -Verbose
    Runs with detailed progress output.

.LINK
    https://github.com/hilge/pc-worth
#>

[CmdletBinding()]
param(
    [switch]$SkipOnline
)

$ErrorActionPreference = 'Stop'

# Import modules
$modulePath = Join-Path $PSScriptRoot 'modules'
Import-Module (Join-Path $modulePath 'HardwareDetection.psm1') -Force
Import-Module (Join-Path $modulePath 'Valuation.psm1') -Force
Import-Module (Join-Path $modulePath 'OnlineLookup.psm1') -Force
Import-Module (Join-Path $modulePath 'ReportFormatter.psm1') -Force

# Step 1: Detect hardware
Write-Host "`n  Scanning hardware..." -ForegroundColor DarkGray
$specs = Get-HardwareSpecs -Verbose:$VerbosePreference

# Step 2: Calculate value
Write-Host "  Calculating value..." -ForegroundColor DarkGray
$valuation = Get-PCValuation -Specs $specs -Verbose:$VerbosePreference

# Step 3: Optional online lookup
$onlineResult = $null
if (-not $SkipOnline) {
    Write-Host "  Checking online prices..." -ForegroundColor DarkGray
    $onlineResult = Get-OnlineEstimate -Specs $specs -OfflineValuation $valuation -Verbose:$VerbosePreference
}

# Step 4: Display report
Write-PCReport -Specs $specs -Valuation $valuation -OnlineResult $onlineResult
