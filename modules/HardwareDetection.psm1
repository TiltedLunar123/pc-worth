function Get-SafeCimInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClassName,
        [string]$Namespace = 'root\cimv2',
        [string]$Label = $ClassName
    )
    try {
        return Get-CimInstance -ClassName $ClassName -Namespace $Namespace -ErrorAction Stop
    } catch {
        Write-Verbose "  $Label query failed: $($_.Exception.Message)"
        return $null
    }
}

function Get-GPUIntegratedFlag {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    # Discrete Arc cards are named "Intel(R) Arc(TM) A770 Graphics" and would
    # otherwise trip the Intel integrated pattern below. The integrated Arc part
    # shipped with Core Ultra carries no A/B model number, so that is what
    # separates the two.
    if ($Name -match 'Arc\b.*\b[AB]\d{3}\b') { return $false }

    return [bool]($Name -match 'Intel.*(?:UHD|HD|Iris|Graphics)|AMD.*Radeon.*Graphics$|Vega.*Graphics')
}

function Get-UnknownCpu {
    [PSCustomObject]@{
        Name         = "Unknown"
        Cores        = 0
        Threads      = 0
        MaxClockGHz  = 0
        BaseClockGHz = 0
    }
}

function Get-UnknownRam {
    [PSCustomObject]@{
        TotalGB  = 0
        SpeedMHz = 0
        Type     = "Unknown"
        Sticks   = 0
    }
}

