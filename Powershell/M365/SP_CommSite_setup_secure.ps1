<#
.SYNOPSIS
Provision a standalone SharePoint Online communication site with a secure “HR Secure Share” library:
- Creates/validates site, sets sharing policy, creates library with versioning + unique permissions
- Creates site groups (Owners/Members), assigns library-level roles, optionally applies a Purview retention label
- Optional Teams “Website” tab pin to the library (only if -PinInTeams is used)
- Supports preflight (-PreflightOnly), -WhatIf planning, and requires explicit -Ack to perform changes
FIXES/APPLIED:
- Use Add-PnPListRoleAssignment for library-scope permissions (replaces non-portable Set-PnPGroupPermissions).
- For Communication Sites, remove unsupported -Owner on New-PnPSite and add owner via Add-PnPSiteCollectionAdmin.
- Use Set-PnPLabel (correct cmdlet) to apply retention labels to a library.
- Pass Graph scopes as an array, not a single comma-delimited string.
- More defensive connects/disconnects and messaging.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
  [Parameter(Mandatory = $true)][string]$TenantName,           # e.g. gmppros
  [Parameter(Mandatory = $true)][string]$SiteTitle,            # e.g. "HR Secure Share"
  [Parameter(Mandatory = $true)][string]$SiteUrlPath,          # e.g. "sites/hr-secure-share"
  [Parameter(Mandatory = $true)][string]$PrimaryOwnerUPN,      # bootstrap site collection admin
  [Parameter(Mandatory = $true)][string[]]$GmpHrOwners,        # Full Control on library
  [Parameter(Mandatory = $true)][string[]]$ZelleContributors,  # Contribute on library

  [ValidateSet('Disabled','ExternalUserSharingOnly','ExistingExternalUserSharingOnly','ExternalUserAndGuestSharing')]
  [string]$SiteSharingCapability = 'ExistingExternalUserSharingOnly',

  [string]$RetentionLabelName = '',

  [switch]$PreflightOnly,

  [switch]$PinInTeams,
  [string]$TeamDisplayName,
  [string]$ChannelDisplayName = 'General',

  [string]$Ack
)

begin {
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  function Write-Info([string]$m){ Write-Host $m -ForegroundColor Cyan }
  function Write-Green([string]$m){ Write-Host $m -ForegroundColor Green }
  function Write-Yellow([string]$m){ Write-Host $m -ForegroundColor Yellow }

  # URLs & constants
  $TenantRootUrl  = "https://$TenantName.sharepoint.com"
  $TenantAdminUrl = "https://$TenantName-admin.sharepoint.com"
  $SiteUrl        = "$TenantRootUrl/$SiteUrlPath"
  $LibraryTitle   = "HR Secure Share"
  $OwnersGroupName  = "$LibraryTitle Owners"
  $MembersGroupName = "$LibraryTitle Members"

  # PnP.PowerShell (prefer user-scoped)
  try {
    $usrPnP = (Get-Module -ListAvailable PnP.PowerShell |
      Where-Object { $_.ModuleBase -like "$env:USERPROFILE*" } |
      Sort-Object Version -Descending | Select-Object -First 1).Path
    if ($usrPnP) { Import-Module $usrPnP -Force } else { Import-Module PnP.PowerShell -Force }
  } catch {
    Write-Error "PnP.PowerShell module not available: $($_.Exception.Message)"; exit 2
  }

  # Optional Graph modules if Teams pin requested
  if ($PinInTeams) {
    try {
      if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) { Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber }
      if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Teams))          { Install-Module Microsoft.Graph.Teams          -Scope CurrentUser -Force -AllowClobber }
      Import-Module Microsoft.Graph.Authentication -Force
      Import-Module Microsoft.Graph.Teams -Force
    } catch {
      Write-Yellow "Graph modules not ready; Teams tab step may be skipped: $($_.Exception.Message)"
    }
  }

  function Connect-SPOAdmin {
    Write-Info "Connecting to SharePoint Admin: $TenantAdminUrl"
    Connect-PnPOnline -Url $TenantAdminUrl -Interactive -Tenant "$TenantName.onmicrosoft.com"
  }

  function Connect-SPOSite {
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
      Write-Yellow "Graph Users not available; skipping identity lookups (non-blocking)."
      return $false
    }
  }

  function Require-Ack {
    param([string]$AckValue)
    if ($PreflightOnly -or $WhatIfPreference) { return }
    if ($AckValue -ne 'ACK: proceed site-provision') {
      throw "Missing explicit ACK. Re-run with -Ack 'ACK: proceed site-provision' (or use -PreflightOnly / -WhatIf)."
    }
  }
}

