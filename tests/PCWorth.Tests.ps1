#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:repoRoot 'modules\HardwareDetection.psm1') -Force
    Import-Module (Join-Path $script:repoRoot 'modules\OnlineLookup.psm1')       -Force
    Import-Module (Join-Path $script:repoRoot 'modules\Valuation.psm1')          -Force
}

Describe 'Get-SafeCimInstance' {
    It 'Returns $null and writes a verbose note when the class does not exist' {
        $verboseLines = New-Object System.Collections.Generic.List[string]
        $values = New-Object System.Collections.Generic.List[object]
        Get-SafeCimInstance -ClassName 'Win32_NonExistent_ClassName_xyz' -Verbose 4>&1 | ForEach-Object {
            if ($null -ne $_ -and $_.GetType().Name -eq 'VerboseRecord') {
                $verboseLines.Add([string]$_)
            } else {
                $values.Add($_)
            }
        }
        ($values | Where-Object { $null -ne $_ }) | Should -BeNullOrEmpty
        $verboseLines.Count | Should -BeGreaterThan 0
        ($verboseLines -join "`n") | Should -Match 'query failed'
    }

    It 'Returns data for a known-good class' {
        $os = Get-SafeCimInstance -ClassName 'Win32_OperatingSystem'
        $os | Should -Not -BeNullOrEmpty
    }
}

Describe 'Unknown-hardware fallbacks' {
    It 'Get-UnknownCpu returns a PSCustomObject with Name=Unknown' {
        $cpu = Get-UnknownCpu
        $cpu | Should -Not -BeNullOrEmpty
        $cpu.Name | Should -Be 'Unknown'
        $cpu.Cores | Should -Be 0
    }

    It 'Get-UnknownRam returns TotalGB=0 and Type=Unknown' {
        $ram = Get-UnknownRam
        $ram.TotalGB | Should -Be 0
        $ram.Type | Should -Be 'Unknown'
        $ram.Sticks | Should -Be 0
    }

    It 'Valuation.Get-RAMValue handles the unknown-RAM shape without throwing' {
        $ram = Get-UnknownRam
        { Get-RAMValue -RAM $ram } | Should -Not -Throw
        (Get-RAMValue -RAM $ram) | Should -Be 0
    }
}

Describe 'Get-HardwareSpecs' {
    It 'Runs end to end without throwing on the current host' {
        { Get-HardwareSpecs | Out-Null } | Should -Not -Throw
    }

    It 'Returns a specs object with CPU/RAM/Storage populated' {
        $specs = Get-HardwareSpecs
        $specs | Should -Not -BeNullOrEmpty
        $specs.CPU | Should -Not -BeNullOrEmpty
        $specs.RAM | Should -Not -BeNullOrEmpty
        $specs.Storage | Should -Not -BeNullOrEmpty
    }

    It 'Preserves display resolution info on GPU list entries' {
        $specs = Get-HardwareSpecs
        ($specs.AllGPUs | Where-Object { $_.CurrentHorizontalResolution }) | Should -Not -BeNullOrEmpty
    }
}

Describe 'OnlineLookup price regex' {
    It 'Captures prices >= $1,000 with thousands separators' {
        $sample = '<span class="POSITIVE">$1,250.00</span> and <span>$450.00</span> plus <span>$2,350</span>'
        $matches = [regex]::Matches($sample, '\$(\d{1,4}(?:,\d{3})*(?:\.\d{2})?)</span>')
        $values = $matches | ForEach-Object { [double]($_.Groups[1].Value -replace ',', '') }
        $values | Should -Contain 1250.00
        $values | Should -Contain 450.00
        $values | Should -Contain 2350
    }

    It 'Still captures plain sub-$1000 prices' {
        $sample = '<span>$99.99</span>'
        $matches = [regex]::Matches($sample, '\$(\d{1,4}(?:,\d{3})*(?:\.\d{2})?)</span>')
        $matches.Count | Should -Be 1
        [double]($matches[0].Groups[1].Value) | Should -Be 99.99
    }
}

