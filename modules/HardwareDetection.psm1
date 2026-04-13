function Get-HardwareSpecs {
    [CmdletBinding()]
    param()

    Write-Verbose "Detecting hardware specifications..."

    # --- CPU ---
    Write-Verbose "  Querying CPU..."
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cpuInfo = [PSCustomObject]@{
        Name         = $cpu.Name.Trim()
        Cores        = $cpu.NumberOfCores
        Threads      = $cpu.NumberOfLogicalProcessors
        MaxClockGHz  = [math]::Round($cpu.MaxClockSpeed / 1000, 2)
        BaseClockGHz = [math]::Round($cpu.CurrentClockSpeed / 1000, 2)
    }

    # --- RAM ---
    Write-Verbose "  Querying RAM..."
    $ramSticks = Get-CimInstance Win32_PhysicalMemory
    $totalRAMBytes = ($ramSticks | Measure-Object -Property Capacity -Sum).Sum
    $totalRAMGB = [math]::Round($totalRAMBytes / 1GB, 0)

    $ramSpeed = ($ramSticks | Select-Object -First 1).Speed
    $ramType = switch (($ramSticks | Select-Object -First 1).SMBIOSMemoryType) {
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
        TotalGB   = $totalRAMGB
        SpeedMHz  = $ramSpeed
        Type      = $ramType
        Sticks    = $ramSticks.Count
    }

    # --- GPU ---
    Write-Verbose "  Querying GPU..."
    $gpus = Get-CimInstance Win32_VideoController
    $gpuList = @()
    foreach ($gpu in $gpus) {
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
            } catch {}
        }

        $isIntegrated = $gpu.Name -match 'Intel.*(?:UHD|HD|Iris|Graphics)|AMD.*Radeon.*Graphics$|Vega.*Graphics'
        $gpuList += [PSCustomObject]@{
            Name         = $gpu.Name.Trim()
            VRAMGB       = $vramGB
            IsIntegrated = $isIntegrated
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
            $sizeGB = [math]::Round($disk.Size / 1GB, 0)
            $mediaType = switch ($disk.MediaType) {
                "SSD"            { "SSD" }
                "HDD"            { "HDD" }
                "Unspecified"    { if ($disk.BusType -eq "NVMe") { "NVMe SSD" } else { "Unknown" } }
                default          { $disk.MediaType }
            }
            if ($disk.BusType -eq "NVMe" -and $mediaType -eq "SSD") { $mediaType = "NVMe SSD" }

            $health = $disk.HealthStatus

            $storageList += [PSCustomObject]@{
                Model     = $disk.FriendlyName.Trim()
                SizeGB    = $sizeGB
                MediaType = $mediaType
                BusType   = $disk.BusType
                Health    = $health
            }
        }
    } catch {
        # Fallback to WMI
        $wmiDisks = Get-CimInstance Win32_DiskDrive
        foreach ($disk in $wmiDisks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 0)
            $storageList += [PSCustomObject]@{
                Model     = $disk.Model.Trim()
                SizeGB    = $sizeGB
                MediaType = if ($disk.Model -match 'SSD|NVMe|Solid') { "SSD" } else { "HDD" }
                BusType   = $disk.InterfaceType
                Health    = "Unknown"
            }
        }
    }

    # --- System Type (Laptop vs Desktop) ---
    Write-Verbose "  Detecting system type..."
    $chassis = Get-CimInstance Win32_SystemEnclosure
    $chassisType = $chassis.ChassisTypes | Select-Object -First 1
    # Laptop chassis types: 8,9,10,11,12,14,18,21,30,31,32
    $laptopTypes = @(8,9,10,11,12,14,18,21,30,31,32)
    $isLaptop = $chassisType -in $laptopTypes

    $systemType = if ($isLaptop) { "Laptop" } else { "Desktop" }

    # --- System Info ---
    Write-Verbose "  Querying system info..."
    $compSys = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    $mobo = Get-CimInstance Win32_BaseBoard

    $manufacturer = $compSys.Manufacturer.Trim()
    $model = $compSys.Model.Trim()

    # System age from BIOS release date
    $biosDate = $bios.ReleaseDate
    $ageYears = if ($biosDate) {
        [math]::Round(((Get-Date) - $biosDate).Days / 365.25, 1)
    } else { $null }

    # Try to get a better manufacture date from serial or BIOS
    $manufactureDate = if ($biosDate) { $biosDate.ToString("yyyy-MM") } else { "Unknown" }

    # --- Battery (Laptops) ---
    $batteryInfo = $null
    if ($isLaptop) {
        Write-Verbose "  Querying battery..."
        try {
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            if ($battery) {
                # Try WMI for design vs full charge capacity
                $batteryHealth = $null
                try {
                    $battFull = Get-CimInstance -Namespace root\WMI -ClassName BatteryFullChargedCapacity -ErrorAction Stop
                    $battDesign = Get-CimInstance -Namespace root\WMI -ClassName BatteryStaticData -ErrorAction Stop
                    if ($battFull -and $battDesign -and $battDesign.DesignedCapacity -gt 0) {
                        $batteryHealth = [math]::Round(($battFull.FullChargedCapacity / $battDesign.DesignedCapacity) * 100, 0)
                    }
                } catch {}

                $batteryInfo = [PSCustomObject]@{
                    Status        = $battery.Status
                    ChargePercent = $battery.EstimatedChargeRemaining
                    HealthPercent = $batteryHealth
                }
            }
        } catch {}
    }

    # --- Display ---
    Write-Verbose "  Querying display..."
    $primaryDisplay = $gpus | Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
    $displayRes = if ($primaryDisplay) {
        "$($primaryDisplay.CurrentHorizontalResolution)x$($primaryDisplay.CurrentVerticalResolution)"
    } else {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            "$($screen.Width)x$($screen.Height)"
        } catch { "Unknown" }
    }

    # --- WiFi ---
    $hasWifi = ($null -ne (Get-CimInstance Win32_NetworkAdapter | Where-Object {
        $_.Name -match 'Wi-?Fi|Wireless|802\.11|WLAN' -and $_.PhysicalAdapter -eq $true
    }))

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
        Motherboard     = "$($mobo.Manufacturer) $($mobo.Product)".Trim()
        OS              = "$($os.Caption) $($os.Version)"
        HasWifi         = $hasWifi
    }

    Write-Verbose "Hardware detection complete."
    return $specs
}

Export-ModuleMember -Function Get-HardwareSpecs
