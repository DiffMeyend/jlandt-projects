<#
TL;DR — LiteRefresh-ADOnly.ps1 (org-agnostic)
A minimal, safe desktop “lite refresh” for an old local profile. Dry-run with -WhatIf; real changes need -Ack "I understand".
Optionally creates a VPN using -CreateVpn with -VpnName/-VpnServer parameters (no hardcoded org strings).
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
  [Parameter(Mandatory=$true)][string]$OldProfile,

  # VPN (org-agnostic)
  [switch]$CreateVpn,
  [string]$VpnName   = 'Company VPN',
  [string]$VpnServer = 'vpn.example.com',

  # Safety/notes
  [string]$Ack,
  [string]$MaintenanceNote
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Runtime & logging ---
$Stamp  = (Get-Date -Format 'yyyyMMdd-HHmmss')
$OutDir = 'C:\Transfer\LiteRefresh'
$Log    = Join-Path $OutDir "LiteRefresh-$Stamp.txt"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
function Log([string]$m){ $line = "[$(Get-Date -Format 'u')] $m"; $line | Tee-Object -FilePath $Log -Append | Out-Host }
function Exists($p){ Test-Path -LiteralPath $p -PathType Any }
$DryRun = [bool]$WhatIfPreference

# --- Preflight ---
$Src = "C:\Users\$OldProfile"
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log "=== Lite Refresh start ===  OldProfile='$OldProfile'  Ack='$Ack'  WhatIf=$DryRun  Admin=$IsAdmin"
if(-not $IsAdmin){ Write-Warning 'Run as SYSTEM/Administrator.' }

# --- 0) Snapshot ---
$comp = Get-ComputerInfo | Select CsName, OsName, WindowsVersion, OsBuildNumber
$bit  = (manage-bde -status C:) 2>$null | Out-String
$join = (dsregcmd /status) 2>$null | Out-String
Log ("Device: {0}  Build: {1}" -f $comp.CsName,$comp.OsBuildNumber)
Log ("WindowsVersion: {0}" -f $comp.WindowsVersion)
Log ("BitLocker snippet: " + ($bit -split "`n" | Where-Object {$_ -match 'Protection Status|Percentage Encrypted'} | ForEach-Object {$_.Trim()} -join '; '))
Log ("DomainJoined: " + ([bool]($join -match 'DomainJoined\s*:\s*YES')))

# --- 1) Identify & optionally stage data ---
Log '--- Step 1: Profile existence & optional data staging ---'
if(-not (Exists $Src)){
  Log "Profile root not found: $Src (nothing to stage/retire)"
} else {
  $desk = Join-Path $Src 'Desktop'; $docs = Join-Path $Src 'Documents'
  $toCopy = @(); foreach($p in @($desk,$docs)){ if(Exists $p){ $toCopy += $p } }
  if($toCopy.Count -gt 0){
    $Stage = "C:\Transfer\${OldProfile}_backup"
    if($PSCmdlet.ShouldProcess($Stage,"Stage Desktop/Documents from $OldProfile") -and $Ack -eq 'I understand'){
      if($DryRun){ Log "DRY-RUN: Would copy: $($toCopy -join ', ') -> $Stage" }
      else {
        New-Item -ItemType Directory -Path $Stage -Force | Out-Null
        Copy-Item $toCopy -Destination $Stage -Recurse -Force -ErrorAction SilentlyContinue
        Log "Staged to $Stage"
      }
    } else { Log 'Staging skipped (no ACK or -WhatIf).' }
  } else { Log 'No Desktop/Documents present; skipping staging.' }
}

# --- 2) De-admin & sign-out (only if local account exists) ---
Log '--- Step 2: De-admin & sign-out (if applicable) ---'
$local = Get-LocalUser -Name $OldProfile -ErrorAction SilentlyContinue
if($local){
  if($PSCmdlet.ShouldProcess("Administrators group","Remove $OldProfile") -and $Ack -eq 'I understand'){
    if($DryRun){ Log "DRY-RUN: Remove-LocalGroupMember Administrators $OldProfile" }
    else { Try { Remove-LocalGroupMember -Group Administrators -Member $OldProfile -ErrorAction SilentlyContinue } Catch {} }
  } else { Log 'ACK missing or -WhatIf on; not changing group membership.' }
}
# active session?
$qs = quser 2>$null | Select-String -Pattern ("^\s*{0}\s+" -f [regex]::Escape($OldProfile))
if($qs){
  $fields = ($qs.Line -replace '\s{2,}','|').Trim('|').Split('|')
  if($fields.Length -ge 3){
    $sid = $fields[2]
    if($sid -match '^\d+$'){
      if($PSCmdlet.ShouldProcess("Session $sid","logoff $OldProfile") -and $Ack -eq 'I understand'){
        if($DryRun){ Log "DRY-RUN: logoff $sid /V" } else { logoff $sid /V }
      } else { Log 'ACK missing or -WhatIf on; not logging off.' }
    }
  }
}

