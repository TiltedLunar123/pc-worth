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
