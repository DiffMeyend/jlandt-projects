Got it. Here’s a quick audit + a clean, drop-in version with fixes.

### What I fixed (quick)

* **Tee-Object**: added `-FilePath` everywhere (PS 5.1 requires it).
* **WinEvent queries**: added `-MaxEvents`/tight filters to avoid huge pulls; consistent PID → hex conversion.
* **Workspace**: ensure `OutDir` exists *once* and reuse it across snippets.
* **Safety gates**: kept destructive actions commented; clarified where no `-WhatIf` exists (e.g., `auditpol`).
* **Reliability**: guarded WMI queries and broad file searches with `-ErrorAction SilentlyContinue` and modest defaults.

---

# Datto EDR / RocketCyber – Endpoint IR SOP (Three-Phase) — **Patched**

> **Purpose:** Fill-in SOP to triage, contain, remediate, and communicate endpoint incidents from **Datto EDR / RocketCyber**. Built for Backstage (SYSTEM) on **PowerShell 5.1**. Guardrails: **Check → Safe (dry-run) → Real (ACK)**.
> **SLA:** *QuickFix* classification & containment within **15–30 minutes**.

---

## 0) Ticket Header (fill-in)

* **Ticket ID:** `T______________`
* **Alert Source:** `Datto EDR | RocketCyber`
* **Alert Type/Detector:** `LOLBin: regsvr32 scrobj | Suspicious PowerShell | Persistence | Beacon | Other`
* **MITRE Mapping (if provided):** `Txxxx`
* **Endpoint Hostname:** `______________`
* **Primary User (if known):** `______________`
* **Local Timezone:** `America/Chicago`
* **Event Window (local):** `Start: ________  End: ________`
* **Primary PID (suspect):** `_______`  **Parent PID:** `_______`
* **Case Folder (default):** `C:\IR\<TicketID>`

> **ScreenConnect note:** Use **Backstage (SYSTEM)**. Built-in file transfer for artifacts. No MSI/module installs required.

---

# 1) QuickFix Response (15–30 min)

**Goal:** **CLASSIFY** (True / Benign / False), **CONTAIN**, then **ESCALATE or CLOSE**. Prefer **Datto EDR portal** actions.

### 1.1 Intake (Portal)

1. Open the alert → review **Process Graph / Timeline**. Capture: exe path, **command line**, **user**, **parent**, **hash**, **signer**, **destinations**, auto-actions.
2. Compare with business context (expected tools, scheduled tasks, admin ops).
3. If malicious indicators or unclear intent → **contain immediately** (1.3) and continue triage.

**Paste in ticket:**

* Detection: `_____________________`
* Process: `Name: _____  Path: _____  PID: ____  PPID: ____`
* Command line: `________________________________________________`
* User/session: `________________`
* Hash & signer: `________________`
* Remote IP/Domain/Port: `________________`

### 1.2 Classify

* **True Positive** – malicious behavior confirmed.
* **Benign Positive** – legit admin/business pattern.
* **False Positive** – mis-fire / non-event.

**Decision:** `True / Benign / False` • **Why (1–2 lines):** `____________________________`

### 1.3 Containment (portal first)

* **Isolate host**, **Kill/Suspend** process tree, **Quarantine/Delete on reboot**, **Block** hash/path, disable **autostarts**, tag/notes.

> If portal fails or lacks a control, use the **optional PowerShell** below **only with ACK**.

### 1.4 Optional PowerShell – rapid spot checks

> Keep outputs in `C:\IR\<TicketID>\<Host>`. Run as SYSTEM (Backstage).

**Create workspace & (optional) transcript**

```powershell
# Check
$Ticket   = '<TicketID>'
$Computer = $env:COMPUTERNAME
$OutDir   = "C:\IR\$Ticket\$Computer"
$null = New-Item -ItemType Directory -Path $OutDir -Force
"Workspace: $OutDir"
"Transcript would write to: $OutDir\transcript.txt"
# Real (ACK)
# Start-Transcript -Path "$OutDir\transcript.txt" -Append
```

**Process & parent (fill values)**