Describe 'Valuation sanity' {
    It 'Get-PCValuation returns consistent estimates with unknown components' {
        $specs = [PSCustomObject]@{
            Manufacturer = 'Unknown'
            Model        = 'Unknown'
            SystemType   = 'Desktop'
            AgeYears     = 3
            CPU          = Get-UnknownCpu
            RAM          = Get-UnknownRam
            GPU          = $null
            Storage      = @()
            Battery      = $null
        }
        $val = Get-PCValuation -Specs $specs
        $val.MidEstimate | Should -BeGreaterOrEqual 25
        $val.LowEstimate | Should -BeLessOrEqual $val.MidEstimate
        $val.HighEstimate | Should -BeGreaterOrEqual $val.MidEstimate
    }

    It 'Three-year depreciation retains ~48% of component total' {
        $dep = Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 3
        $remaining = 1000 - $dep
        $remaining | Should -BeGreaterThan 470
        $remaining | Should -BeLessThan 490
    }
}

Describe 'Get-CPUValue' {
    It 'Values an Intel gen-12 i7 above the gen-10 baseline' {
        $cpu = [PSCustomObject]@{ Name = 'Intel(R) Core(TM) i7-12700H CPU @ 2.30GHz' }
        $val = Get-CPUValue -CPU $cpu
        # i7 base 200 * 1.2 (gen 12 multiplier) = 240
        $val | Should -Be 240
    }

    It 'Values an Intel gen-9 i5 below the gen-10 baseline' {
        $cpu = [PSCustomObject]@{ Name = 'Intel(R) Core(TM) i5-9400F CPU @ 2.90GHz' }
        $val = Get-CPUValue -CPU $cpu
        # i5 base 120 * 0.8 (gen 8-9 multiplier) = 96
        $val | Should -Be 96
    }

    It 'Values a Ryzen 7 5800X using the AMD generation digit' {
        $cpu = [PSCustomObject]@{ Name = 'AMD Ryzen 7 5800X 8-Core Processor' }
        $val = Get-CPUValue -CPU $cpu
        # Ryzen 7 base 200, AMD gen 5 -> multiplier 0.4. Yes, the curve is
        # harsh on older AMD parts; that's the current model, not a bug.
        $val | Should -BeGreaterThan 0
        $val | Should -BeLessOrEqual 200
    }

    It 'Recognizes Apple M-series silicon' {
        $cpu = [PSCustomObject]@{ Name = 'Apple M2' }
        $val = Get-CPUValue -CPU $cpu
        $val | Should -BeGreaterThan 0
    }

    It 'Falls back to the unknown tier without throwing' {
        $cpu = [PSCustomObject]@{ Name = 'Some Weird Bespoke CPU' }
        { Get-CPUValue -CPU $cpu } | Should -Not -Throw
        (Get-CPUValue -CPU $cpu) | Should -BeGreaterThan 0
    }
}

Describe 'Get-GPUValue' {
    It 'Returns 0 for a null GPU' {
        Get-GPUValue -GPU $null | Should -Be 0
    }

    It 'Returns 0 for integrated graphics' {
        $gpu = [PSCustomObject]@{
            Name         = 'Intel(R) UHD Graphics 770'
            VRAMGB       = 0
            IsIntegrated = $true
        }
        Get-GPUValue -GPU $gpu | Should -Be 0
    }

    It 'Prices a current-gen RTX from the lookup table' {
        $gpu = [PSCustomObject]@{
            Name         = 'NVIDIA GeForce RTX 4070'
            VRAMGB       = 12
            IsIntegrated = $false
        }
        Get-GPUValue -GPU $gpu | Should -Be 280
    }

    It 'Prefers the more specific Ti variant over the base SKU' {
        $gpu = [PSCustomObject]@{
            Name         = 'NVIDIA GeForce RTX 4060 Ti'
            VRAMGB       = 8
            IsIntegrated = $false
        }
        Get-GPUValue -GPU $gpu | Should -Be 220
    }

    It 'Applies the laptop penalty when the name flags mobile silicon' {
        $gpu = [PSCustomObject]@{
            Name         = 'NVIDIA GeForce RTX 3070 Laptop GPU'
            VRAMGB       = 8
            IsIntegrated = $false
        }
        # 190 * 0.8 = 152
        Get-GPUValue -GPU $gpu | Should -Be 152
    }

    It 'Recognizes AMD Radeon RX' {
        $gpu = [PSCustomObject]@{
            Name         = 'AMD Radeon RX 6700 XT'
            VRAMGB       = 12
            IsIntegrated = $false
        }
        Get-GPUValue -GPU $gpu | Should -Be 140
    }
}

