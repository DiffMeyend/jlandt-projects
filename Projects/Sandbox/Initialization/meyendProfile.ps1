<# =====================================================================
   PowerShell 7 Profile – Full Template (with Tenant Context Awareness)
   Purpose: Shape your PS7 environment, toolbelt, and vibe
===================================================================== #>

# =========================
# 1. Environment Setup
# =========================
Set-Location "C:\Sandbox"

# Add USB module path (Sandbox sees it as C:\Sandbox\Modules)
$usbModules = "C:\Sandbox\Modules"
if (Test-Path $usbModules) {
    # Cleaner, deduped build
    $current = ($env:PSModulePath -split ';') | Where-Object { $_ }
    $env:PSModulePath = ($usbModules + $current | Select-Object -Unique) -join ';'
}


# Paths for notes + tenant config
$Global:TicketNoteRoot  = "C:\Sandbox\TicketNotes"
$Global:TenantConfigPath = "C:\Sandbox\Config\Tenants.json"

# =========================
# 2. Palettes + Theme Switcher
# =========================
$Palettes = @{
    Hacker = @{
        Time  = $PSStyle.Foreground.BrightGreen
        Path  = $PSStyle.Foreground.Green
        User  = $PSStyle.Foreground.BrightGreen
        Host  = $PSStyle.Foreground.Green
        Reset = $PSStyle.Reset
    }
    Solarized = @{
        Time  = $PSStyle.Foreground.BrightYellow
        Path  = $PSStyle.Foreground.BrightCyan
        User  = $PSStyle.Foreground.Blue
        Host  = $PSStyle.Foreground.Magenta
        Reset = $PSStyle.Reset
    }
    Neon = @{
        Time  = $PSStyle.Foreground.BrightMagenta
        Path  = $PSStyle.Foreground.BrightCyan
        User  = $PSStyle.Foreground.BrightYellow
        Host  = $PSStyle.Foreground.BrightRed
        Reset = $PSStyle.Reset
    }
}

# Pick default theme (randomize on startup)
$themes = $Palettes.Keys | Get-Random
$Global:Colors = $Palettes.$themes
Write-Host "🎲 Random theme loaded: $themes" -ForegroundColor Cyan

function prompt {
    $time  = (Get-Date -Format "HH:mm:ss")
    $path  = (Get-Location)

    # Connection flags
    $flags = @()
    if (Get-Module -Name Microsoft.Graph.Authentication -ErrorAction SilentlyContinue) {
        try {
            if (Get-MgContext) { $flags += "[G]" }
        } catch { }
    }
    if (Get-Module -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue) {
        try {
            $exoConn = Get-ConnectionInformation -ErrorAction SilentlyContinue
            if ($exoConn -and $exoConn.Connected) { $flags += "[E]" }
        } catch { }
    }
    $flagString  = if ($flags) { " " + ($flags -join '') } else { "" }
    $tenantFlag  = if ($Global:TenantName) { " [$TenantName]" } else { "" }

    return "$($Colors.User)$env:USERNAME$($Colors.Reset)@" +
           "$($Colors.Host)$env:COMPUTERNAME$($Colors.Reset) " +
           "$($Colors.Time)$time$($Colors.Reset) " +
           "$($Colors.Path)$path$($Colors.Reset)$flagString$tenantFlag`n> "
}

function Set-PromptTheme {
    param(
        [ValidateSet("Hacker","Solarized","Neon")]
        [string]$Name
    )
    $Global:Colors = $Palettes.$Name
    Write-Host "🔥 Prompt theme switched to $Name!" -ForegroundColor Green
}

# =========================
# 3. Aliases
# =========================
Set-Alias np Notepad
Set-Alias note New-TicketNote
Set-Alias npp "C:\NotepadPP\notepad++.exe"

# =========================
# 4. Module Auto-Load
# =========================
$exo = Get-Module -ListAvailable ExchangeOnlineManagement |
       Sort-Object Version -Descending |
       Select-Object -First 1
if ($exo) {
    $exoManifest = Join-Path $exo.ModuleBase "$($exo.Name).psd1"
    Import-Module $exoManifest -ErrorAction Stop
    Write-Host "✅ $($exo.Name) $($exo.Version) loaded from $exoManifest" -ForegroundColor Green
} else {
    Write-Warning "ExchangeOnlineManagement not found in $usbModules"
}

$graph = Get-Module -ListAvailable Microsoft.Graph.Authentication |
         Sort-Object Version -Descending |
         Select-Object -First 1
if ($graph) {
    $graphManifest = Join-Path $graph.ModuleBase "$($graph.Name).psd1"
    Import-Module $graphManifest -ErrorAction Stop
    Write-Host "✅ $($graph.Name) $($graph.Version) loaded from $graphManifest" -ForegroundColor Green
} else {
    Write-Warning "Microsoft.Graph.Authentication not found in $usbModules"
}

# =========================
# 5. Functions
# =========================

function Connect-M365 {
    Write-Host "Connecting to M365 services..." -ForegroundColor Green
}

function Open-Log {
    param([string]$LogDir = "C:\Sandbox\Logs")
    if (Test-Path $LogDir) { ii $LogDir }
    else { Write-Warning "Log directory not found." }
}

function Reload-Profile {
    Write-Host "🔄 Reloading PowerShell profile..." -ForegroundColor Yellow
    . "C:\Sandbox\Initialization\meyendProfile.ps1"
}