```powershell
# Check
$Pid  = <SuspectPID>
$PPid = <ParentPID>
Get-CimInstance Win32_Process -Filter "ProcessId = $Pid"  | Select ProcessId,ParentProcessId,Name,CommandLine
Get-CimInstance Win32_Process -Filter "ProcessId = $PPid" | Select ProcessId,ParentProcessId,Name,CommandLine
```

**Quick event sweep (Security 4688)**

```powershell
# Requires: Audit Process Creation enabled (4688); cmdline optional but helpful
$EventStart=[datetime]'<StartLocalISO>'
$EventEnd  =[datetime]'<EndLocalISO>'
$Pid=<SuspectPID>; $PidHex=('0x{0:x}' -f $Pid)

# Name/keyword skim (bounded)
Get-WinEvent -LogName Security -FilterXPath "*[System[(EventID=4688)]]" -MaxEvents 5000 |
 Where-Object { $_.TimeCreated -ge $EventStart -and $_.TimeCreated -le $EventEnd -and $_.Message -like '*<processOrKeyword>*' } |
 Select TimeCreated,Id,Message -First 20

# PID-precise (ACK line is non-destructive; safe to run)
Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4688] and EventData[Data[@Name='NewProcessId']='$PidHex']]" -MaxEvents 200 |
 Select TimeCreated,Id,Message
```

**Containment stubs (ACK only; portal first)**

```powershell
# Real (ACK) – destructive; uncomment only with approval
# Stop-Process -Id <PID> -Force
# Remove-Item '<MaliciousFilePath>' -Force
```

### 1.5 Decision & Next Step

* **True Positive** → go to **Section 2**.
* **Benign/False** → document & go to **Section 3** to close.

---

# 2) Escalation Response

**Goal:** **REMEDIATE** and **RESTORE**.

### 2.1 Deep Triage

* Expand graph: lateral procs, Tasks, WMI, autoruns, egress.
* Collect IOCs; snapshot to case folder.

**Optional PowerShell – persistence & artifacts**

