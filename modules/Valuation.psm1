function Get-CPUValue {
    [CmdletBinding()]
    param([PSCustomObject]$CPU)

    $name = $CPU.Name.ToUpper()

    # Detect generation for Intel
    $intelGen = 0
    if ($name -match 'I[3579]-(\d{2,5})') {
        $modelNum = $Matches[1]
        if ($modelNum.Length -ge 4) {
            $intelGen = [int]$modelNum.Substring(0, [math]::Min(2, $modelNum.Length))
            if ($intelGen -gt 20) { $intelGen = [int]$modelNum[0].ToString() }
        } elseif ($modelNum.Length -eq 3) {
            $intelGen = [int]$modelNum[0].ToString()
        }
    }
    # Core Ultra detection
    if ($name -match 'ULTRA\s*(\d)') { $intelGen = 14 + [int]$Matches[1] }

    # Detect generation for AMD. Ryzen series numbers run 1000-9000 while Intel
    # counts 1-14, so the series digit is mapped onto the Intel generation it
    # launched against before the shared multiplier below sees it.
    $amdGen = 0
    if ($name -match 'RYZEN\s*(?:\d\s+)?(?:PRO\s+)?(\d)\d{3}') {
        $amdGen = switch ([int]$Matches[1]) {
            1 { 7 }    # Zen, 2017
            2 { 8 }    # Zen+, 2018
            3 { 9 }    # Zen 2, 2019
            4 { 10 }   # Zen 2 mobile/APU, 2020
            5 { 11 }   # Zen 3, 2020
            6 { 12 }   # Zen 3+ mobile, 2022
            7 { 13 }   # Zen 4, 2022
            8 { 14 }   # Zen 4 APU, 2024
            9 { 15 }   # Zen 5, 2024
            default { 0 }
        }
    }

    # Base value by tier
    $baseValue = 0
    if ($name -match 'I9|RYZEN\s*9') { $baseValue = 300 }
    elseif ($name -match 'I7|RYZEN\s*7') { $baseValue = 200 }
    elseif ($name -match 'I5|RYZEN\s*5') { $baseValue = 120 }
    elseif ($name -match 'I3|RYZEN\s*3') { $baseValue = 60 }
    elseif ($name -match 'ULTRA\s*9') { $baseValue = 350 }
    elseif ($name -match 'ULTRA\s*7') { $baseValue = 250 }
    elseif ($name -match 'ULTRA\s*5') { $baseValue = 160 }
    elseif ($name -match 'PENTIUM|CELERON|ATHLON') { $baseValue = 30 }
    elseif ($name -match 'XEON') { $baseValue = 250 }
    elseif ($name -match 'APPLE\s*M3\s*MAX') { $baseValue = 400 }
    elseif ($name -match 'APPLE\s*M3\s*PRO') { $baseValue = 300 }
    elseif ($name -match 'APPLE\s*M[1234]') { $baseValue = 200 }
    else { $baseValue = 80 }

    # Generation multiplier
    $gen = [math]::Max($intelGen, $amdGen)
    $genMultiplier = if ($gen -ge 14) { 1.4 }
    elseif ($gen -ge 12) { 1.2 }
    elseif ($gen -ge 10) { 1.0 }
    elseif ($gen -ge 8) { 0.8 }
    elseif ($gen -ge 6) { 0.6 }
    elseif ($gen -ge 4) { 0.4 }
    elseif ($gen -ge 1) { 0.3 }
    else { 0.7 }

    $value = [math]::Round($baseValue * $genMultiplier, 0)
    return $value
}

