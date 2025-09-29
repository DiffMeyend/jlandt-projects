<#  
.SYNOPSIS
  Rightsized end-to-end Purview eDiscovery (Standard) helper.

.DESCRIPTION
  - PowerShell 7+ script with two parameter sets:
      • Connectivity  : Connect + permission probe, then exit
      • RunSearch     : Ensure case, build KQL, create/start search, wait, export, log row
  - Safe-by-default: SupportsShouldProcess, ConfirmImpact High, honors -WhatIf/-Confirm.
  - Minimal, friendly errors; transcript + chain-of-custody CSV.

.NOTES
  Drop-in replacement for PurviewSearch_rightsized.ps1
#>

#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'RunSearch')]
param(
  # --- Connectivity-only mode ---
  [Parameter(ParameterSetName = 'Connectivity')]
  [switch] $ConnectOnly,

  # --- Common optionals ---
  [Parameter()] [string] $UserPrincipalName,
  [Parameter()] [switch] $Help,

  # Paths (override as needed)
  [Parameter()] [string] $TranscriptPath = (Join-Path (Join-Path $PWD 'Logs') ("PurviewSOP_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))),
  [Parameter()] [string] $ChainLogPath   = (Join-Path $PWD 'ChainOfCustody.csv'),

  # --- RunSearch mode (mandatory) ---
  [Parameter(Mandatory, ParameterSetName = 'RunSearch')]
  [ValidateNotNullOrEmpty()] [string]   $TicketNumber,

  [Parameter(Mandatory, ParameterSetName = 'RunSearch')]
  [ValidateNotNullOrEmpty()] [string[]] $Custodians,

  [Parameter(Mandatory, ParameterSetName = 'RunSearch')]
  [datetime] $StartDate,

  [Parameter(Mandatory, ParameterSetName = 'RunSearch')]
  [datetime] $EndDate,

  [Parameter(Mandatory, ParameterSetName = 'RunSearch')]
  [ValidateNotNullOrEmpty()] [string] $Requestor,

  # Optionals for RunSearch
  [Parameter(ParameterSetName = 'RunSearch')] [switch] $IncludeSharePoint,
  [Parameter(ParameterSetName = 'RunSearch')] [ValidateSet('FxStream','Pst','IndividualMessages')] [string] $ExportFormat = 'FxStream',
  [Parameter(ParameterSetName = 'RunSearch')] [string] $CaseName,
  [Parameter(ParameterSetName = 'RunSearch')] [string] $SearchName,
  [Parameter(ParameterSetName = 'RunSearch')] [string] $ExportName,
  [Parameter(ParameterSetName = 'RunSearch')] [string] $Keywords
)

#region --- Helpers -------------------------------------------------------------

function Show-Usage {
  Write-Host @'
Usage:
  Connectivity test:
    .\PurviewSearch_rightsized.ps1 -ConnectOnly [-UserPrincipalName upn@domain]

  Plan a run (no changes):
    .\PurviewSearch_rightsized.ps1 -TicketNumber TST-0001 -Custodians a@contoso.com[,b@contoso.com] `
      -StartDate yyyy-mm-dd -EndDate yyyy-mm-dd -Requestor "Name" -WhatIf

  Execute (Exchange only):
    .\PurviewSearch_rightsized.ps1 -TicketNumber TST-0001 -Custodians a@contoso.com `
      -StartDate yyyy-mm-dd -EndDate yyyy-mm-dd -Requestor "Name"

  Execute (Exchange + SharePoint/OneDrive All):
    .\PurviewSearch_rightsized.ps1 -TicketNumber TST-0001 -Custodians a@contoso.com `
      -StartDate yyyy-mm-dd -EndDate yyyy-mm-dd -Requestor "Name" -IncludeSharePoint
'@
}

function Ensure-Module {
  param([Parameter(Mandatory)][string] $Name, [string] $MinVersion = '3.0.0')
  if (-not (Get-Module -ListAvailable -Name $Name)) {
    Write-Host "[INFO] Installing module: $Name (min $MinVersion)…"
    $psget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $psget) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null }
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    Install-Module -Name $Name -MinimumVersion $MinVersion -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $Name -ErrorAction Stop
}

function Connect-PurviewSafely {
  param([string] $UPN)
  $ipps = @{ ErrorAction = 'Stop' }
  if ($UPN) { $ipps.UserPrincipalName = $UPN }
  try {
    Connect-IPPSSession @ipps | Out-Null
  } catch {
    throw ('Failed to connect to Purview PowerShell. ' + $_.Exception.Message)
  }
  try {
    # Lightweight permission probe; requires eDiscovery role visibility
    Get-ComplianceCase -ErrorAction Stop | Out-Null
  } catch {
    throw ('Connected, but the account lacks eDiscovery permissions (Get-ComplianceCase failed). ' + $_.Exception.Message)
  }
}

function New-KqlQuery {
  [OutputType([string])]
  param(
    [Parameter(Mandatory)][string[]] $People,
    [Parameter(Mandatory)][datetime] $From,
    [Parameter(Mandatory)][datetime] $To,
    [string] $Keywords
  )
  $esc = $People | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { '"{0}"' -f $_ }
  $party = @()
  if ($esc.Count -gt 0) {
    $party += @("from:(" + ($esc -join ' OR ') + ")")
    $party += @("to:("   + ($esc -join ' OR ') + ")")
    $party += @("cc:("   + ($esc -join ' OR ') + ")")
    $party += @("participants:(" + ($esc -join ' OR ') + ")")
  }
  $dateRange = "received:{0}..{1}" -f ($From.ToString('yyyy-MM-dd')), ($To.ToString('yyyy-MM-dd'))
  $base = '(' + ($party -join ' OR ') + ') AND (' + $dateRange + ')'
  if ($Keywords) { $base += ' AND (' + $Keywords + ')' }
  return $base
}

function Ensure-Case {
  [CmdletBinding(SupportsShouldProcess=$true)]
  param([Parameter(Mandatory)][string]$Name)
  $existing = Get-ComplianceCase -Identity $Name -ErrorAction SilentlyContinue
  if ($existing) { return $existing }
  if ($PSCmdlet.ShouldProcess("ComplianceCase/$Name",'New-ComplianceCase')) {
    return New-ComplianceCase -Name $Name
  }
}

function Ensure-Search {
  [CmdletBinding(SupportsShouldProcess=$true)]
  param(
    [Parameter(Mandatory)][string]   $Name,
    [Parameter(Mandatory)][string]   $Case,
    [Parameter(Mandatory)][string[]] $ExchangeLocations,
    [Parameter()][switch]            $IncludeSP,
    [Parameter(Mandatory)][string]   $Kql
  )
  $finalName = $Name
  if (Get-ComplianceSearch -Identity $finalName -ErrorAction SilentlyContinue) {
    $finalName = '{0}_{1:yyyyMMdd_HHmmss}' -f $Name,(Get-Date)
  }

  if ($PSCmdlet.ShouldProcess("ComplianceSearch/$finalName",'New/Set-ComplianceSearch')) {
    # Create new search
    $search = New-ComplianceSearch -Name $finalName -Case $Case -ExchangeLocation $ExchangeLocations -ContentMatchQuery $Kql
    if ($IncludeSP) {
      # Expand to SP/OneDrive = All
      Set-ComplianceSearch -Identity $search.Name -SharePointLocation All -OneDriveLocation All
    }
    return Get-ComplianceSearch -Identity $finalName
  }
}

function Start-SearchAndWait {
  param([Parameter(Mandatory)][string] $SearchName)
  try {
    Start-ComplianceSearch -Identity $SearchName -ErrorAction Stop | Out-Null
  } catch {
    throw ('Failed to start compliance search: ' + $_.Exception.Message)
  }
  Write-Host "[INFO] Search started: $SearchName — waiting for completion…"
  for ($i=0; $i -lt 240; $i++) {
    Start-Sleep -Seconds 5
    $s = Get-ComplianceSearch -Identity $SearchName
    if ($s.Status -eq 'Completed') {
      Write-Host ("[INFO] Completed: Items={0}, Size(MB)={1:N2}" -f $s.Items, ($s.Size/1MB))
      return $s
    }
    if ($s.Status -match 'Failed|PartiallyFailed|Suspended') {
      throw "Search status is $($s.Status). Check Purview UI for details."
    }
  }
  throw "Timeout waiting for search completion after 20 minutes."
}

function Start-Export {
  param(
    [Parameter(Mandatory)][string] $SearchName,
    [Parameter(Mandatory)][string] $ActionName,
    [Parameter(Mandatory)][ValidateSet('FxStream','Pst','IndividualMessages')] [string] $Format
  )
  try {
    # Note: -Format is supported for eDiscovery (Standard) export types in modern modules.
    New-ComplianceSearchAction -SearchName $SearchName -Export -Name $ActionName -Format $Format -ErrorAction Stop | Out-Null
  } catch {
    throw ('Failed to create export action: ' + $_.Exception.Message)
  }
}

function Append-ChainLogRow {
  param(
    [Parameter(Mandatory)][string] $CsvPath,
    [Parameter(Mandatory)][string] $Ticket,
    [Parameter(Mandatory)][string] $Requestor,
    [Parameter(Mandatory)][string] $Case,
    [Parameter(Mandatory)][string] $Search,
    [Parameter(Mandatory)][string] $Export
  )
  $row = [pscustomobject]@{
    Timestamp   = (Get-Date).ToString('s')
    Ticket      = $Ticket
    Requestor   = $Requestor
    CaseName    = $Case
    SearchName  = $Search
    ExportName  = $Export
    Operator    = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  }
  $dir = Split-Path -Parent $CsvPath
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $exists = Test-Path $CsvPath
  $row | Export-Csv -Path $CsvPath -NoTypeInformation -Append:($exists)
}

#endregion Helpers --------------------------------------------------------------

#region --- Early gating --------------------------------------------------------
if ($Help) { Show-Usage; return }

switch ($PSCmdlet.ParameterSetName) {
  'Connectivity' { }
  'RunSearch'    {
    if ($StartDate -gt $EndDate) { throw 'StartDate cannot be after EndDate.' }
  }
  default { Show-Usage; return }
}

#endregion ----------------------------------------------------------------------

#region --- Prereqs + Transcript ------------------------------------------------
try {
  if ($TranscriptPath) {
    $tDir = Split-Path -Parent $TranscriptPath
    if ($tDir -and -not (Test-Path $tDir)) { New-Item -ItemType Directory -Path $tDir -Force | Out-Null }
    Start-Transcript -Path $TranscriptPath -ErrorAction SilentlyContinue | Out-Null
  }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Ensure-Module -Name ExchangeOnlineManagement -MinVersion '3.2.0'
} catch {
  Write-Error ("Prerequisite failure: " + $_.Exception.Message)
  Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
  return
}
#endregion ----------------------------------------------------------------------

#region --- Connect + permission probe -----------------------------------------
Write-Host "[INFO] Connecting to Microsoft Purview (Security & Compliance PowerShell)…"
try {
  Connect-PurviewSafely -UPN $UserPrincipalName
  Write-Host "[INFO] Connected and permissions validated."
} catch {
  Write-Error $_.Exception.Message
  Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
  return
}
if ($ConnectOnly) {
  Write-Host "[INFO] Connectivity and permission check passed. Exiting (-ConnectOnly)."
  try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
  Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
  return
}
#endregion ----------------------------------------------------------------------

#region --- Derive names --------------------------------------------------------
$caseName   = if ($CaseName)   { $CaseName }   else { "CASE_$TicketNumber" }
$searchName = if ($SearchName) { $SearchName } else { "SEARCH_$TicketNumber" }
$exportName = if ($ExportName) { $ExportName } else { "EXPORT_$TicketNumber" }
#endregion ----------------------------------------------------------------------

#region --- Ensure case ---------------------------------------------------------
try {
  $case = Ensure-Case -Name $caseName
  if (-not $case) { throw "Unable to ensure case '$caseName'." }
  Write-Host "[INFO] Using case: $($case.Name)"
} catch {
  Write-Error ("Case error: " + $_.Exception.Message)
  goto Cleanup
}
#endregion ----------------------------------------------------------------------

#region --- Build KQL -----------------------------------------------------------
$kql = New-KqlQuery -People $Custodians -From $StartDate -To $EndDate -Keywords $Keywords
Write-Host "[INFO] KQL: $kql"
#endregion ----------------------------------------------------------------------

#region --- Ensure search -------------------------------------------------------
try {
  $search = Ensure-Search -Name $searchName -Case $case.Name -ExchangeLocations $Custodians -IncludeSP:$IncludeSharePoint -Kql $kql
  if (-not $search) { throw "Unable to ensure search '$searchName'." }
  $searchName = $search.Name   # in case we timestamp-suffixed
  Write-Host "[INFO] Using search: $searchName"
} catch {
  Write-Error ("Search error: " + $_.Exception.Message)
  goto Cleanup
}
#endregion ----------------------------------------------------------------------

#region --- Start + wait --------------------------------------------------------
try {
  $completed = Start-SearchAndWait -SearchName $searchName
} catch {
  Write-Error $_.Exception.Message
  goto Cleanup
}
#endregion ----------------------------------------------------------------------

#region --- Export --------------------------------------------------------------
try {
  if ($PSCmdlet.ShouldProcess("Export/$exportName", "New-ComplianceSearchAction -Export ($ExportFormat)")) {
    Start-Export -SearchName $searchName -ActionName $exportName -Format $ExportFormat
    Write-Host "[INFO] Export action queued: $exportName ($ExportFormat)."
  }
} catch {
  Write-Error $_.Exception.Message
  goto Cleanup
}
#endregion ----------------------------------------------------------------------

#region --- Chain-of-custody row ------------------------------------------------
try {
  Append-ChainLogRow -CsvPath $ChainLogPath -Ticket $TicketNumber -Requestor $Requestor -Case $case.Name -Search $searchName -Export $exportName
  Write-Host "[INFO] Chain-of-custody updated: $ChainLogPath"
} catch {
  Write-Warning ("Failed to write chain-of-custody CSV: " + $_.Exception.Message)
}
#endregion ----------------------------------------------------------------------

:Cleanup
#region --- Cleanup -------------------------------------------------------------
try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
#endregion ----------------------------------------------------------------------
