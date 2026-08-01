# PC Worth Estimator

A PowerShell script that auto-detects your PC's hardware and estimates its current resale value.

It reads the hardware itself, so there is nothing to fill in. CPU, GPU, RAM, storage,
battery health and system age all come from CIM queries, get priced component by
component against a built-in table, and then get adjusted for age and for whether the
machine is a laptop. Everything works offline. If you leave the online step on it also
checks eBay sold listings and blends that in.

The pricing table is my own and it is opinionated. See the valuation notes below if you
want to argue with it.

## Quick Start

```powershell
# Clone and run
git clone https://github.com/TiltedLunar123/pc-worth.git
cd pc-worth
.\Get-PCWorth.ps1
```

Or download and run directly:
```powershell
irm https://raw.githubusercontent.com/TiltedLunar123/pc-worth/master/Get-PCWorth.ps1 -OutFile Get-PCWorth.ps1
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
- GPU model, VRAM (discrete vs integrated vs virtual)
- Storage type (NVMe/SSD/HDD), capacity, health
- System type (laptop/desktop via chassis type)
- Battery health (design vs current capacity)
- Display resolution, WiFi, motherboard

### Valuation
Each component is valued independently:
- **CPU**: Tier-based (i3/i5/i7/i9, Core Ultra 5/7/9, Ryzen 3/5/7/9) with a generation multiplier. Ryzen series numbers are mapped onto the Intel generation they launched against first, so a Ryzen 7 5800X and the i7-10700 it competed with price the same instead of the AMD part landing four bands too low.
- **GPU**: Lookup table covering NVIDIA GTX/RTX, AMD RX, and discrete Intel Arc. Integrated graphics are worth $0, including the Arc iGPU in Core Ultra chips, which shares its name with the discrete cards. Software and remote display adapters (Microsoft Basic Display Adapter, Hyper-V, VMware, VirtualBox, Citrix, Parsec, DisplayLink) are worth $0 too, and a real card outranks them when the primary GPU is picked, so a machine running without its graphics driver is not credited with a mystery card.
- **RAM**: Per-GB pricing by DDR generation
- **Storage**: Per-GB pricing by media type

Then adjustments:
- **Age depreciation**: multiplicative on the remaining value (not the original). Year 1 retains 70%, year 2 multiplies that by 0.80, year 3 by 0.85, each year beyond by 0.90, floored at 15% of the original. So a 3-year-old system retains roughly 48% of its component total, not 35%.
- **Battery penalty**: -$50 below 80% health, -$100 below 60%, -$150 below 40%. A battery reporting 0% is a reading, not a missing one, so it takes the full -$150 rather than being read as "no battery fitted".
- **Portability bonus**: +10% for laptops

### Online Lookup
Optionally queries eBay sold listings for similar systems, averages the prices (trimming outliers), and blends 60/40 with the offline estimate.

## Requirements

- Windows 10/11
- PowerShell 5.1+ (built into Windows)
- No admin rights needed (some battery details may need elevation)

## Contributing

The prices go stale, so corrections to the tables in `modules/` are the most useful
thing to send. Open an issue or a PR.

## License

MIT - see [LICENSE](LICENSE)