# --- 3) Clear user app caches (Teams/OneDrive/Office) ---
Log '--- Step 3: Clear per-user app caches ---'
if(Exists $Src){
  if($PSCmdlet.ShouldProcess('Processes','Stop Teams/OneDrive/Office') -and $Ack -eq 'I understand'){
    if($DryRun){ Log 'DRY-RUN: Stop-Process Teams/OneDrive/Office' }
    else { Get-Process Teams,OneDrive,OUTLOOK,EXCEL,WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force }
  }
  $cachePaths = @(
    Join-Path $Src 'AppData\Roaming\Microsoft\Teams',
    Join-Path $Src 'AppData\Local\Microsoft\OneDrive\logs',
    Join-Path $Src 'AppData\Local\Microsoft\OneDrive\settings\Business1'
  )
  foreach($p in $cachePaths){
    if(Exists $p){
      if($PSCmdlet.ShouldProcess($p,'Remove cache folder') -and $Ack -eq 'I understand'){
        if($DryRun){ Log "DRY-RUN: Remove '$p'" } else { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
      }
    }
  }
} else { Log 'Profile root absent; skipping cache clears.' }

# --- 4) Reset browser profiles (Edge/Chrome) ---
Log '--- Step 4: Reset Edge/Chrome profiles ---'
$browserPaths = @(
  Join-Path $Src 'AppData\Local\Microsoft\Edge\User Data',
  Join-Path $Src 'AppData\Local\Google\Chrome\User Data'
)
foreach($p in $browserPaths){
  if(Exists $p){
    if($PSCmdlet.ShouldProcess($p,'Remove user data') -and $Ack -eq 'I understand'){
      if($DryRun){ Log "DRY-RUN: Remove '$p' -Recurse" } else { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
  }
}

# --- 5) Temp & Storage tidy (lightweight) ---
Log '--- Step 5: Temp & Storage tidy ---'
if($PSCmdlet.ShouldProcess('DiskCleanup task','Run SilentCleanup') -and $Ack -eq 'I understand'){
  if($DryRun){ Log "DRY-RUN: schtasks /Run /TN '\Microsoft\Windows\DiskCleanup\SilentCleanup'" }
  else { schtasks /Run /TN "\Microsoft\Windows\DiskCleanup\SilentCleanup" | Out-Null }
}
$globs = @("$Src\AppData\Local\Temp\*","$env:WINDIR\Temp\*")
foreach($glob in $globs){
  $base = Split-Path $glob.TrimEnd('*')
  if(Exists $base){
    if($PSCmdlet.ShouldProcess($glob,'Remove temp files') -and $Ack -eq 'I understand'){
      if($DryRun){ Log "DRY-RUN: Remove '$glob'" } else { Remove-Item $glob -Recurse -Force -ErrorAction SilentlyContinue }
    }
  }
}

# --- 6) Retire the old profile (only if not loaded) ---
Log '--- Step 6: Retire profile ---'
$profObj = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object LocalPath -eq $Src
if($profObj){
  Log ("Profile Loaded=$($profObj.Loaded) LastUse=$($profObj.LastUseTime)")
  if(-not $profObj.Loaded -and $Ack -eq 'I understand' -and $PSCmdlet.ShouldProcess($Src,'Remove-CimInstance (retire profile)')){
    if($DryRun){ Log "DRY-RUN: Remove-CimInstance $Src" } else { $profObj | Remove-CimInstance }
  } else { Log 'Profile loaded or ACK missing; not deleting.' }
} else { Log 'Profile object not found (already removed).' }

# --- 7) VPN presence & optional creation (org-agnostic) ---
Log '--- Step 7: VPN check & optional create ---'
$vpnAll  = Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue
$vpnUser = Get-VpnConnection -ErrorAction SilentlyContinue
$have = @($vpnAll+$vpnUser) | Where-Object { $_.Name -eq $VpnName -or $_.ServerAddress -eq $VpnServer } | Select-Object -First 1
Log ("Existing native VPN: " + $(if($have){"Yes ($($have.Name)) Status=$($have.ConnectionStatus)"}else{"No"}))
# Reachability probe (non-destructive)
try{ $dns = Resolve-DnsName $VpnServer -ErrorAction Stop | Select-Object -First 1; Log "DNS $VpnServer -> $($dns.IPAddress)" }catch{ Log "DNS failed for $VpnServer" }
$tcp443 = Test-NetConnection -ComputerName $VpnServer -Port 443 -InformationLevel Quiet
Log ("TCP 443 to $VpnServer: " + ($(if($tcp443){'OK'}else{'FAILED'})))

if($CreateVpn -and -not $have){
  if($PSCmdlet.ShouldProcess($VpnName,'Add-VpnConnection') -and $Ack -eq 'I understand'){
    if($DryRun){
      Log "DRY-RUN: Add-VpnConnection -Name '$VpnName' -ServerAddress '$VpnServer' -TunnelType SSTP -AllUserConnection -SplitTunneling:$true -AuthenticationMethod Eap,MSChapv2 -Force"
    } else {
      Try {
        Add-VpnConnection -Name $VpnName -ServerAddress $VpnServer -TunnelType SSTP -AllUserConnection -SplitTunneling $true -AuthenticationMethod Eap,MSChapv2 -Force
      } Catch { Log "Add-VpnConnection error: $_" }
    }
  } else { Log 'VPN creation skipped (either exists, no ACK, or -WhatIf).' }
}

# --- 8) Windows Update quick cycle + Defender sigs ---
Log '--- Step 8: Windows Update (quick) & Defender sigs ---'
if($PSCmdlet.ShouldProcess('Windows Update','Scan/Download/Install (UsoClient)') -and $Ack -eq 'I understand'){
  foreach($svc in 'bits','wuauserv','UsoSvc'){
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if($s -and $s.Status -ne 'Running'){
      if($DryRun){ Log "DRY-RUN: Start $svc" } else { Start-Service $svc }
    }
  }
  foreach($cmd in 'StartScan','StartDownload','StartInstall'){
    if($DryRun){ Log "DRY-RUN: UsoClient $cmd" }
    else { Start-Process "$env:SystemRoot\System32\UsoClient.exe" -ArgumentList $cmd -WindowStyle Hidden -Wait }
    Start-Sleep -Seconds 8
  }
}
$mp = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
if(Test-Path $mp){
  if($PSCmdlet.ShouldProcess('Defender','SignatureUpdate') -and $Ack -eq 'I understand'){
    if($DryRun){ Log 'DRY-RUN: Defender -SignatureUpdate' } else { Start-Process $mp -ArgumentList '-SignatureUpdate' -WindowStyle Hidden -Wait }
  }
}

# --- 9) Welcome note ---
Log '--- Step 9: Welcome note ---'
$welcome = 'C:\Users\Public\Desktop\Welcome.txt'
$note = @'
Welcome! This device has been refreshed for your account.
Sign in with your company credentials. If apps don’t appear within 15–30 minutes, connect to VPN if required.
'@
if($PSCmdlet.ShouldProcess($welcome,'Create/Update Welcome note')){
  if($DryRun){ Log "DRY-RUN: Create $welcome" } else { Set-Content -Path $welcome -Value $note }
}

# --- 10) Verification / Exit ---
$reboot = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -or
          Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$hot5 = Get-HotFix | Sort-Object InstalledOn | Select-Object -Last 5
$buildNow = (Get-ComputerInfo).OsBuildNumber
Log '=== Exit Summary ==='
Log ("Build: $buildNow  RebootPending: $reboot")
$hot5 | ForEach-Object { Log ("KB: {0}  Date: {1}" -f $_.HotFixID, $_.InstalledOn) }
if($MaintenanceNote){ Log ("Note: $MaintenanceNote") }
Log ("Log saved to: $Log")