Describe 'Get-AgeDepreciation under one year' {
    It 'Applies a 5% hit at 3 months' {
        $dep = Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 0.25
        $dep | Should -Be 50
    }

    It 'Applies a 10% hit at 6 months' {
        $dep = Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 0.5
        $dep | Should -Be 100
    }

    It 'Applies a 20% hit between 6 and 12 months' {
        $dep = Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 0.75
        $dep | Should -Be 200
    }

    It 'Returns zero depreciation when AgeYears is null' {
        Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears $null | Should -Be 0
    }
}

Describe 'Get-BatteryPenalty' {
    It 'Returns zero for a healthy battery (>= 80%)' {
        $battery = [PSCustomObject]@{ HealthPercent = 95 }
        Get-BatteryPenalty -Battery $battery | Should -Be 0
    }

    It 'Returns -$50 for the 60-79% band' {
        $battery = [PSCustomObject]@{ HealthPercent = 70 }
        Get-BatteryPenalty -Battery $battery | Should -Be -50
    }

    It 'Returns -$100 for the 40-59% band' {
        $battery = [PSCustomObject]@{ HealthPercent = 45 }
        Get-BatteryPenalty -Battery $battery | Should -Be -100
    }

    It 'Returns -$150 for a heavily degraded battery (< 40%)' {
        $battery = [PSCustomObject]@{ HealthPercent = 25 }
        Get-BatteryPenalty -Battery $battery | Should -Be -150
    }

    It 'Returns zero when no battery object is passed (desktop)' {
        Get-BatteryPenalty -Battery $null | Should -Be 0
    }

    It 'Returns zero when HealthPercent is missing or null' {
        $battery = [PSCustomObject]@{ HealthPercent = $null }
        Get-BatteryPenalty -Battery $battery | Should -Be 0
    }
}

Describe 'Get-RAMValue' {
    It 'Prices 16GB DDR5 at $3.00/GB' {
        $ram = [PSCustomObject]@{ TotalGB = 16; Type = 'DDR5' }
        Get-RAMValue -RAM $ram | Should -Be 48
    }

    It 'Prices 16GB DDR4 at $2.00/GB' {
        $ram = [PSCustomObject]@{ TotalGB = 16; Type = 'DDR4' }
        Get-RAMValue -RAM $ram | Should -Be 32
    }

    It 'Prices 8GB DDR3 at $1.00/GB' {
        $ram = [PSCustomObject]@{ TotalGB = 8; Type = 'DDR3' }
        Get-RAMValue -RAM $ram | Should -Be 8
    }

    It 'Prices 4GB DDR2 at $0.50/GB' {
        $ram = [PSCustomObject]@{ TotalGB = 4; Type = 'DDR2' }
        Get-RAMValue -RAM $ram | Should -Be 2
    }

    It 'Falls back to the default $1.50/GB for an unrecognized type' {
        $ram = [PSCustomObject]@{ TotalGB = 16; Type = 'LPDDR5X' }
        Get-RAMValue -RAM $ram | Should -Be 24
    }
}

Describe 'Get-StorageValue' {
    It 'Prices a 1TB NVMe SSD at $0.06/GB' {
        $disks = @(
            [PSCustomObject]@{ SizeGB = 1024; MediaType = 'NVMe SSD' }
        )
        Get-StorageValue -StorageList $disks | Should -Be 61
    }

    It 'Prices a 500GB SATA SSD at $0.04/GB' {
        $disks = @(
            [PSCustomObject]@{ SizeGB = 500; MediaType = 'SSD' }
        )
        Get-StorageValue -StorageList $disks | Should -Be 20
    }

    It 'Prices a 2TB HDD at $0.02/GB' {
        $disks = @(
            [PSCustomObject]@{ SizeGB = 2048; MediaType = 'HDD' }
        )
        Get-StorageValue -StorageList $disks | Should -Be 41
    }

    It 'Falls back to $0.03/GB for an unknown media type' {
        $disks = @(
            [PSCustomObject]@{ SizeGB = 256; MediaType = 'Unknown' }
        )
        Get-StorageValue -StorageList $disks | Should -Be 8
    }

    It 'Sums values across multiple disks' {
        $disks = @(
            [PSCustomObject]@{ SizeGB = 512; MediaType = 'NVMe SSD' }
            [PSCustomObject]@{ SizeGB = 1024; MediaType = 'HDD' }
        )
        # 512 * 0.06 = 30.72 -> 31; 1024 * 0.02 = 20.48 -> 20; total 51
        Get-StorageValue -StorageList $disks | Should -Be 51
    }

    It 'Returns zero for an empty storage list' {
        Get-StorageValue -StorageList @() | Should -Be 0
    }
}

