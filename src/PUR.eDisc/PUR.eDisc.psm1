# PUR.eDisc.psm1
# Microsoft Purview eDiscovery (Standard) helper module

# --- Helpers ---
function Ensure-Module { ... }
function Connect-PurviewSafely { ... }
function New-KqlQuery { ... }
function Ensure-Case { ... }
function Ensure-Search { ... }
function Start-SearchAndWait { ... }
function Start-Export { ... }
function Append-ChainLogRow { ... }

# --- Orchestration (public entrypoint) ---
function Invoke-PURLitigationSearch {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string] $UserPrincipalName,
        [switch] $ConnectOnly,
        [string] $TicketNumber,
        [string[]] $Custodians,
        [datetime] $StartDate,
        [datetime] $EndDate,
        [string] $Requestor,
        [switch] $IncludeSharePoint,
        [ValidateSet('FxStream','Pst','IndividualMessages')] [string] $ExportFormat = 'FxStream',
        [string] $CaseName,
        [string] $SearchName,
        [string] $ExportName,
        [string] $Keywords,
        [string] $TranscriptPath = (Join-Path (Join-Path $PWD 'Logs') ("PurviewSOP_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))),
        [string] $ChainLogPath   = (Join-Path $PWD 'ChainOfCustody.csv')
    )

    try {
        # transcript + prerequisites
        if ($TranscriptPath) {
            $tDir = Split-Path -Parent $TranscriptPath
            if ($tDir -and -not (Test-Path $tDir)) { New-Item -ItemType Directory -Path $tDir -Force | Out-Null }
            Start-Transcript -Path $TranscriptPath -ErrorAction SilentlyContinue | Out-Null
        }

        Ensure-Module -Name ExchangeOnlineManagement -MinVersion '3.2.0'
        Connect-PurviewSafely -UPN $UserPrincipalName
        if ($ConnectOnly) { return }

        # derive names
        $caseName   = if ($CaseName)   { $CaseName }   else { "CASE_$TicketNumber" }
        $searchName = if ($SearchName) { $SearchName } else { "SEARCH_$TicketNumber" }
        $exportName = if ($ExportName) { $ExportName } else { "EXPORT_$TicketNumber" }

        # run steps
        $case   = Ensure-Case -Name $caseName
        $kql    = New-KqlQuery -People $Custodians -From $StartDate -To $EndDate -Keywords $Keywords
        $search = Ensure-Search -Name $searchName -Case $case.Name -ExchangeLocations $Custodians -IncludeSP:$IncludeSharePoint -Kql $kql
        $completed = Start-SearchAndWait -SearchName $search.Name
        Start-Export -SearchName $search.Name -ActionName $exportName -Format $ExportFormat
        Append-ChainLogRow -CsvPath $ChainLogPath -Ticket $TicketNumber -Requestor $Requestor -Case $case.Name -Search $search.Name -Export $exportName
    }
    finally {
        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
}