process {
  # ---------- PRE-FLIGHT ----------
  function Run-Preflight {
    $issues = @()

    try { Connect-SPOAdmin; Disconnect-PnPOnline } catch { $issues += "Cannot connect to SPO Admin: $($_.Exception.Message)" }

    try {
      Connect-SPOAdmin
      $exists = Get-PnPTenantSite -Url $SiteUrl -ErrorAction SilentlyContinue
      Disconnect-PnPOnline
      if ($exists) { Write-Yellow "Site already exists at $SiteUrl (ok if you’re re-running)." }
    } catch { $issues += "Failed to check site existence: $($_.Exception.Message)" }

    $graphOK = Test-GraphUsersReady
    if ($graphOK) {
      try {
        $o = Get-MgUser -UserId $PrimaryOwnerUPN -ErrorAction SilentlyContinue
        if (-not $o) { $issues += "Owner not found in Graph: $PrimaryOwnerUPN" }
      } catch { Write-Yellow "Graph lookup failed for owner $PrimaryOwnerUPN: $($_.Exception.Message)" }
      foreach ($g in $ZelleContributors) {
        try {
          $u = Get-MgUser -UserId $g -ErrorAction SilentlyContinue
          if (-not $u) { Write-Yellow "Guest not found (SPO can still resolve/invite): $($g)" }
        } catch { Write-Yellow "Graph lookup failed for guest $($g): $($_.Exception.Message)" }
      }
    }

    if ($issues.Count -gt 0) { Write-Warning "PRE-FLIGHT issues:`n - " + ($issues -join "`n - "); return $false }
    Write-Green "Pre-flight checks passed."
    return $true
  }

  if ($PreflightOnly) { if (Run-Preflight) { exit 0 } else { exit 3 } }

  try { Require-Ack -AckValue $Ack } catch { Write-Error $_; exit 4 }

  # ---------- PROVISIONING ----------
  try {
    Run-Preflight | Out-Null

    if ($PSCmdlet.ShouldProcess($SiteUrl, "Create Communication Site")) {
      try {
        Connect-SPOAdmin
        # New-PnPSite -Type CommunicationSite does not accept -Owner; add owner afterward
        New-PnPSite -Type CommunicationSite -Title $SiteTitle -Url $SiteUrl -ErrorAction Stop | Out-Null
        # Make the specified UPN a site collection admin
        Add-PnPSiteCollectionAdmin -Owners $PrimaryOwnerUPN -ErrorAction Stop
        Disconnect-PnPOnline
      } catch {
        Write-Yellow "Site create skipped/failed (likely exists): $($_.Exception.Message)"
        Disconnect-PnPOnline -ErrorAction SilentlyContinue
      }
    }

    if ($PSCmdlet.ShouldProcess($SiteUrl, "Set SharingCapability: $SiteSharingCapability")) {
      Connect-SPOAdmin
      Set-PnPTenantSite -Url $SiteUrl -SharingCapability $SiteSharingCapability
      Disconnect-PnPOnline
    }

    $siteExists = $false
    Connect-SPOAdmin
    try { $siteExists = [bool](Get-PnPTenantSite -Url $SiteUrl -ErrorAction SilentlyContinue) } finally { Disconnect-PnPOnline }
    if ($WhatIfPreference -and -not $siteExists) { Write-Yellow "WhatIf: site not present yet; skipping site+library steps."; exit 0 }

    Connect-SPOSite

    if ($PSCmdlet.ShouldProcess($LibraryTitle, "Create Library + Versioning + Unique Permissions")) {
      $lib = Get-PnPList -Identity $LibraryTitle -ErrorAction SilentlyContinue
      if (-not $lib) { New-PnPList -Title $LibraryTitle -Template DocumentLibrary -OnQuickLaunch | Out-Null }

      # Versioning and unique permissions
      Set-PnPList -Identity $LibraryTitle -EnableVersioning:$true -MajorVersions 500
      Set-PnPList -Identity $LibraryTitle -BreakRoleInheritance:$true -CopyRoleAssignments:$false -ClearSubscopes:$true

      # Ensure site groups
      if (-not (Get-PnPGroup -Identity $OwnersGroupName  -ErrorAction SilentlyContinue)) { New-PnPGroup -Title $OwnersGroupName  | Out-Null }
      if (-not (Get-PnPGroup -Identity $MembersGroupName -ErrorAction SilentlyContinue)) { New-PnPGroup -Title $MembersGroupName | Out-Null }

      foreach ($u in $GmpHrOwners)       { Add-PnPGroupMember -Identity $OwnersGroupName  -LoginName $u -ErrorAction SilentlyContinue }
      foreach ($u in $ZelleContributors) { Add-PnPGroupMember -Identity $MembersGroupName -LoginName $u -ErrorAction SilentlyContinue }

      # Library-scope permissions via role assignments
      $ownersGroup  = Get-PnPGroup -Identity $OwnersGroupName
      $membersGroup = Get-PnPGroup -Identity $MembersGroupName
      Add-PnPListRoleAssignment -List $LibraryTitle -Principal $ownersGroup  -RoleDefinition "Full Control"
      Add-PnPListRoleAssignment -List $LibraryTitle -Principal $membersGroup -RoleDefinition "Contribute"

      # Optional retention label on the library (use Set-PnPLabel for retention labels)
      if ($RetentionLabelName) {
        try {
          Set-PnPLabel -List $LibraryTitle -RetentionLabel $RetentionLabelName -SyncToItems:$true -ErrorAction Stop
          Write-Green "Applied retention label '$RetentionLabelName'."
        } catch {
          Write-Yellow "Retention label apply failed/skipped: $($_.Exception.Message)"
        }
      }
    }

    # Output URLs
    $web   = Get-PnPWeb
    $list  = Get-PnPList -Identity $LibraryTitle
    $HostRoot  = Get-HostRoot $web.Url
    $LibRootUrl = $HostRoot + (Get-PnPProperty -ClientObject $list -Property RootFolder).ServerRelativeUrl
    $LibViewUrl = $HostRoot + $list.DefaultViewUrl

    Write-Green "DONE. Site: $SiteUrl"
    Write-Green "Library (root): $LibRootUrl"
    Write-Green "Library (view): $LibViewUrl"

    if ($PinInTeams) {
      try {
        Connect-MgGraph -Scopes @(
          "Group.ReadWrite.All",
          "TeamsAppInstallation.ReadWriteForTeam",
          "TeamsTab.ReadWriteForTeam"
        ) -NoWelcome

        $teamGroup = Get-MgGroup -Filter "displayName eq '$TeamDisplayName' and resourceProvisioningOptions/Any(x:x eq 'Team')" -ConsistencyLevel eventual -CountVariable c
        if (-not $teamGroup) { throw "Team '$TeamDisplayName' not found." }
        $teamId = $teamGroup.Id
        $channel = Get-MgTeamChannel -TeamId $teamId | Where-Object { $_.DisplayName -eq $ChannelDisplayName }
        if (-not $channel) { throw "Channel '$ChannelDisplayName' not found in '$TeamDisplayName'." }

        # Teams Website app
        $websiteAppId = "06805b9e-77e3-4b93-ac81-525eb87513b8"
        New-MgTeamInstalledApp -TeamId $teamId -BodyParameter @{ "teamsApp@odata.bind" = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/$websiteAppId" } -ErrorAction SilentlyContinue | Out-Null
        New-MgTeamChannelTab -TeamId $teamId -ChannelId $channel.Id -BodyParameter @{
          displayName = $LibraryTitle
          "teamsApp@odata.bind" = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/$websiteAppId"
          configuration = @{ websiteUrl = $LibViewUrl; contentUrl = $LibViewUrl }
        } | Out-Null

        Write-Green "Pinned Teams tab '$LibraryTitle' in $TeamDisplayName / $ChannelDisplayName"
      } catch {
        Write-Yellow "Teams tab skipped: $($_.Exception.Message)"
      }
    }

    exit 0
  }
  catch {
    Write-Error "Provisioning failed: $($_.Exception.Message)"; exit 5
  }
  finally {
    try { Disconnect-PnPOnline } catch {}
    try { Disconnect-MgGraph } catch {}
  }
}