function Get-GPUValue {
    [CmdletBinding()]
    param([PSCustomObject]$GPU)

    if (-not $GPU -or $GPU.IsIntegrated) { return 0 }

    $name = $GPU.Name.ToUpper()

    # NVIDIA RTX 40 series
    $gpuPrices = @{
        # RTX 50 series
        'RTX\s*5090' = 1200; 'RTX\s*5080' = 700; 'RTX\s*5070\s*TI' = 500; 'RTX\s*5070' = 400; 'RTX\s*5060\s*TI' = 300; 'RTX\s*5060' = 220
        # RTX 40 series
        'RTX\s*4090' = 800; 'RTX\s*4080\s*SUPER' = 550; 'RTX\s*4080' = 500; 'RTX\s*4070\s*TI\s*SUPER' = 400
        'RTX\s*4070\s*TI' = 350; 'RTX\s*4070\s*SUPER' = 330; 'RTX\s*4070' = 280; 'RTX\s*4060\s*TI' = 220
        'RTX\s*4060' = 180; 'RTX\s*4050' = 150
        # RTX 30 series
        'RTX\s*3090\s*TI' = 450; 'RTX\s*3090' = 400; 'RTX\s*3080\s*TI' = 330; 'RTX\s*3080' = 280
        'RTX\s*3070\s*TI' = 220; 'RTX\s*3070' = 190; 'RTX\s*3060\s*TI' = 160; 'RTX\s*3060' = 130
        'RTX\s*3050' = 90
        # RTX 20 series
        'RTX\s*2080\s*TI' = 200; 'RTX\s*2080\s*SUPER' = 170; 'RTX\s*2080' = 150; 'RTX\s*2070\s*SUPER' = 140
        'RTX\s*2070' = 120; 'RTX\s*2060\s*SUPER' = 110; 'RTX\s*2060' = 90
        # GTX 16 series
        'GTX\s*1660\s*TI' = 80; 'GTX\s*1660\s*SUPER' = 75; 'GTX\s*1660' = 65; 'GTX\s*1650\s*SUPER' = 60; 'GTX\s*1650' = 50
        # GTX 10 series
        'GTX\s*1080\s*TI' = 100; 'GTX\s*1080' = 80; 'GTX\s*1070\s*TI' = 70; 'GTX\s*1070' = 60
        'GTX\s*1060' = 40; 'GTX\s*1050\s*TI' = 30; 'GTX\s*1050' = 25
        # AMD RX 7000
        'RX\s*7900\s*XTX' = 550; 'RX\s*7900\s*XT' = 450; 'RX\s*7800\s*XT' = 300; 'RX\s*7700\s*XT' = 250
        'RX\s*7600\s*XT' = 200; 'RX\s*7600' = 170
        # AMD RX 6000
        'RX\s*6950\s*XT' = 300; 'RX\s*6900\s*XT' = 270; 'RX\s*6800\s*XT' = 220; 'RX\s*6800' = 180
        'RX\s*6700\s*XT' = 140; 'RX\s*6600\s*XT' = 110; 'RX\s*6600' = 90; 'RX\s*6500\s*XT' = 50
        # AMD RX 5000
        'RX\s*5700\s*XT' = 100; 'RX\s*5700' = 80; 'RX\s*5600\s*XT' = 70; 'RX\s*5500\s*XT' = 45
        # Intel Arc (discrete only; the integrated part carries no model number).
        # The reported name is "Intel(R) Arc(TM) A770 Graphics", so the branding
        # suffix has to be skipped rather than matched as whitespace.
        'ARC\b.*\bB580\b' = 220; 'ARC\b.*\bB570\b' = 180
        'ARC\b.*\bA770\b' = 180; 'ARC\b.*\bA750\b' = 140
        'ARC\b.*\bA580\b' = 100; 'ARC\b.*\bA380\b' = 70
        # Laptop GPUs (generally worth less - use mobile modifier later)
    }

    $value = 50  # default for unknown discrete GPUs
    # Sort by key length descending so more specific patterns match first
    $sortedKeys = $gpuPrices.Keys | Sort-Object { $_.Length } -Descending
    foreach ($pattern in $sortedKeys) {
        if ($name -match $pattern) {
            $value = $gpuPrices[$pattern]
            break
        }
    }

    # Laptop GPU penalty (~20% less than desktop)
    if ($name -match 'LAPTOP|MOBILE|MAX-Q') {
        $value = [math]::Round($value * 0.8, 0)
    }

    return $value
}

function Get-RAMValue {
    [CmdletBinding()]
    param([PSCustomObject]$RAM)

    $pricePerGB = switch ($RAM.Type) {
        "DDR5"    { 3.00 }
        "DDR4"    { 2.00 }
        "DDR3"    { 1.00 }
        "DDR2"    { 0.50 }
        default   { 1.50 }
    }

    return [math]::Round($RAM.TotalGB * $pricePerGB, 0)
}

