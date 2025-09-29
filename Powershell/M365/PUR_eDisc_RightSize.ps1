<#
.SYNOPSIS
Right-sized Purview eDiscovery (Standard) helper that follows an SOP lifecycle:
Create/Reuse Case → Create/Run Search → (optional) Export → Chain-of-Custody logging.
Supports -WhatIf for safe planning and -Confirm for real actions. Includes fixes:
- Proper CSV headers on first write
- Explicit IPPSSession cleanup
- Module min-version check
- More robust KQL date filtering
- Defensive size parsing in search status
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
  [Parameter(Mandatory=$true)]
  [string]$TicketNumber,

  [Parameter(Mandatory=$true)]
  [string[]]$Custodians,

  [Parameter(Mandatory=$true)]
  [datetime]$StartDate,

  [Parameter(Mandatory=$true)]
  [datetime]$EndDate,

  [Parameter()]
  [string]$Requestor,

  [Parameter()]
  [ValidateSet('FxStream','Pst','IndividualMessages')]
  [string]$ExportFormat = 'FxStream',

  [Parameter()]
  [switch]$IncludeSharePoint,

  [Parameter()]
  [string]$CaseName,

  [Parameter()]
  [string]$SearchName,

  [Parameter()]
  [string]$ExportName,

  [Parameter()]
  [string]$ChainLogPath = (Join-Path -Path (Resolve-Path '.').Path -ChildPath 'ChainOfCustody.csv'),

  [Parameter()]
  [string]$TranscriptPath = (Join-Path -Path (Resolve-Path '.').Path -ChildPath ("PurviewSOP_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".txt"))
)

#region Helpers
function Write-Log {
  param([string]$Message)
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$ts] $Message"
}

function Ensure-Module {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter()][version]$MinVersion = '3.0.0'
  )
  $m = Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
  if (-not $m -or [version]$m.Version -lt $MinVersion) {
    throw "Required module '$Name' (≥ $MinVersion) is not available."
  }
}

function New-KqlQuery {
  param(
    [string[]]$Addresses,
    [datetime]$FromDate,
    [datetime]$ToDate
  )
  # Build ((from:"a") OR (to:"a") OR (from:"b") OR (to:"b")) AND received>="YYYY-MM-DD" AND received<="YYYY-MM-DD"
  $terms = foreach($a in $Addresses){
    "(from:`"$a`")"; "(to:`"$a`")"
  }
  $addrClause = '(' + ($terms -join ' OR ') + ')'
  $dateClause = @(
    'received>="' + ($FromDate.ToString('yyyy-MM-dd')) + '"'
    'received<="' + ($ToDate.ToString('yyyy-MM-dd')) + '"'
  ) -join ' AND '
  return "$addrClause AND $dateClause"
}

function Connect-Compliance {
  [CmdletBinding()] param()
  Write-Log "Connecting to Purview Compliance PowerShell (IPPSSession)…"
  Import-Module ExchangeOnlineManagement -ErrorAction Stop
  Connect-IPPSSession -ShowBanner:$false -ErrorAction Stop | Out-Null
}

function Ensure-Case {
  [CmdletBinding(SupportsShouldProcess=$true)]
  param([string]$Name,[string]$Description)
  $existing = $null
  try { $existing = Get-ComplianceCase -Identity $Name -ErrorAction Stop } catch { $existing = $null }
  if ($existing) { Write-Log "Case '$Name' exists → reusing."; return $existing }
  if ($PSCmdlet.ShouldProcess("Case '$Name'",'New-ComplianceCase')) {
    return New-ComplianceCase -Name $Name -Description $Description
  } else {
    Write-Log "PLAN: Create case '$Name' with description '$Description'"
  }
}

function Ensure-Search {
  [CmdletBinding(SupportsShouldProcess=$true)]
  param(
    [string]$CaseName,
    [string]$Name,
    [string[]]$ExchangeLocations,
    [string]$Kql,
    [switch]$IncludeSPO
  )
  $finalName = $Name
  $existing = $null
  try { $existing = Get-ComplianceSearch -Identity $Name -ErrorAction Stop } catch { $existing = $null }
  if ($existing) {
    $suffix = Get-Date -Format 'yyyyMMddHHmmss'
    $finalName = "$Name-$suffix"
    Write-Log "Search '$Name' already exists → using '$finalName'."
  }
  Write-Log "KQL: $Kql"
  Write-Log ("Scope: Exchange=" + ($ExchangeLocations -join ',') + (if($IncludeSPO) '; SharePoint=All, OneDrive=All' else ''))
  if ($PSCmdlet.ShouldProcess("Search '$finalName' in case '$CaseName'",'New-ComplianceSearch + Start-ComplianceSearch')) {
    $params = @{
      Name = $finalName
      Case = $CaseName
      ExchangeLocation = $ExchangeLocations
      ContentMatchQuery = $Kql
      AllowNotFoundExchangeLocationsIncluded = $true
    }
    if ($IncludeSPO) { $params.SharePointLocation = 'All'; $params.OneDriveLocation = 'All' }
    $search = New-ComplianceSearch @params
    Start-ComplianceSearch -Identity $search.Name | Out-Null
    return $search.Name
  } else {
    Write-Log "PLAN: Create search '$finalName' in case '$CaseName' with KQL above, then start it."
    return $finalName
  }
}

