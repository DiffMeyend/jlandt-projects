# SPO.SecureSite.psm1

function Write-Info { param([string]$m) Write-Host $m -ForegroundColor Cyan }
function Write-Green { param([string]$m) Write-Host $m -ForegroundColor Green }
function Write-Yellow { param([string]$m) Write-Host $m -ForegroundColor Yellow }

function Connect-SPOAdmin {
    param([string]$TenantName)
    $TenantAdminUrl = "https://$TenantName-admin.sharepoint.com"
    Write-Info "Connecting to SharePoint Admin: $TenantAdminUrl"
    Connect-PnPOnline -Url $TenantAdminUrl -Interactive -Tenant "$TenantName.onmicrosoft.com"
}

function Connect-SPOSite {
    param([string]$TenantName, [string]$SiteUrlPath)
    $SiteUrl = "https://$TenantName.sharepoint.com/$SiteUrlPath"
    Write-Info "Connecting to Site: $SiteUrl"
    Connect-PnPOnline -Url $SiteUrl -Interactive -Tenant "$TenantName.onmicrosoft.com"
}

function Get-HostRoot([string]$absWebUrl) {
    $u = [uri]$absWebUrl
    return ('{0}://{1}' -f $u.Scheme, $u.Host)
}

function Test-GraphUsersReady {
    try {
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        Connect-MgGraph -Scopes "User.Read.All" -NoWelcome | Out-Null
        return $true
    } catch {
        Write-Yellow "Graph Users not available; skipping identity lookups."
        return $false
    }
}

function Require-Ack {
    param([string]$AckValue, [switch]$PreflightOnly, [switch]$WhatIfPreference)
    if ($PreflightOnly -or $WhatIfPreference) { return }
    if ($AckValue -ne 'ACK: proceed site-provision') {
        throw "Missing explicit ACK. Re-run with -Ack 'ACK: proceed site-provision'."
    }
}

function New-HRSiteProvisioning {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][string]$TenantName,           # e.g. contoso
        [Parameter(Mandatory)][string]$SiteTitle,            # e.g. "HR Secure Share"
        [Parameter(Mandatory)][string]$SiteUrlPath,          # e.g. "sites/hr-secure-share"
        [Parameter(Mandatory)][string]$PrimaryOwnerUPN,      # e.g. owner@contoso.com
        [Parameter(Mandatory)][string[]]$HrOwners,           # owners for library
        [Parameter(Mandatory)][string[]]$Contributors,       # contributors for library

        [ValidateSet('Disabled','ExternalUserSharingOnly','ExistingExternalUserSharingOnly','ExternalUserAndGuestSharing')]
        [string]$SiteSharingCapability = 'ExistingExternalUserSharingOnly',

        [string]$RetentionLabelName = '',

        [switch]$PreflightOnly,

        [switch]$PinInTeams,
        [string]$TeamDisplayName,
        [string]$ChannelDisplayName = 'General',

        [string]$Ack
    )

    # construct URLs from TenantName
    $TenantRootUrl  = "https://$TenantName.sharepoint.com"
    $TenantAdminUrl = "https://$TenantName-admin.sharepoint.com"
    $SiteUrl        = "$TenantRootUrl/$SiteUrlPath"

    # rest of your orchestration logic here...
}
