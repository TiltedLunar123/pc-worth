# PC Worth Estimator

A PowerShell script that auto-detects your PC's hardware and estimates its current resale value.

## Features

- **Auto-detection** - CPU, GPU, RAM, storage, battery health, system age, and more
- **Built-in pricing** - Offline valuation using component-level pricing database
- **Online lookup** - Optional eBay sold listings check to refine the estimate
- **Laptop aware** - Detects battery health, applies portability bonus
- **Age depreciation** - Realistic depreciation curves based on system age
- **Colored report** - Clean terminal output with component breakdown

## Quick Start

```powershell
# Clone and run
git clone https://github.com/hilge/pc-worth.git
cd pc-worth
.\Get-PCWorth.ps1
```

Or download and run directly:
```powershell
irm https://raw.githubusercontent.com/hilge/pc-worth/main/Get-PCWorth.ps1 -OutFile Get-PCWorth.ps1
# Also grab the modules folder, then:
.\Get-PCWorth.ps1
```

## Usage

```powershell
# Full analysis (offline + online)
.\Get-PCWorth.ps1

# Offline only (no internet needed)
.\Get-PCWorth.ps1 -SkipOnline

# Verbose output (see detection details)
.\Get-PCWorth.ps1 -Verbose
```

## Sample Output

```
  ══════════════════════════════════════════════════════

      PC WORTH ESTIMATOR v1.0

  ══════════════════════════════════════════════════════

  SYSTEM: Acer Nitro AN515-58 (Laptop)
  AGE:    ~2 years (Manufactured: 2024-03)

  HARDWARE SPECS
  ────────────────────────────────────────────────────
  CPU         Intel Core i7-12700H (14C/20T @ 4.7GHz)
  GPU         NVIDIA GeForce RTX 3050 Ti (4GB)
  RAM         16 GB DDR5 @ 4800 MHz
  Storage     512 GB NVMe SSD
  Display     1920x1080
  Battery     82% health
  OS          Windows 11 Home

  VALUE BREAKDOWN
  ────────────────────────────────────────────────────
  CPU ................    $240
  GPU ................     $90
  RAM ................     $48
  Storage ............     $31
  Age depreciation ...    -$71
  Portability bonus ..    +$28
                         ────────
  ESTIMATED VALUE:  $280 - $380

  Online check: ~$320 (eBay Sold Listings)

  ══════════════════════════════════════════════════════
```

## How It Works

### Hardware Detection
Uses Windows CIM/WMI queries (`Get-CimInstance`) to detect:
- CPU model, cores, threads, clock speed
- RAM total, speed, DDR generation
- GPU model, VRAM (discrete vs integrated)
- Storage type (NVMe/SSD/HDD), capacity, health
- System type (laptop/desktop via chassis type)
- Battery health (design vs current capacity)
- Display resolution, WiFi, motherboard

### Valuation
Each component is valued independently:
- **CPU**: Tier-based (i3/i5/i7/i9, Ryzen 3/5/7/9) with generation multiplier
- **GPU**: Lookup table covering NVIDIA GTX/RTX and AMD RX series
- **RAM**: Per-GB pricing by DDR generation
- **Storage**: Per-GB pricing by media type

Then adjustments:
- **Age depreciation**: 30% year 1, 20% year 2, 15% year 3, 10%/year after (floor 15%)
- **Battery penalty**: -$50 to -$150 for degraded batteries
- **Portability bonus**: +10% for laptops

### Online Lookup
Optionally queries eBay sold listings for similar systems, averages the prices (trimming outliers), and blends 60/40 with the offline estimate.

## Requirements

- Windows 10/11
- PowerShell 5.1+ (built into Windows)
- No admin rights needed (some battery details may need elevation)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## License

MIT - see [LICENSE](LICENSE)