```powershell
# Assume $OutDir exists from Section 1

# Recent scriptlets / LOLBin feeders (bounded)
$LookbackDays=5; $Patterns='*.sct','*.xml','*.js','*.vbs','*.hta'
Get-ChildItem -Path C:\ -Include $Patterns -Recurse -ErrorAction SilentlyContinue |
 Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-$LookbackDays) } |
 Select FullName,LastWriteTime |
 Export-Csv -Path "$OutDir\recent_scriptlets.csv" -NoTypeInformation -Encoding UTF8

# Scheduled tasks inventory + suspicious filter
$tasks = Get-ScheduledTask | ForEach-Object {
  $t=$_; $info=Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath
  foreach($a in $t.Actions){
    [pscustomobject]@{
      TaskName      = ($t.TaskPath+$t.TaskName)
      State         = $t.State
      UserId        = $t.Principal.UserId
      RunLevel      = $t.Principal.RunLevel
      NextRunTime   = $info.NextRunTime
      LastRunTime   = $info.LastRunTime
      LastTaskResult= $info.LastTaskResult
      Execute       = $a.Execute
      Arguments     = $a.Arguments
      WorkingDir    = $a.WorkingDirectory
      Triggers      = ($t.Triggers|ForEach-Object{$_.StartBoundary}) -join ';'
    }
  }
}
$tasks | Sort-Object TaskName | Export-Csv -Path "$OutDir\scheduled_tasks_inventory.csv" -NoTypeInformation -Encoding UTF8

$patterns='regsvr32','scrobj','\.sct','rundll32','mshta','wscript','cscript','powershell','cmd\.exe','http://','https://','-enc','-encodedcommand'
$regex=($patterns -join '|')
$tasks | Where-Object { $_.Execute -match $regex -or $_.Arguments -match $regex } |
 Tee-Object -FilePath "$OutDir\scheduled_tasks_suspicious.txt" | Out-Null

# Run keys & Startup
function Dump-RunKey{
  param([string]$Path)
  if(Test-Path $Path){
    Get-ItemProperty -Path $Path | Select-Object * -ExcludeProperty PS* |
      ForEach-Object{
        $_.PSObject.Properties |
          Where-Object{$_.MemberType -eq 'NoteProperty'} |
          ForEach-Object{ [pscustomobject]@{KeyPath=$Path;Name=$_.Name;Value=$_.Value} }
      }
  }
}
$runPaths=@(
 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
)
$runEntries = foreach($p in $runPaths){ Dump-RunKey -Path $p }
$runEntries | Export-Csv -Path "$OutDir\run_keys_inventory.csv" -NoTypeInformation -Encoding UTF8
$runEntries | Where-Object { $_.Value -match $regex } |
 Tee-Object -FilePath "$OutDir\run_keys_suspicious.txt" | Out-Null

$startupPaths = @(
 "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp",
 "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
)
$startupItems = foreach($sp in $startupPaths){
  if(Test-Path $sp){ Get-ChildItem -Path $sp -File -ErrorAction SilentlyContinue | Select FullName,LastWriteTime,Length }
}
$startupItems | Export-Csv -Path "$OutDir\startup_inventory.csv" -NoTypeInformation -Encoding UTF8
$startupItems | Where-Object { $_.FullName -match $regex } |
 Tee-Object -FilePath "$OutDir\startup_suspicious.txt" | Out-Null

# WMI event subscriptions (guarded)
$ns='root/Subscription'
$wmiFilters  = Get-CimInstance -Namespace $ns -ClassName __EventFilter -ErrorAction SilentlyContinue
$wmiCL       = Get-CimInstance -Namespace $ns -ClassName CommandLineEventConsumer -ErrorAction SilentlyContinue
$wmiAS       = Get-CimInstance -Namespace $ns -ClassName ActiveScriptEventConsumer -ErrorAction SilentlyContinue
$wmiBindings = Get-CimInstance -Namespace $ns -ClassName __FilterToConsumerBinding -ErrorAction SilentlyContinue
$wmiFilters  | Select Name,Query,CreatorSID,EventNamespace,Timeout | Export-Csv -Path "$OutDir\wmi_eventfilters.csv" -NoTypeInformation -Encoding UTF8
$wmiCL       | Select Name,CommandLineTemplate,WorkingDirectory       | Export-Csv -Path "$OutDir\wmi_cmdline_consumers.csv" -NoTypeInformation -Encoding UTF8
$wmiAS       | Select Name,ScriptingEngine,ScriptText                 | Export-Csv -Path "$OutDir\wmi_activescript_consumers.csv" -NoTypeInformation -Encoding UTF8
$wmiBindings | Select Filter,Consumer                                  | Export-Csv -Path "$OutDir\wmi_bindings.csv" -NoTypeInformation -Encoding UTF8
$wmiSuspicious=@()
if($wmiCL){ $wmiSuspicious += $wmiCL | Where-Object { $_.CommandLineTemplate -match $regex } }
if($wmiAS){ $wmiSuspicious += $wmiAS | Where-Object { ($_.ScriptingEngine -match 'JScript|VBScript') -or ($_.ScriptText -match $regex) } }
$wmiSuspicious | Format-List * | Out-File -FilePath "$OutDir\wmi_suspicious.txt" -Encoding UTF8

# Prefetch & DNS (best-effort)
Get-ChildItem "C:\Windows\Prefetch\*.pf" -ErrorAction SilentlyContinue |
 Select Name,Length,LastWriteTime |
 Tee-Object -FilePath "$OutDir\prefetch.txt" | Out-Null

Get-DnsClientCache -ErrorAction SilentlyContinue |
 Export-Csv -Path "$OutDir\dns_cache.csv" -NoTypeInformation -Encoding UTF8
```

### 2.2 Remediation (ACK gates)

* **Portal first**: remove/quarantine files, disable/delete persistence, block IOCs, rotate creds/tokens, keep isolated until clean.
* **PowerShell fallbacks (ACK)**:

```powershell
# Real (ACK) – destructive; uncomment with change control
# Unregister-ScheduledTask -TaskName '<TaskName>' -Confirm:$false
# Remove-Item '<MaliciousFilePath>' -Force
# Stop-Process -Id <PID> -Force
```

### 2.3 Restore Asset