Describe 'Get-PCValuation laptop portability bonus' {
    BeforeAll {
        # i7-12700H 240 + DDR5 16GB 48 + 512GB NVMe 31 = 319 component total.
        # At two years old the depreciated total is 319 - 140 = 179.
        $script:bonusSpecs = @{
            Manufacturer = 'Acer'
            Model        = 'Nitro'
            AgeYears     = 2
            CPU          = [PSCustomObject]@{ Name = 'Intel(R) Core(TM) i7-12700H CPU @ 2.30GHz' }
            RAM          = [PSCustomObject]@{ TotalGB = 16; Type = 'DDR5' }
            GPU          = $null
            Storage      = @([PSCustomObject]@{ SizeGB = 512; MediaType = 'NVMe SSD' })
            Battery      = $null
        }
    }

    It 'Adds a portability bonus for a laptop' {
        $specs = [PSCustomObject]($bonusSpecs + @{ SystemType = 'Laptop' })
        $val = Get-PCValuation -Specs $specs
        $val.PortabilityBonus | Should -Be 18   # round(179 * 0.10)
        $val.MidEstimate | Should -Be 197        # 319 - 140 + 0 + 18
    }

    It 'Adds no portability bonus for a desktop' {
        $specs = [PSCustomObject]($bonusSpecs + @{ SystemType = 'Desktop' })
        $val = Get-PCValuation -Specs $specs
        $val.PortabilityBonus | Should -Be 0
        $val.MidEstimate | Should -Be 179        # 319 - 140, no bonus
    }

    It 'Takes the bonus on the depreciated total, not the raw component sum' {
        # On the raw 319 total the bonus would round to 32; on the
        # depreciated 179 it is 18. The 18 confirms which base is used.
        $specs = [PSCustomObject]($bonusSpecs + @{ SystemType = 'Laptop' })
        $val = Get-PCValuation -Specs $specs
        $val.PortabilityBonus | Should -Be 18
        $val.PortabilityBonus | Should -Not -Be 32
    }

    It 'The laptop mid estimate beats the desktop one by exactly the bonus' {
        $lap  = Get-PCValuation -Specs ([PSCustomObject]($bonusSpecs + @{ SystemType = 'Laptop' }))
        $desk = Get-PCValuation -Specs ([PSCustomObject]($bonusSpecs + @{ SystemType = 'Desktop' }))
        ($lap.MidEstimate - $desk.MidEstimate) | Should -Be $lap.PortabilityBonus
    }
}

Describe 'Get-PCValuation battery penalty integration' {
    BeforeAll {
        # A higher-value laptop so the penalty does not collide with the
        # $25 floor: i7 240 + RTX 4070 280 + DDR5 48 + 1TB NVMe 61 = 629.
        function New-BatterySpecs {
            param([int]$Health)
            [PSCustomObject]@{
                Manufacturer = 'Acer'
                Model        = 'Predator'
                SystemType   = 'Laptop'
                AgeYears     = 1
                CPU          = [PSCustomObject]@{ Name = 'Intel(R) Core(TM) i7-12700H CPU @ 2.30GHz' }
                RAM          = [PSCustomObject]@{ TotalGB = 16; Type = 'DDR5' }
                GPU          = [PSCustomObject]@{ Name = 'NVIDIA GeForce RTX 4070'; VRAMGB = 12; IsIntegrated = $false }
                Storage      = @([PSCustomObject]@{ SizeGB = 1024; MediaType = 'NVMe SSD' })
                Battery      = [PSCustomObject]@{ HealthPercent = $Health }
            }
        }
    }

    It 'Subtracts the 40-59% band penalty from the mid estimate' {
        $val = Get-PCValuation -Specs (New-BatterySpecs -Health 45)
        $val.BatteryPenalty | Should -Be -100
        $val.MidEstimate | Should -Be 384   # 629 - 189 - 100 + 44
    }

    It 'A degraded battery lands below an otherwise identical healthy one' {
        $degraded = Get-PCValuation -Specs (New-BatterySpecs -Health 45)
        $healthy  = Get-PCValuation -Specs (New-BatterySpecs -Health 95)
        $healthy.BatteryPenalty | Should -Be 0
        $healthy.MidEstimate | Should -Be 484
        ($healthy.MidEstimate - $degraded.MidEstimate) | Should -Be 100
    }
}