function Wait-SearchCompletion {
  [CmdletBinding()] param([string]$Identity)
  Write-Log "Waiting for search '$Identity' to complete…"
  do {
    $s = Get-ComplianceSearch -Identity $Identity
    $sizeMb = try { [math]::Round(([double]$s.Size)/1MB, 2) } catch { $null }
    Write-Log ("Status={0}, Items={1}, SizeMB={2}" -f $s.Status, $s.Items, ($sizeMb ?? 'n/a'))
    if ($s.Status -in 'Completed','PartiallySucceeded','Failed') { break }
    Start-Sleep -Seconds 10
  } while ($true)
  return $s
}

function Invoke-Export {
  [CmdletBinding(SupportsShouldProcess=$true)]
  param([string]$SearchName,[string]$ExportName,[string]$Format)
  if ($PSCmdlet.ShouldProcess("Export '$ExportName' for search '$SearchName'",'New-ComplianceSearchAction -Export')) {
    $action = New-ComplianceSearchAction -SearchName $SearchName -Export -Format $Format -Name $ExportName -ErrorAction Stop
    Write-Log "Export job created: $($action.Identity)"
    return $action
  } else {
    Write-Log "PLAN: Create export '$ExportName' (Format=$Format) for search '$SearchName'"
  }
}

function Write-ChainLog {
  [CmdletBinding()] param(
    [string]$Case,
    [string]$Search,
    [string]$ExportName,
    [string]$ExportIdentity,
    [string]$Ticket,
    [string]$Requestor,
    [string]$LogPath
  )
  $row = [pscustomobject]@{
    Timestamp      = (Get-Date).ToString('o')
    Case           = $Case
    Search         = $Search
    ExportName     = $ExportName
    ExportIdentity = $ExportIdentity
    Ticket         = $Ticket
    Requestor      = $Requestor
    Operator       = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  }
  $exists = Test-Path $LogPath
  if ($exists) { $row | Export-Csv -Path $LogPath -Append -NoTypeInformation }
  else         { $row | Export-Csv -Path $LogPath -NoTypeInformation }
  Write-Log ("Chain log {0}: {1}" -f ($(if($exists){'updated'}else{'created'}), $LogPath))
}
#endregion Helpers

#region Orchestration
try {
  Start-Transcript -Path $TranscriptPath -ErrorAction SilentlyContinue | Out-Null

  Ensure-Module -Name ExchangeOnlineManagement -MinVersion 3.0.0
  Connect-Compliance

  # Derive friendly names when not supplied
  if (-not $CaseName) {
    $cust = ($Custodians -join ', ')
    $CaseName = "${TicketNumber} – $cust"
  }
  if (-not $SearchName) {
    $SearchName = "Email Search – " + ($Custodians -join '+') + " – " + (Get-Date -Date $StartDate -Format 'yyyy-MM')
  }
  if (-not $ExportName) {
    $ExportName = "$TicketNumber – $((Get-Date -Date $StartDate -Format 'yyyy-MM-dd'))..$((Get-Date -Date $EndDate -Format 'yyyy-MM-dd'))"
  }

  $description = "Ticket #$TicketNumber – $Requestor – Custodians: $($Custodians -join ', ') – Range: $($StartDate.ToString('yyyy-MM-dd'))..$($EndDate.ToString('yyyy-MM-dd'))"
  $null = Ensure-Case -Name $CaseName -Description $description

  $kql = New-KqlQuery -Addresses $Custodians -FromDate $StartDate -ToDate $EndDate
  $searchId = Ensure-Search -CaseName $CaseName -Name $SearchName -ExchangeLocations $Custodians -Kql $kql -IncludeSPO:$IncludeSharePoint

  # If the search was actually started (not just planned), wait and show stats
  $s = $null
  try { $s = Wait-SearchCompletion -Identity $searchId } catch { Write-Log "Search not started (WhatIf/plan-only)." }

  if ($s) {
    Write-Host "`n===== SEARCH SUMMARY ====="
    $summary = [pscustomobject]@{
      Name   = $s.Name
      Status = $s.Status
      Items  = $s.Items
      SizeMB = try { [math]::Round(([double]$s.Size)/1MB, 2) } catch { $null }
    }
    $summary | Format-Table -AutoSize | Out-Host
  }

  # Export stage
  $export = Invoke-Export -SearchName $searchId -ExportName $ExportName -Format $ExportFormat
  if ($export) {
    Write-ChainLog -Case $CaseName -Search $searchId -ExportName $ExportName -ExportIdentity $export.Identity -Ticket $TicketNumber -Requestor $Requestor -LogPath $ChainLogPath
  }
}
finally {
  # Clean up IPPSSession and transcript
  try { Get-PSSession | Where-Object { $_.Name -like 'IPPSSession*' } | Remove-PSSession -ErrorAction SilentlyContinue } catch {}
  try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
  try { Stop-Transcript | Out-Null } catch {}
}
#endregion Orchestration
