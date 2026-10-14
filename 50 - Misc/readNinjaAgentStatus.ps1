#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Meldet Status, Version, Installationspfad und Laufzeit der NinjaOne-Agent-Dienste.
    EN: Reports state, version, install path and uptime of the NinjaOne agent services.
.DESCRIPTION
    DE: Liest per CIM Win32_Service alle Dienste mit Name NinjaRMMAgent* (Status,
        Starttyp, Pfad der Dienstdatei ohne Argumente), die Dateiversion der Dienstdatei,
        das Installationsverzeichnis und die Prozesslaufzeit (Win32_Process
        CreationDate). Es werden keine Konfigurationsdateien, Token, Schlüssel oder
        Kommandozeilenargumente gelesen oder ausgegeben. JSON, max. 4000 Zeichen.
        Nur lesend, keine Dienstaktion.
    EN: Reads via CIM Win32_Service all services named NinjaRMMAgent* (state, start
        mode, service binary path without arguments), the file version of the binary,
        the install directory and the process uptime (Win32_Process CreationDate).
        No configuration files, tokens, keys or command line arguments are read or
        output. JSON, max. 4000 characters. Read-only, no service actions.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: optionales MultiLine-Gerätefeld.
    EN: NinjaOne Text resultCustomField: optional MultiLine device field.
.EXAMPLE
    .\readNinjaAgentStatus.ps1
    DE: Meldet die NinjaOne-Agent-Dienste; Exit 2, wenn der Agent nicht läuft.
    EN: Reports the NinjaOne agent services; exit 2 if the agent is not running.
.EXAMPLE
    .\readNinjaAgentStatus.ps1 -CustomField ninjaAgentStatus
    DE: Zusätzlich JSON in das MultiLine-Feld ninjaAgentStatus schreiben.
    EN: Additionally write JSON to the MultiLine field ninjaAgentStatus.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben Variablen.
        Exit 0 = Agent läuft, 1 = Eingabe-/Abfrage-/Schreibfehler, 2 = kein
        NinjaRMMAgent*-Dienst, Dienst NinjaRMMAgent nicht Running oder ein weiterer
        Dienst mit Starttyp Auto nicht Running.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override variables.
        Exit 0 = agent running, 1 = input/query/write error, 2 = no NinjaRMMAgent*
        service, service NinjaRMMAgent not running or another service with start
        mode Auto not running.
#>
[CmdletBinding()]
param(
    [string]$CustomField = $env:resultCustomField
)

$ErrorActionPreference = 'Stop'
try {
    $CustomField = ([string]$CustomField).Trim()
    if ($CustomField -ieq 'null') { $CustomField = '' }
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiger Feldname / Invalid custom field name.' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / is unavailable.' }
    $services = @(Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE 'NinjaRMMAgent%'" -ErrorAction Stop | Sort-Object Name | Select-Object -First 10)
    $now = Get-Date
    $records = @(foreach ($service in $services) {
        # DE: Nur der Programmpfad, niemals Argumente. EN: Program path only, never arguments.
        $pathName = [string]$service.PathName
        $exe = ''
        if ($pathName -match '^\s*"([^"]+)"') { $exe = $Matches[1] }
        elseif ($pathName -match '^\s*(.+?\.exe)(?:\s|$)') { $exe = $Matches[1] }
        $version = ''
        $fileFound = $false
        if ($exe) {
            $file = Get-Item -LiteralPath $exe -ErrorAction SilentlyContinue
            if ($null -ne $file) {
                $fileFound = $true
                $version = [string]$file.VersionInfo.FileVersion
            }
        }
        $installPath = ''
        if ($exe -match '^(.+)\\[^\\]+$') { $installPath = $Matches[1] }
        $uptimeHours = $null
        $processId = [int]$service.ProcessId
        if ($processId -gt 0) {
            $process = @(Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId = {0}" -f $processId) -ErrorAction SilentlyContinue) | Select-Object -First 1
            if ($null -ne $process -and $null -ne $process.CreationDate) { $uptimeHours = [Math]::Round(($now - $process.CreationDate).TotalHours, 1) }
        }
        [pscustomobject]@{
            Name = [string]$service.Name; DisplayName = [string]$service.DisplayName; State = [string]$service.State
            StartMode = [string]$service.StartMode; ExecutablePath = $exe; InstallPath = $installPath
            FileFound = $fileFound; FileVersion = $version; ProcessId = $processId; UptimeHours = $uptimeHours
        }
    })
    $main = @($records | Where-Object { $_.Name -eq 'NinjaRMMAgent' })
    $problems = New-Object System.Collections.Generic.List[string]
    if ($records.Count -eq 0) { $problems.Add('NoNinjaRMMAgentService') }
    elseif ($main.Count -eq 0) { $problems.Add('NinjaRMMAgentMissing') }
    elseif ($main[0].State -ne 'Running') { $problems.Add('NinjaRMMAgentNotRunning') }
    foreach ($entry in @($records | Where-Object { $_.Name -ne 'NinjaRMMAgent' -and $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' })) {
        $problems.Add(('{0}NotRunning' -f $entry.Name))
    }
    $agentVersion = ''
    if ($main.Count -gt 0) { $agentVersion = $main[0].FileVersion }
    $report = [ordered]@{
        AgentRunning = ($main.Count -gt 0 -and $main[0].State -eq 'Running'); AgentVersion = $agentVersion
        ServiceCount = $records.Count; Problems = $problems.ToArray(); Services = $records
    } | ConvertTo-Json -Depth 4 -Compress
    if ($report.Length -gt 4000) { throw 'Bericht zu groß / Report too large.' }
    Write-Output $report
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Attribut schreiben fehlgeschlagen / Custom field write failed.' }
    }
    if ($problems.Count -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