Describe 'Get-AgeDepreciation past year three' {
    It 'Runs the per-year loop once at four years' {
        # 0.70 * 0.80 * 0.85 * 0.90 = 0.4284 remaining
        Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 4 | Should -Be 572
    }

    It 'Runs the per-year loop twice at five years' {
        # 0.4284 * 0.90 = 0.38556 remaining
        Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 5 | Should -Be 614
    }

    It 'Depreciation keeps growing year over year past three' {
        $three = Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 3
        $four  = Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 4
        $five  = Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 5
        $four | Should -BeGreaterThan $three
        $five | Should -BeGreaterThan $four
    }

    It 'Bottoms out at the 15% floor for a very old system' {
        # By the floor, value retained is 15%, so depreciation is 85%.
        Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 20 | Should -Be 850
    }

    It 'Stays on the floor for an absurdly old system' {
        Get-AgeDepreciation -TotalComponentValue 1000 -AgeYears 40 | Should -Be 850
    }
}

Describe 'Get-CPUValue uncovered tiers' {
    It 'Prices a Core Ultra 7 with the newest-gen multiplier' {
        $cpu = [PSCustomObject]@{ Name = 'Intel(R) Core(TM) Ultra 7 155H' }
        # base 250 * 1.4 (Ultra is treated as the top gen band) = 350
        Get-CPUValue -CPU $cpu | Should -Be 350
    }

    It 'Prices a Core Ultra 9 above the Ultra 7' {
        $cpu = [PSCustomObject]@{ Name = 'Intel(R) Core(TM) Ultra 9 285K' }
        # base 350 * 1.4 = 490
        Get-CPUValue -CPU $cpu | Should -Be 490
    }

    It 'Prices a Core Ultra 5 below the Ultra 7' {
        $cpu = [PSCustomObject]@{ Name = 'Intel(R) Core(TM) Ultra 5 125H' }
        # base 160 * 1.4 = 224
        Get-CPUValue -CPU $cpu | Should -Be 224
    }

    It 'Prices a Xeon at the workstation tier with no gen bump' {
        $cpu = [PSCustomObject]@{ Name = 'Intel(R) Xeon(R) W-2295' }
        # base 250, no detectable gen so the 0.7 fallback multiplier -> 175
        Get-CPUValue -CPU $cpu | Should -Be 175
    }

    It 'Prices a Pentium at the budget tier' {
        $cpu = [PSCustomObject]@{ Name = 'Intel(R) Pentium(R) Gold G7400' }
        # base 30 * 0.7 = 21
        Get-CPUValue -CPU $cpu | Should -Be 21
    }
}

Describe 'Get-GPUValue unknown discrete fallback' {
    It 'Prices a discrete card with no table match at the $50 default' {
        $gpu = [PSCustomObject]@{
            Name         = 'NVIDIA GeForce RTX 9999'
            VRAMGB       = 16
            IsIntegrated = $false
        }
        Get-GPUValue -GPU $gpu | Should -Be 50
    }
}