function Reload-CoreModules {
    Write-Host "🔄 Reloading core modules (EXO + Graph)..." -ForegroundColor Yellow

    # ExchangeOnlineManagement
    if (Get-Module ExchangeOnlineManagement -ErrorAction SilentlyContinue) {
        Remove-Module ExchangeOnlineManagement -Force -ErrorAction SilentlyContinue
    }
    $exo = Get-Module -ListAvailable ExchangeOnlineManagement | Sort-Object Version -Descending | Select-Object -First 1
    if ($exo) {
        Import-Module $exo.ModuleBase -ErrorAction Stop
        Write-Host "✅ ExchangeOnlineManagement $($exo.Version) reloaded" -ForegroundColor Green
    } else {
        Write-Warning "ExchangeOnlineManagement not found in $usbModules"
    }

    # Microsoft Graph
    if (Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue) {
        Remove-Module Microsoft.Graph.Authentication -Force -ErrorAction SilentlyContinue
    }
    $graph = Get-Module -ListAvailable Microsoft.Graph.Authentication | Sort-Object Version -Descending | Select-Object -First 1
    if ($graph) {
        Import-Module $graph.ModuleBase -ErrorAction Stop
        Write-Host "✅ Microsoft.Graph.Authentication $($graph.Version) reloaded" -ForegroundColor Green
    } else {
        Write-Warning "Microsoft.Graph.Authentication not found in $usbModules"
    }
}


function Disconnect-CoreModules {
    Write-Host "🔌 Disconnecting core modules (EXO + Graph)..." -ForegroundColor Yellow
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}

function Start-SLATimer { $Global:SLAStart = Get-Date; Write-Host "⏱️ SLA timer started at $SLAStart" -ForegroundColor Yellow }
function Stop-SLATimer {
    if ($Global:SLAStart) {
        $elapsed = (Get-Date) - $Global:SLAStart
        Write-Host "⏱️ SLA timer stopped — elapsed: $elapsed" -ForegroundColor Green
        Remove-Variable SLAStart -Scope Global -ErrorAction SilentlyContinue
    }
}

function New-TicketNote {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Result,
        [string]$NextStep = "None",
        [switch]$Quiet
    )
    if (-not (Test-Path $Global:TicketNoteRoot)) {
        New-Item -Path $Global:TicketNoteRoot -ItemType Directory | Out-Null
    }
    if (-not $Global:CurrentTicketLog) {
        $Global:CurrentTicketLog = Join-Path $Global:TicketNoteRoot ("TicketNotes_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
    }
    $time = Get-Date -Format "u"
    $note = "[$time] Action: $Action | Result: $Result | Next Step: $NextStep"
    if (-not $Quiet) { Write-Output $note }
    Add-Content -Path $Global:CurrentTicketLog -Value $note
}
function Export-TicketReport {
    if ($Global:CurrentTicketLog -and (Test-Path $Global:CurrentTicketLog)) {
        Write-Host "📝 Ticket Report: $Global:CurrentTicketLog" -ForegroundColor Cyan
        Get-Content $Global:CurrentTicketLog
    }
}

# =========================
# 6. Tenant Context + Helpers
# =========================

# Load tenant config
if (Test-Path $TenantConfigPath) {
    $Global:TenantConfig = Get-Content $TenantConfigPath | ConvertFrom-Json
} else {
    Write-Warning "Tenant config not found: $TenantConfigPath"
    $Global:TenantConfig = @()
}

function Set-TenantContext {
    param([Parameter(Mandatory)][string]$Name)
    $tenant = $TenantConfig | Where-Object { $_.Name -eq $Name }
    if (-not $tenant) { Write-Warning "Tenant '$Name' not found."; return }
    $Global:TenantName   = $tenant.Name
    $Global:TenantDomain = $tenant.Domain
    $Global:TenantUPN    = $tenant.UPN
    Write-Host "🔑 Context switched to $TenantName" -ForegroundColor Green
}

function Get-TenantContext {
    if (-not $TenantName) { Write-Host "No tenant context set." -ForegroundColor Yellow; return }
    Write-Host "Current tenant:" -ForegroundColor Cyan
    Write-Host "  Name:   $TenantName"
    Write-Host "  Domain: $TenantDomain"
    Write-Host "  UPN:    $TenantUPN"
}

function Connect-Tenant {
    if (-not $TenantDomain -or -not $TenantUPN) { Write-Warning "No tenant context set."; return }
    Write-Host "Connecting to $TenantName..." -ForegroundColor Cyan
    Connect-MgGraph -TenantId $TenantDomain -Scopes "User.Read.All","Directory.Read.All"
    Connect-ExchangeOnline -DelegatedOrganization $TenantDomain -UserPrincipalName $TenantUPN
    Write-Host "✅ Connected to $TenantName" -ForegroundColor Green
}

function Disconnect-Tenant {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "🔌 Disconnected from $TenantName"
    $Global:TenantName = $null
    $Global:TenantDomain = $null
    $Global:TenantUPN = $null
}

# Tab completion for Set-TenantContext
Register-ArgumentCompleter -CommandName Set-TenantContext -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    $TenantConfig |
        Where-Object { $_.Name -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', "Tenant: $($_.Domain)")
        }
}

# =========================
# 7. QoL Scripts
# =========================
Write-Host "🔥 PS7 profile loaded for $env:USERNAME@$env:COMPUTERNAME" -ForegroundColor Green
Write-Host "Host: $env:COMPUTERNAME | Time: $(Get-Date -Format u)" -ForegroundColor Cyan

# =========================
# 8. Profile Chaining
# =========================
$aliasFile   = "$HOME\Documents\PowerShell\Profile.Aliases.ps1"
$tenantFuncs = "$HOME\Documents\PowerShell\Profile.Functions.Tenant.ps1"
$devFuncs    = "$HOME\Documents\PowerShell\Profile.Functions.Dev.ps1"
foreach ($file in @($tenantFuncs,$devFuncs,$aliasFile)) {
    if (Test-Path $file) { . $file }
}
