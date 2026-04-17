# Known Bugs

## [Severity: High] WMI queries throw unhandled exceptions
- **File:** modules/HardwareDetection.psm1:9, 20, 49, 128, 138-141, 195
- **Issue:** Core `Get-CimInstance` calls (CPU, RAM, GPU, chassis, system, network adapter) lack try/catch; with `$ErrorActionPreference='Stop'` any failure kills the entire script.
- **Repro:** Run on a host with the WMI service disabled, a corrupt WMI repository, or a restricted user — script crashes immediately.
- **Fix:** Wrap each CIM call in try/catch with `$null`/"Unknown" fallbacks.

## [Severity: High] Null dereference when CPU/RAM detection returns nothing
- **File:** modules/HardwareDetection.psm1:11, 24-25
- **Issue:** `Select-Object -First 1` on empty CIM results yields `$null`; `.Trim()`/`.Substring()` on it throw "cannot call a method on a null-valued expression".
- **Repro:** Run under a configuration where the CPU or RAM query returns no objects (corrupt drivers, minimal VM).
- **Fix:** Guard with `if (-not $cpu) { $cpu = [pscustomobject]@{ Name="Unknown"; ... } }` before accessing members.

## [Severity: Medium] eBay price regex misses prices ≥ $1,000
- **File:** modules/OnlineLookup.psm1:57
- **Issue:** `\$(\d{1,4}(?:\.\d{2})?)</span>` doesn't allow thousands separators, so `$1,250.00` is never captured, skewing averages downward on higher-value systems.
- **Repro:** Run against a laptop whose listings are mostly $1,000+ — many prices are silently dropped.
- **Fix:** Update regex to `\$(\d{1,4}(?:,\d{3})*(?:\.\d{2})?)</span>` and strip commas before parsing.

## [Severity: Medium] Empty RAM/storage arrays yield silent "Unknown"
- **File:** modules/HardwareDetection.psm1:24-25, 44
- **Issue:** When CIM returns zero sticks or disks, downstream speed/size comparisons against `$null` collapse into "Unknown" with no diagnostic.
- **Repro:** Run under WinPE/USB boot where storage or memory enumeration is empty.
- **Fix:** Add `if ($ramSticks.Count -eq 0) { ... }` / `if ($disks.Count -eq 0) { ... }` fallbacks with explicit messaging.

## [Severity: Medium] Battery query failures silenced
- **File:** modules/HardwareDetection.psm1:165-170
- **Issue:** Errors from `BatteryFullChargedCapacity`/`BatteryStaticData` are silently swallowed, so desktops (and laptops with missing WMI classes) see no battery line at all.
- **Repro:** Run on a desktop — the report omits battery info without explaining why.
- **Fix:** Emit `Write-Verbose`/`Write-Host` note when battery queries are unavailable.

## [Severity: Low] README depreciation model misdescribes implementation
- **File:** README.md:101 vs modules/Valuation.psm1:158-172
- **Issue:** README reads as additive ("30% year 1, 20% year 2, …") but the code is multiplicative on the remaining value, giving different numbers than readers expect.
- **Repro:** Compare README sample output to actual runs on a 2–3 year-old machine.
- **Fix:** Reword the README section or change the model to match.

## [Severity: Low] eBay request timeout surfaces no explanation
- **File:** modules/OnlineLookup.psm1:53
- **Issue:** 10s timeout catches silently; user sees "No data found" without knowing the network stalled.
- **Repro:** Run over a slow VPN or captive-portal Wi-Fi.
- **Fix:** `Write-Verbose "Online lookup timed out after 10s"` in the catch.

## [Severity: Low] Display-detection fallback swallows Add-Type errors
- **File:** modules/HardwareDetection.psm1:183-192
- **Issue:** When GPU resolution is blank and `System.Windows.Forms` load fails, the error is eaten and "Unknown" returned with no hint why.
- **Repro:** Minimal .NET install or constrained language mode.
- **Fix:** Log `Write-Verbose "Display detection via WinForms failed: $_"` in the catch.