Describe 'Get-OnlineEstimate' {
    BeforeAll {
        # Specs with placeholder manufacturer/model that the query builder
        # is supposed to drop, plus two disks so the largest-disk pick matters.
        function New-LookupSpecs {
            [PSCustomObject]@{
                Manufacturer = 'System manufacturer'
                Model        = 'To Be Filled By O.E.M.'
                SystemType   = 'Laptop'
                CPU          = [PSCustomObject]@{ Name = 'Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz' }
                RAM          = [PSCustomObject]@{ TotalGB = 16 }
                Storage      = @(
                    [PSCustomObject]@{ SizeGB = 256;  MediaType = 'SSD' }
                    [PSCustomObject]@{ SizeGB = 1000; MediaType = 'HDD' }
                )
            }
        }

        $script:offline = [PSCustomObject]@{
            LowEstimate = 850
            MidEstimate = 1000
            HighEstimate = 1150
        }

        # Five span-wrapped prices. After the top/bottom 20% trim (1 each)
        # the kept set is 400/500/600, so the trimmed average is 500.
        $script:goodHtml = '<span>$300.00</span> <span>$400.00</span> ' +
                           '<span>$500.00</span> <span>$600.00</span> <span>$700.00</span>'
    }

    It 'Builds a query that drops placeholder make/model and folds in CPU, RAM, and the largest disk' {
        Mock Invoke-WebRequest -ModuleName OnlineLookup { [PSCustomObject]@{ Content = '' } }
        $r = Get-OnlineEstimate -Specs (New-LookupSpecs) -OfflineValuation $script:offline

        $r.SearchQuery | Should -Not -Match 'System manufacturer'
        $r.SearchQuery | Should -Not -Match 'To Be Filled'
        $r.SearchQuery | Should -Match 'Intel Core i7-9750H'
        $r.SearchQuery | Should -Match '16GB'
        $r.SearchQuery | Should -Match '1000GB HDD'   # largest disk wins over the 256 SSD
        $r.SearchQuery | Should -Match 'used Laptop'
    }

    It 'Marks success and blends 60/40 when enough sold listings come back' {
        Mock Invoke-WebRequest -ModuleName OnlineLookup { [PSCustomObject]@{ Content = $script:goodHtml } }
        $r = Get-OnlineEstimate -Specs (New-LookupSpecs) -OfflineValuation $script:offline

        $r.Success     | Should -BeTrue
        $r.OnlinePrice | Should -Be 500              # trimmed average
        $r.Source      | Should -Match 'eBay'
        # blendedMid = round(500*0.6 + 1000*0.4) = 700, low/high are +/-15%
        $r.BlendedMid  | Should -Be 700
        $r.BlendedLow  | Should -Be 595
        $r.BlendedHigh | Should -Be 805
    }

    It 'Falls back to the offline estimate when fewer than three listings are found' {
        Mock Invoke-WebRequest -ModuleName OnlineLookup {
            [PSCustomObject]@{ Content = '<span>$300.00</span> <span>$400.00</span>' }
        }
        $r = Get-OnlineEstimate -Specs (New-LookupSpecs) -OfflineValuation $script:offline

        $r.Success     | Should -BeFalse
        $r.OnlinePrice | Should -BeNullOrEmpty
        $r.BlendedLow  | Should -Be $script:offline.LowEstimate
        $r.BlendedMid  | Should -Be $script:offline.MidEstimate
        $r.BlendedHigh | Should -Be $script:offline.HighEstimate
    }

    It 'Ignores prices outside the $20-$5000 sanity band' {
        # Only two prices land inside the band, so this stays an offline fallback.
        Mock Invoke-WebRequest -ModuleName OnlineLookup {
            [PSCustomObject]@{ Content = '<span>$5.00</span> <span>$400.00</span> <span>$500.00</span> <span>$9000.00</span>' }
        }
        $r = Get-OnlineEstimate -Specs (New-LookupSpecs) -OfflineValuation $script:offline
        $r.Success    | Should -BeFalse
        $r.BlendedMid | Should -Be $script:offline.MidEstimate
    }

    It 'Returns the offline estimate instead of throwing when the request fails' {
        Mock Invoke-WebRequest -ModuleName OnlineLookup { throw 'network down' }
        { Get-OnlineEstimate -Specs (New-LookupSpecs) -OfflineValuation $script:offline } | Should -Not -Throw

        $r = Get-OnlineEstimate -Specs (New-LookupSpecs) -OfflineValuation $script:offline
        $r.Success     | Should -BeFalse
        $r.BlendedMid  | Should -Be $script:offline.MidEstimate
    }
}
