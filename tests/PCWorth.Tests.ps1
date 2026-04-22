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