function Get-HardwareSpecs {
    [CmdletBinding()]
    param()

    Write-Verbose "Detecting hardware specifications..."

    # --- CPU ---
    Write-Verbose "  Querying CPU..."
    $cpuRaw = Get-SafeCimInstance -ClassName Win32_Processor -Label "CPU"
    $cpu = $cpuRaw | Select-Object -First 1
    if (-not $cpu) {
        Write-Verbose "  CPU detection returned no data; using fallback."
        $cpuInfo = Get-UnknownCpu
    } else {
        $cpuName = if ($cpu.Name) { $cpu.Name.Trim() } else { "Unknown" }
        $maxClock = if ($cpu.MaxClockSpeed) { [math]::Round($cpu.MaxClockSpeed / 1000, 2) } else { 0 }
        $baseClock = if ($cpu.CurrentClockSpeed) { [math]::Round($cpu.CurrentClockSpeed / 1000, 2) } else { 0 }
        $cpuInfo = [PSCustomObject]@{
            Name         = $cpuName
            Cores        = [int]($cpu.NumberOfCores)
            Threads      = [int]($cpu.NumberOfLogicalProcessors)
            MaxClockGHz  = $maxClock
            BaseClockGHz = $baseClock
        }
    }

    # --- RAM ---
    Write-Verbose "  Querying RAM..."
    $ramRaw = Get-SafeCimInstance -ClassName Win32_PhysicalMemory -Label "RAM"
    $ramSticks = @()
    if ($ramRaw) { $ramSticks = @($ramRaw) }

    if ($ramSticks.Count -eq 0) {
        Write-Verbose "  No RAM sticks reported by WMI; values will be Unknown."
        $ramInfo = Get-UnknownRam
    } else {
        $totalRAMBytes = ($ramSticks | Measure-Object -Property Capacity -Sum).Sum
        $totalRAMGB = if ($totalRAMBytes) { [math]::Round($totalRAMBytes / 1GB, 0) } else { 0 }

        $firstStick = $ramSticks | Select-Object -First 1
        $ramSpeed = $firstStick.Speed
        $ramType = switch ($firstStick.SMBIOSMemoryType) {
            20 { "DDR" }
            21 { "DDR2" }
            22 { "DDR2" }
            24 { "DDR3" }
            26 { "DDR4" }
            34 { "DDR5" }
            default {
                if ($ramSpeed -ge 4800) { "DDR5" }
                elseif ($ramSpeed -ge 1600) { "DDR4" }
                elseif ($ramSpeed -ge 800) { "DDR3" }
                else { "Unknown" }
            }
        }

        $ramInfo = [PSCustomObject]@{
            TotalGB  = $totalRAMGB
            SpeedMHz = $ramSpeed
            Type     = $ramType
            Sticks   = $ramSticks.Count
        }
    }

    # --- GPU ---
    Write-Verbose "  Querying GPU..."
    $gpusRaw = Get-SafeCimInstance -ClassName Win32_VideoController -Label "GPU"
    $gpus = @()
    if ($gpusRaw) { $gpus = @($gpusRaw) }

    $gpuList = @()
    foreach ($gpu in $gpus) {
        if (-not $gpu) { continue }
        $vramGB = if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
            [math]::Round([uint64]$gpu.AdapterRAM / 1GB, 1)
        } else { 0 }

        # AdapterRAM caps at 4GB for 32-bit field; try registry for real VRAM
        if ($vramGB -le 4 -and $gpu.Name -match 'NVIDIA|Radeon|GeForce|RTX|GTX|RX') {
            try {
                $regPath = "HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
                $subkeys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
                foreach ($key in $subkeys) {
                    $desc = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DriverDesc
                    if ($desc -eq $gpu.Name) {
                        $qwMem = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).'HardwareInformation.qwMemorySize'
                        if ($qwMem) {
                            $vramGB = [math]::Round([uint64]$qwMem / 1GB, 1)
                        }
                        break
                    }
                }
            } catch {
                Write-Verbose "  Registry VRAM probe failed: $($_.Exception.Message)"
            }
        }

        $gpuName = if ($gpu.Name) { $gpu.Name.Trim() } else { "Unknown" }
        $isIntegrated = Get-GPUIntegratedFlag -Name $gpuName
        $gpuList += [PSCustomObject]@{
            Name                        = $gpuName
            VRAMGB                      = $vramGB
            IsIntegrated                = $isIntegrated
            CurrentHorizontalResolution = $gpu.CurrentHorizontalResolution
            CurrentVerticalResolution   = $gpu.CurrentVerticalResolution
        }
    }

    # Prefer discrete GPU if available
    $primaryGPU = $gpuList | Where-Object { -not $_.IsIntegrated } | Select-Object -First 1
    if (-not $primaryGPU) { $primaryGPU = $gpuList | Select-Object -First 1 }

    # --- Storage ---
    Write-Verbose "  Querying storage..."
    $storageList = @()
    try {
        $physicalDisks = Get-PhysicalDisk -ErrorAction Stop
        foreach ($disk in $physicalDisks) {
            $sizeGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 0) } else { 0 }
            $mediaType = switch ($disk.MediaType) {
                "SSD"            { "SSD" }
                "HDD"            { "HDD" }
                "Unspecified"    { if ($disk.BusType -eq "NVMe") { "NVMe SSD" } else { "Unknown" } }
                default          { $disk.MediaType }
            }
            if ($disk.BusType -eq "NVMe" -and $mediaType -eq "SSD") { $mediaType = "NVMe SSD" }

            $storageList += [PSCustomObject]@{
                Model     = if ($disk.FriendlyName) { $disk.FriendlyName.Trim() } else { "Unknown" }
                SizeGB    = $sizeGB
                MediaType = $mediaType
                BusType   = $disk.BusType
                Health    = $disk.HealthStatus
            }
        }
    } catch {
        Write-Verbose "  Get-PhysicalDisk failed, falling back to Win32_DiskDrive: $($_.Exception.Message)"
        $wmiDisks = Get-SafeCimInstance -ClassName Win32_DiskDrive -Label "Disk drives"
        if ($wmiDisks) {
            foreach ($disk in $wmiDisks) {
                $sizeGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 0) } else { 0 }
                $storageList += [PSCustomObject]@{
                    Model     = if ($disk.Model) { $disk.Model.Trim() } else { "Unknown" }
                    SizeGB    = $sizeGB
                    MediaType = if ($disk.Model -match 'SSD|NVMe|Solid') { "SSD" } else { "HDD" }
                    BusType   = $disk.InterfaceType
                    Health    = "Unknown"
                }
            }
        }
    }

    if ($storageList.Count -eq 0) {
        Write-Verbose "  No storage devices reported by either Get-PhysicalDisk or WMI."
    }

    # --- System Type (Laptop vs Desktop) ---
    Write-Verbose "  Detecting system type..."
    $chassis = Get-SafeCimInstance -ClassName Win32_SystemEnclosure -Label "Chassis"
    $chassisType = if ($chassis) { ($chassis | Select-Object -First 1).ChassisTypes | Select-Object -First 1 } else { $null }
    $laptopTypes = @(8,9,10,11,12,14,18,21,30,31,32)
    $isLaptop = $chassisType -in $laptopTypes
    $systemType = if ($isLaptop) { "Laptop" } else { "Desktop" }

    # --- System Info ---
    Write-Verbose "  Querying system info..."
    $compSys = Get-SafeCimInstance -ClassName Win32_ComputerSystem -Label "Computer system" | Select-Object -First 1
    $bios    = Get-SafeCimInstance -ClassName Win32_BIOS            -Label "BIOS"            | Select-Object -First 1
    $os      = Get-SafeCimInstance -ClassName Win32_OperatingSystem -Label "Operating system"| Select-Object -First 1
    $mobo    = Get-SafeCimInstance -ClassName Win32_BaseBoard       -Label "Motherboard"     | Select-Object -First 1

    $manufacturer = if ($compSys -and $compSys.Manufacturer) { $compSys.Manufacturer.Trim() } else { "Unknown" }
    $model        = if ($compSys -and $compSys.Model)        { $compSys.Model.Trim() }        else { "Unknown" }

    $biosDate = if ($bios) { $bios.ReleaseDate } else { $null }
    $ageYears = if ($biosDate) {
        [math]::Round(((Get-Date) - $biosDate).Days / 365.25, 1)
    } else { $null }
    $manufactureDate = if ($biosDate) { $biosDate.ToString("yyyy-MM") } else { "Unknown" }

    # --- Battery (Laptops) ---
    $batteryInfo = $null
    if ($isLaptop) {
        Write-Verbose "  Querying battery..."
        $battery = Get-SafeCimInstance -ClassName Win32_Battery -Label "Battery" | Select-Object -First 1
        if ($battery) {
            $batteryHealth = $null
            try {
                $battFull = Get-CimInstance -Namespace root\WMI -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1
                $battDesign = Get-CimInstance -Namespace root\WMI -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1
                if ($battFull -and $battDesign -and $battDesign.DesignedCapacity -gt 0) {
                    $batteryHealth = [math]::Round(($battFull.FullChargedCapacity / $battDesign.DesignedCapacity) * 100, 0)
                }
            } catch {
                Write-Verbose "  Battery design/full-charge capacity queries unavailable: $($_.Exception.Message)"
            }

            $batteryInfo = [PSCustomObject]@{
                Status        = $battery.Status
                ChargePercent = $battery.EstimatedChargeRemaining
                HealthPercent = $batteryHealth
            }
        } else {
            Write-Verbose "  Win32_Battery returned no data on a laptop chassis."
        }
    }

    # --- Display ---
    Write-Verbose "  Querying display..."
    $primaryDisplay = $gpuList | Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
    $displayRes = if ($primaryDisplay) {
        "$($primaryDisplay.CurrentHorizontalResolution)x$($primaryDisplay.CurrentVerticalResolution)"
    } else {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            "$($screen.Width)x$($screen.Height)"
        } catch {
            Write-Verbose "  Display detection via WinForms failed: $($_.Exception.Message)"
            "Unknown"
        }
    }

    # --- WiFi ---
    $netAdapters = Get-SafeCimInstance -ClassName Win32_NetworkAdapter -Label "Network adapters"
    $hasWifi = $false
    if ($netAdapters) {
        $hasWifi = $null -ne ($netAdapters | Where-Object {
            $_.Name -match 'Wi-?Fi|Wireless|802\.11|WLAN' -and $_.PhysicalAdapter -eq $true
        })
    }

    # --- Build result ---
    $specs = [PSCustomObject]@{
        Manufacturer    = $manufacturer
        Model           = $model
        SystemType      = $systemType
        AgeYears        = $ageYears
        ManufactureDate = $manufactureDate
        CPU             = $cpuInfo
        RAM             = $ramInfo
        GPU             = $primaryGPU
        AllGPUs         = $gpuList
        Storage         = $storageList
        Battery         = $batteryInfo
        DisplayRes      = $displayRes
        Motherboard     = if ($mobo) { "$($mobo.Manufacturer) $($mobo.Product)".Trim() } else { "Unknown" }
        OS              = if ($os) { "$($os.Caption) $($os.Version)" } else { "Unknown" }
        HasWifi         = $hasWifi
    }

    Write-Verbose "Hardware detection complete."
    return $specs
}

Export-ModuleMember -Function Get-HardwareSpecs, Get-SafeCimInstance, Get-UnknownCpu, Get-UnknownRam, Get-GPUIntegratedFlag