* Un-isolate when: persistence removed; no suspicious events; AV/EDR clean; business owner OK.
* Validate login, LOB apps, VPN/printers, performance. Record **restore time** + residuals.

**Optional – make evidence more visible (use with care)**

```powershell
# Check current policy
auditpol /get /category:"Detailed Tracking"
$regPath='HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
"Would set $regPath ProcessCreationIncludeCmdLine_Enabled=1"
# Real (ACK) – no -WhatIf for auditpol; registry supports -WhatIf but is commented here
# New-Item -Path $regPath -Force            | Out-Null
# New-ItemProperty -Path $regPath -Name ProcessCreationIncludeCmdLine_Enabled -PropertyType DWord -Value 1 -Force | Out-Null
# auditpol /set /subcategory:"Process Creation" /success:enable /failure:disable
```

---

# 3) Audit & Inform

### 3.1 Package Evidence & Closeout

```powershell
(Get-History | ForEach-Object CommandLine) | Out-File -FilePath "$OutDir\history.txt" -Encoding UTF8
"Would compress $OutDir to $OutDir.zip"
# Real (ACK)
# Compress-Archive -Path $OutDir -DestinationPath "$OutDir.zip" -Force
```

### 3.2 Documentation

* Update SOP/playbooks; tune rules & allow/deny lists; update regex (below).
* Add IOCs to TI store, blocklists, EDR policies.

### 3.3 Inform

* **Internal**: summary, timeline, root cause, IOCs, actions, impact, prevention.
* **External**: plain-language summary, what happened, what we did, user actions, restoration status.

**Fill-in block**

* Executive summary (≤150 words): `______________________________________________`
* Timeline (UTC/local): `______________________________________________`
* Indicators & scope: `______________________________________________`
* Actions taken: `______________________________________________`
* Residual risk & follow-ups: `______________________________________________`

---

## Mini-Playbook: regsvr32 / scrobj

**Portal**: Check `regsvr32.exe` command line (`/i:`; `http(s)://`, `.sct`, `.xml`). Inspect parent/user. If unclear → **isolate** and hunt files.

**Optional PowerShell**

```powershell
$Pid=<SuspectPID>; $PPid=<ParentPID>
Get-CimInstance Win32_Process -Filter "ProcessId = $Pid"  | Select ProcessId,ParentProcessId,Name,CommandLine
Get-CimInstance Win32_Process -Filter "ProcessId = $PPid" | Select ProcessId,ParentProcessId,Name,CommandLine

$PidHex=('0x{0:x}' -f $Pid); $PPidHex=('0x{0:x}' -f $PPid)
Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4688] and EventData[Data[@Name='NewProcessId']='$PidHex']]"  -MaxEvents 200 |
 Select TimeCreated,Id,Message
Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4688] and EventData[Data[@Name='NewProcessId']='$PPidHex']]" -MaxEvents 200 |
 Select TimeCreated,Id,Message

$EventStart=[datetime]'<StartLocalISO>'; $EventEnd=[datetime]'<EndLocalISO>'
Get-ChildItem -Path C:\ -Include *.sct,*.xml -Recurse -ErrorAction SilentlyContinue |
 Where-Object { $_.LastWriteTime -ge $EventStart.AddDays(-1) -and $_.LastWriteTime -le $EventEnd.AddDays(1) } |
 Select FullName,LastWriteTime |
 Export-Csv -Path "$OutDir\regsvr32_scriptlets.csv" -NoTypeInformation -Encoding UTF8

Get-ChildItem "C:\Windows\Prefetch\REGSVR32*.pf" -ErrorAction SilentlyContinue |
 Select Name,Length,LastWriteTime |
 Tee-Object -FilePath "$OutDir\prefetch_regsvr32.txt" | Out-Null
```

---

## Patterns & Tuning (regex)

```
regsvr32|scrobj|\.sct|rundll32|mshta|wscript|cscript|powershell|cmd\.exe|http://|https://|-enc|-encodedcommand
```

**Why this format?** Three-phase flow (**QuickFix → Escalation → Audit & Inform**) with guardrails so responders act quickly, safely, and consistently.
