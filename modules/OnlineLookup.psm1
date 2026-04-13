function Get-OnlineEstimate {
    [CmdletBinding()]
    param(
        [PSCustomObject]$Specs,
        [PSCustomObject]$OfflineValuation
    )

    Write-Verbose "Attempting online price lookup..."

    # Build search query from specs
    $queryParts = @()
    if ($Specs.Manufacturer -and $Specs.Manufacturer -notmatch 'System manufacturer|To Be Filled|Default') {
        $queryParts += $Specs.Manufacturer
    }
    if ($Specs.Model -and $Specs.Model -notmatch 'System Product|To Be Filled|Default') {
        $queryParts += $Specs.Model
    }

    # Add key specs to narrow search
    $cpuShort = $Specs.CPU.Name -replace '\(R\)|\(TM\)|CPU|Processor|@.*$', '' -replace '\s+', ' '
    $cpuShort = $cpuShort.Trim()
    if ($cpuShort.Length -gt 30) { $cpuShort = $cpuShort.Substring(0, 30).Trim() }

    $queryParts += $cpuShort
    $queryParts += "$($Specs.RAM.TotalGB)GB"

    $primaryStorage = $Specs.Storage | Sort-Object SizeGB -Descending | Select-Object -First 1
    if ($primaryStorage) {
        $queryParts += "$($primaryStorage.SizeGB)GB $($primaryStorage.MediaType)"
    }

    $searchQuery = ($queryParts -join ' ').Trim()
    $searchQuery += " used $($Specs.SystemType)"

    Write-Verbose "  Search query: $searchQuery"

    $result = [PSCustomObject]@{
        Success      = $false
        SearchQuery  = $searchQuery
        OnlinePrice  = $null
        Source       = $null
        BlendedLow   = $OfflineValuation.LowEstimate
        BlendedMid   = $OfflineValuation.MidEstimate
        BlendedHigh  = $OfflineValuation.HighEstimate
    }

    # Try eBay completed listings via web search
    try {
        $encodedQuery = [System.Net.WebUtility]::UrlEncode($searchQuery)
        $ebayUrl = "https://www.ebay.com/sch/i.html?_nkw=$encodedQuery&_sop=13&LH_Complete=1&LH_Sold=1&_ipg=25"

        Write-Verbose "  Fetching eBay sold listings..."
        $response = Invoke-WebRequest -Uri $ebayUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop

        # Parse prices from the response
        $prices = @()
        $priceMatches = [regex]::Matches($response.Content, '\$(\d{1,4}(?:\.\d{2})?)</span>')
        foreach ($match in $priceMatches) {
            $price = [double]$match.Groups[1].Value
            if ($price -ge 20 -and $price -le 5000) {
                $prices += $price
            }
        }

        if ($prices.Count -ge 3) {
            # Remove outliers (top/bottom 20%)
            $sorted = $prices | Sort-Object
            $trimCount = [math]::Max(1, [math]::Floor($sorted.Count * 0.2))
            $trimmed = $sorted[$trimCount..($sorted.Count - $trimCount - 1)]

            $avgOnline = [math]::Round(($trimmed | Measure-Object -Average).Average, 0)
            Write-Verbose "  Found $($prices.Count) sold listings, trimmed avg: $$avgOnline"

            $result.Success = $true
            $result.OnlinePrice = $avgOnline
            $result.Source = "eBay Sold Listings ($($prices.Count) results)"

            # Blend: 60% online, 40% offline
            $blendedMid = [math]::Round($avgOnline * 0.6 + $OfflineValuation.MidEstimate * 0.4, 0)
            $result.BlendedLow = [math]::Round($blendedMid * 0.85, 0)
            $result.BlendedMid = $blendedMid
            $result.BlendedHigh = [math]::Round($blendedMid * 1.15, 0)
        } else {
            Write-Verbose "  Not enough sold listings found ($($prices.Count)), using offline estimate."
        }
    } catch {
        Write-Verbose "  Online lookup failed: $($_.Exception.Message)"
    }

    return $result
}

Export-ModuleMember -Function Get-OnlineEstimate