function Get-StorageValue {
    [CmdletBinding()]
    param([array]$StorageList)

    $totalValue = 0
    foreach ($disk in $StorageList) {
        $pricePerGB = switch -Wildcard ($disk.MediaType) {
            "NVMe*"   { 0.06 }
            "SSD"     { 0.04 }
            "HDD"     { 0.02 }
            default   { 0.03 }
        }
        $totalValue += [math]::Round($disk.SizeGB * $pricePerGB, 0)
    }
    return $totalValue
}

function Get-AgeDepreciation {
    [CmdletBinding()]
    param(
        [double]$TotalComponentValue,
        [object]$AgeYears
    )

    if (-not $AgeYears -or $AgeYears -le 0) { return 0 }

    $remaining = 1.0

    # First year: gradual depreciation by month
    if ($AgeYears -lt 1) {
        # 0-3 months: 5%, 3-6 months: 10%, 6-12 months: 20%
        if ($AgeYears -le 0.25) { $remaining = 0.95 }
        elseif ($AgeYears -le 0.5) { $remaining = 0.90 }
        else { $remaining = 0.80 }
    } else {
        $remaining = 0.70  # Year 1 complete: -30%
        $fullYears = [math]::Floor($AgeYears)
        if ($fullYears -ge 2) { $remaining *= 0.80 }  # Year 2: -20%
        if ($fullYears -ge 3) { $remaining *= 0.85 }  # Year 3: -15%
        for ($i = 4; $i -le $fullYears; $i++) {
            $remaining *= 0.90  # Each additional year: -10%
        }
    }

    # Floor at 15% of original value
    $remaining = [math]::Max($remaining, 0.15)

    $depreciatedValue = $TotalComponentValue * $remaining
    $depreciation = $TotalComponentValue - $depreciatedValue

    return [math]::Round($depreciation, 0)
}

function Get-BatteryPenalty {
    [CmdletBinding()]
    param([PSCustomObject]$Battery)

    if (-not $Battery -or -not $Battery.HealthPercent) { return 0 }

    $health = $Battery.HealthPercent
    if ($health -ge 80) { return 0 }
    elseif ($health -ge 60) { return -50 }
    elseif ($health -ge 40) { return -100 }
    else { return -150 }
}

function Get-PCValuation {
    [CmdletBinding()]
    param([PSCustomObject]$Specs)

    Write-Verbose "Calculating component values..."

    $cpuValue = Get-CPUValue -CPU $Specs.CPU
    $gpuValue = Get-GPUValue -GPU $Specs.GPU
    $ramValue = Get-RAMValue -RAM $Specs.RAM
    $storageValue = Get-StorageValue -StorageList $Specs.Storage

    $componentTotal = $cpuValue + $gpuValue + $ramValue + $storageValue

    $depreciation = Get-AgeDepreciation -TotalComponentValue $componentTotal -AgeYears $Specs.AgeYears
    $batteryPenalty = Get-BatteryPenalty -Battery $Specs.Battery

    # Portability bonus for laptops
    $portabilityBonus = 0
    if ($Specs.SystemType -eq "Laptop") {
        $portabilityBonus = [math]::Round(($componentTotal - $depreciation) * 0.10, 0)
    }

    $midEstimate = $componentTotal - $depreciation + $batteryPenalty + $portabilityBonus
    $midEstimate = [math]::Max($midEstimate, 25)  # Minimum $25

    $lowEstimate = [math]::Round($midEstimate * 0.85, 0)
    $highEstimate = [math]::Round($midEstimate * 1.15, 0)

    $valuation = [PSCustomObject]@{
        CPUValue          = $cpuValue
        GPUValue          = $gpuValue
        RAMValue          = $ramValue
        StorageValue      = $storageValue
        ComponentTotal    = $componentTotal
        Depreciation      = $depreciation
        BatteryPenalty    = $batteryPenalty
        PortabilityBonus  = $portabilityBonus
        LowEstimate       = $lowEstimate
        MidEstimate       = $midEstimate
        HighEstimate      = $highEstimate
    }

    Write-Verbose "Valuation complete."
    return $valuation
}

Export-ModuleMember -Function Get-PCValuation, Get-CPUValue, Get-GPUValue, Get-RAMValue, Get-StorageValue, Get-AgeDepreciation, Get-BatteryPenalty
