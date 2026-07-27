function Write-PCReport {
    [CmdletBinding()]
    param(
        [PSCustomObject]$Specs,
        [PSCustomObject]$Valuation,
        [PSCustomObject]$OnlineResult
    )

    $width = 52
    $line = [string]::new([char]0x2550, $width)
    $thinLine = [string]::new([char]0x2500, $width - 4)

    function Write-Line {
        param([string]$Text, [ConsoleColor]$Color = 'White')
        Write-Host $Text -ForegroundColor $Color
    }

    function Write-SpecRow {
        param([string]$Label, [string]$Value, [ConsoleColor]$ValueColor = 'White')
        $padded = $Label.PadRight(12)
        Write-Host "  $padded" -ForegroundColor DarkGray -NoNewline
        Write-Host $Value -ForegroundColor $ValueColor
    }

    function Write-ValueRow {
        param([string]$Label, [int]$Value, [bool]$IsNegative = $false, [bool]$IsBonus = $false)
        $padded = $Label.PadRight(22)
        $dots = [string]::new('.', [math]::Max(1, 22 - $Label.Length))
        $valueStr = if ($IsNegative -and $Value -ne 0) {
            "-`${0}" -f [math]::Abs($Value)
        } elseif ($IsBonus -and $Value -gt 0) {
            "+`${0}" -f $Value
        } else {
            "`${0}" -f $Value
        }
        $color = if ($IsNegative -and $Value -ne 0) { 'Red' }
                 elseif ($IsBonus -and $Value -gt 0) { 'Green' }
                 else { 'Cyan' }

        Write-Host "  $Label " -ForegroundColor Gray -NoNewline
        Write-Host "$dots " -ForegroundColor DarkGray -NoNewline
        Write-Host $valueStr.PadLeft(8) -ForegroundColor $color
    }

    # ---- Header ----
    Write-Host ""
    Write-Line "  $line" Cyan
    Write-Host ""
    Write-Host "      PC WORTH ESTIMATOR v1.0" -ForegroundColor Cyan
    Write-Host ""
    Write-Line "  $line" Cyan
    Write-Host ""

    # ---- System Summary ----
    $sysName = "$($Specs.Manufacturer) $($Specs.Model)" -replace 'System manufacturer|System Product Name|To Be Filled|Default string', '' -replace '\s+', ' '
    $sysName = $sysName.Trim()
    if (-not $sysName -or $sysName.Length -lt 3) { $sysName = "Custom PC" }

    Write-Host "  SYSTEM: " -ForegroundColor DarkGray -NoNewline
    Write-Host "$sysName ($($Specs.SystemType))" -ForegroundColor Yellow
    if ($Specs.AgeYears) {
        $ageStr = if ($Specs.AgeYears -lt 1) { "< 1 year" }
                  elseif ($Specs.AgeYears -eq 1) { "~1 year" }
                  else { "~$([math]::Round($Specs.AgeYears, 0)) years" }
        Write-Host "  AGE:    " -ForegroundColor DarkGray -NoNewline
        Write-Host "$ageStr (Manufactured: $($Specs.ManufactureDate))" -ForegroundColor Gray
    }
    Write-Host ""

    # ---- Hardware Specs ----
    Write-Host "  HARDWARE SPECS" -ForegroundColor White
    Write-Host "  $thinLine" -ForegroundColor DarkGray

    # CPU
    $cpuDisplay = "$($Specs.CPU.Name) ($($Specs.CPU.Cores)C/$($Specs.CPU.Threads)T @ $($Specs.CPU.MaxClockGHz)GHz)"
    if ($cpuDisplay.Length -gt 50) {
        $cpuName = $Specs.CPU.Name -replace '\(R\)|\(TM\)|CPU|Processor', '' -replace '\s+', ' '
        $cpuDisplay = "$($cpuName.Trim()) ($($Specs.CPU.Cores)C/$($Specs.CPU.Threads)T)"
    }
    Write-SpecRow "CPU" $cpuDisplay Cyan

    # GPU
    if ($Specs.GPU) {
        $gpuDisplay = $Specs.GPU.Name
        if ($Specs.GPU.VRAMGB -gt 0 -and -not $Specs.GPU.IsIntegrated) {
            $gpuDisplay += " ($($Specs.GPU.VRAMGB)GB)"
        }
        $gpuColor = if ($Specs.GPU.IsIntegrated) { 'Gray' } else { 'Cyan' }
        Write-SpecRow "GPU" $gpuDisplay $gpuColor
    }

    # RAM
    Write-SpecRow "RAM" "$($Specs.RAM.TotalGB) GB $($Specs.RAM.Type) @ $($Specs.RAM.SpeedMHz) MHz" Cyan

    # Storage
    foreach ($disk in $Specs.Storage) {
        $healthStr = if ($disk.Health -and $disk.Health -ne 'Unknown' -and $disk.Health -ne 'Healthy') { " [$($disk.Health)]" } else { "" }
        Write-SpecRow "Storage" "$($disk.SizeGB) GB $($disk.MediaType)$healthStr" Cyan
    }

    # Display
    Write-SpecRow "Display" $Specs.DisplayRes White

    # Battery
    if ($Specs.Battery) {
        # Health of 0 is a real reading, not a missing one, so these three
        # checks test against $null. On truthiness a flat battery printed its
        # charge instead of its health and came out green.
        $hasHealth = $null -ne $Specs.Battery.HealthPercent
        $batStr = if ($hasHealth) {
            "$($Specs.Battery.HealthPercent)% health"
        } else {
            "$($Specs.Battery.ChargePercent)% charge"
        }
        $batColor = if ($hasHealth -and $Specs.Battery.HealthPercent -lt 50) { 'Red' }
                    elseif ($hasHealth -and $Specs.Battery.HealthPercent -lt 80) { 'Yellow' }
                    else { 'Green' }
        Write-SpecRow "Battery" $batStr $batColor
    }

    # OS
    Write-SpecRow "OS" $Specs.OS White

    Write-Host ""

    # ---- Value Breakdown ----
    Write-Host "  VALUE BREAKDOWN" -ForegroundColor White
    Write-Host "  $thinLine" -ForegroundColor DarkGray

    Write-ValueRow "CPU" $Valuation.CPUValue
    Write-ValueRow "GPU" $Valuation.GPUValue
    Write-ValueRow "RAM" $Valuation.RAMValue
    Write-ValueRow "Storage" $Valuation.StorageValue

    if ($Valuation.BatteryPenalty -ne 0) {
        Write-ValueRow "Battery penalty" ([math]::Abs($Valuation.BatteryPenalty)) -IsNegative $true
    }

    if ($Valuation.Depreciation -gt 0) {
        Write-ValueRow "Age depreciation" $Valuation.Depreciation -IsNegative $true
    }

    if ($Valuation.PortabilityBonus -gt 0) {
        Write-ValueRow "Portability bonus" $Valuation.PortabilityBonus -IsBonus $true
    }

    Write-Host "                               $([string]::new([char]0x2500, 8))" -ForegroundColor DarkGray

    # ---- Estimated Value ----
    $lowStr = "`$$($Valuation.LowEstimate)"
    $highStr = "`$$($Valuation.HighEstimate)"
    Write-Host ""
    Write-Host "  ESTIMATED VALUE:  " -ForegroundColor White -NoNewline

    if ($OnlineResult -and $OnlineResult.Success) {
        # Use blended values
        $lowStr = "`$$($OnlineResult.BlendedLow)"
        $highStr = "`$$($OnlineResult.BlendedHigh)"
    }

    Write-Host "$lowStr - $highStr" -ForegroundColor Green
    Write-Host ""

    # ---- Online check ----
    if ($OnlineResult) {
        if ($OnlineResult.Success) {
            Write-Host "  Online check: " -ForegroundColor DarkGray -NoNewline
            Write-Host "~`$$($OnlineResult.OnlinePrice)" -ForegroundColor Yellow -NoNewline
            Write-Host " ($($OnlineResult.Source))" -ForegroundColor DarkGray
        } else {
            Write-Host "  Online check: " -ForegroundColor DarkGray -NoNewline
            Write-Host "No data found (using offline estimate only)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    Write-Line "  $line" Cyan
    Write-Host ""
}

Export-ModuleMember -Function Write-PCReport
