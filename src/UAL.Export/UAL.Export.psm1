# UAL.Export.psm1
# Unified Audit Log (UAL) export helpers

function Convert-UalToRows {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][object[]]$Records)
    process {
        foreach ($r in $Records) {
            $auditJson = $null
            if ($r.PSObject.Properties.Match('AuditData').Count -gt 0 -and $r.AuditData) {
                $auditJson = [string]$r.AuditData
            }

            $d = $null
            if ($auditJson) {
                try { $d = $auditJson | ConvertFrom-Json -ErrorAction Stop } catch { $d = $null }
            }

            $creation = $null
            if ($r.PSObject.Properties.Match('CreationDate').Count) {
                $creation = $r.CreationDate
            } elseif ($d -and $d.PSObject.Properties.Match('CreationTime').Count) {
                $creation = $d.CreationTime
            }
            if ($creation -and -not ($creation -is [datetime])) {
                try { $creation = [datetime]$creation } catch {}
            }

            $uid = $null
            if ($r.PSObject.Properties.Match('UserId').Count) {
                $uid = $r.UserId
            } elseif ($r.PSObject.Properties.Match('UserIds').Count -and $r.UserIds) {
                $uid = ($r.UserIds | Select-Object -First 1)
            } elseif ($d -and $d.PSObject.Properties.Match('UserId').Count) {
                $uid = $d.UserId
            }

            $op = $null
            if ($r.PSObject.Properties.Match('Operation').Count) {
                $op = $r.Operation
            } elseif ($r.PSObject.Properties.Match('Operations').Count -and $r.Operations) {
                $op = ($r.Operations | Select-Object -First 1)
            } elseif ($d -and $d.PSObject.Properties.Match('Operation').Count) {
                $op = $d.Operation
            }

            $orgId = $null
            if ($r.PSObject.Properties.Match('OrganizationId').Count) {
                $orgId = $r.OrganizationId
            } elseif ($d -and $d.PSObject.Properties.Match('OrganizationId').Count) {
                $orgId = $d.OrganizationId
            }

            $id = $null
            if ($r.PSObject.Properties.Match('Id').Count) {
                $id = $r.Id
            } elseif ($d -and $d.PSObject.Properties.Match('Id').Count) {
                $id = $d.Id
            }

            [pscustomobject]@{
                CreationDateUtc = $creation
                UserId          = $uid
                RecordType      = $r.RecordType
                Operation       = $op
                OrganizationId  = $orgId
                AuditDataJson   = $auditJson
                Id              = $id
            }
        }
    }
}

function Write-UalPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]       $Records,
        [Parameter(Mandatory)][pscustomobject] $Paths
    )
    if (-not $Records -or $Records.Count -eq 0) { return 0 }

    foreach ($p in @($Paths.RawCsv, $Paths.Ndjson)) {
        if ($p) {
            $dir = Split-Path -Parent $p
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        }
    }

    $rows = $Records | Convert-UalToRows

    if (Test-Path -LiteralPath $Paths.RawCsv) {
        $rows | Export-Csv -Path $Paths.RawCsv -Append -NoTypeInformation -Encoding UTF8
    } else {
        $rows | Export-Csv -Path $Paths.RawCsv -NoTypeInformation -Encoding UTF8
    }

    foreach ($j in $rows.AuditDataJson) {
        if ($null -ne $j -and $j -ne '') {
            Add-Content -Path $Paths.Ndjson -Value $j -Encoding UTF8
        }
    }

    return $rows.Count
}

function Invoke-UalSlice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]         $User,
        [Parameter(Mandatory)][datetime]       $StartUtc,
        [Parameter(Mandatory)][datetime]       $EndUtc,
        [Parameter(Mandatory)][pscustomobject] $Paths,
        [ValidateRange(1,5000)][int]           $PageSize = 5000
    )
    $ErrorActionPreference = 'Stop'

    if ($EndUtc -le $StartUtc) {
        throw "EndUtc must be greater than StartUtc."
    }

    $total = 0
    $sid   = [guid]::NewGuid().Guid
    $cmd   = 'ReturnLargeSet'

    Write-Host ("Slice: {0:o} -> {1:o}" -f $StartUtc, $EndUtc)

    do {
        $params = @{
            StartDate      = [datetime]$StartUtc
            EndDate        = [datetime]$EndUtc
            UserIds        = @($User)
            ResultSize     = $PageSize
            SessionId      = $sid
            SessionCommand = $cmd
            ErrorAction    = 'Stop'
        }

        $page = $null
        try {
            $page = Search-UnifiedAuditLog @params
        } catch {
            Write-Warning ("Search-UnifiedAuditLog failed (will stop paging): {0}" -f $_.Exception.Message)
            break
        }

        if ($page -and $page.Count -gt 0) {
            $wrote = Write-UalPage -Records $page -Paths $Paths
            $total += $wrote
            if ($cmd -eq 'ReturnLargeSet') {
                Write-Host ("  wrote {0} events (first page)" -f $wrote)
            } else {
                Write-Host ("  wrote +{0} events (next page)" -f $wrote)
            }
        } else {
            if ($cmd -eq 'ReturnLargeSet') { Write-Host "  wrote 0 events (first page)" }
        }

        $cmd = 'ReturnNextPreviewPage'
        Start-Sleep -Milliseconds 150
    }
    while ($page -and $page.Count -gt 0)

    return $total
}
