#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Deinstalliert ein Programm (HKLM-Uninstall-Eintrag) anhand des Anzeigenamens still; ohne Opt-in nur Inventur.
    EN: Silently uninstalls a program (HKLM uninstall entry) by display name; audit only without opt-in.
.DESCRIPTION
    DE: Liest die 64- und 32-Bit-Uninstall-Schlüssel unter HKLM. Ignoriert werden Einträge ohne DisplayName, mit
        SystemComponent=1 und mit ParentKeyName (Updates/Patches). MatchMode Exact = exakter Anzeigename
        (Groß-/Kleinschreibung egal), Contains = literaler Teilstring. Gleiche MSI-Produktcodes zählen einmal.
        Mehr Treffer als MaxMatches = Exit 1 ohne jede Deinstallation (Schutz vor zu breiten Namen).
        Methode je Eintrag:
        - MSI (WindowsInstaller=1 mit GUID-Schlüsselname, GUID-Schlüssel ohne bzw. mit MsiExec-UninstallString oder
          UninstallString "MsiExec.exe /I{GUID}" bzw. "/X{GUID}"): msiexec.exe /x {GUID} /qn /norestart /l*v "<Log>"
          (Log in $env:TEMP).
        - sonst QuietUninstallString; sonst UninstallString + ExeArguments (z. B. /S). Ohne stille Variante wird
          NICHTS gestartet (Ergebnis NoSilentMethod, kein interaktiver Deinstaller).
        Befehlszeilen werden sicher in Programm + Argumente zerlegt (Pfad in Anführungszeichen oder bis ".exe"),
        ohne cmd.exe /c oder Invoke-Expression; Start per Start-Process -PassThru mit Zeitlimit (WaitForExit).
        Exitcodes 0, 3010 (Neustart nötig), 1641 (Neustart eingeleitet) = Erfolg; 1605 = Produkt unbekannt
        (bereits entfernt). Nach der Deinstallation wird der Registry-Eintrag erneut geprüft. Bei Zeitüberschreitung
        wird der Prozess NICHT beendet; Ergebnis Timeout und Exit 1.
        Ohne Allow=true wird nur inventarisiert; jede Deinstallation läuft über ShouldProcess (-WhatIf).
        Bericht als JSON, optional in ein MultiLine-Feld (max. 4000 Zeichen, sonst Exit 1).
    EN: Reads the 64- and 32-bit HKLM uninstall keys. Entries without DisplayName, with SystemComponent=1 and with
        ParentKeyName (updates/patches) are ignored. MatchMode Exact = exact display name (case-insensitive),
        Contains = literal substring. Identical MSI product codes count once.
        More matches than MaxMatches = exit 1 without any uninstall (protects against overly broad names).
        Method per entry:
        - MSI (WindowsInstaller=1 with GUID key name, GUID key without or with an MsiExec UninstallString, or
          UninstallString "MsiExec.exe /I{GUID}" or "/X{GUID}"): msiexec.exe /x {GUID} /qn /norestart /l*v "<log>"
          (log in $env:TEMP).
        - otherwise QuietUninstallString; otherwise UninstallString + ExeArguments (e.g. /S). Without a silent
          variant NOTHING is started (result NoSilentMethod, no interactive uninstaller).
        Command lines are split safely into program + arguments (quoted path or path up to ".exe"), without
        cmd.exe /c or Invoke-Expression; started via Start-Process -PassThru with a timeout (WaitForExit).
        Exit codes 0, 3010 (reboot required), 1641 (reboot initiated) = success; 1605 = unknown product (already
        removed). After the uninstall the registry entry is checked again. On timeout the process is NOT killed;
        result Timeout and exit 1.
        Without Allow=true the script only audits; every uninstall goes through ShouldProcess (-WhatIf).
        JSON report, optionally written to a MultiLine field (max. 4000 characters, otherwise exit 1).
.PARAMETER Name
    DE: NinjaOne Text uninstallSoftwareName; erforderlich; 1-200 Zeichen; keine Steuerzeichen, * oder ?.
    EN: NinjaOne text uninstallSoftwareName; required; 1-200 characters; no control characters, * or ?.
.PARAMETER MatchMode
    DE: NinjaOne Dropdown/Text uninstallMatchMode; Exact oder Contains; Standard Exact.
    EN: NinjaOne drop-down/text uninstallMatchMode; Exact or Contains; default Exact.
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text uninstallAllow; true/false; Standard false. Nur true deinstalliert.
    EN: NinjaOne checkbox/text uninstallAllow; true/false; default false. Only true uninstalls.
.PARAMETER MaxMatches
    DE: NinjaOne Text uninstallMaxMatches; ganze Zahl 1-10; Standard 1. Mehr Treffer = Exit 1 ohne Deinstallation.
    EN: NinjaOne text uninstallMaxMatches; integer 1-10; default 1. More matches = exit 1 without uninstalling.
.PARAMETER ExeArguments
    DE: NinjaOne Text uninstallExeArguments; optionale stille Argumente für EXE-Deinstaller ohne
        QuietUninstallString (z. B. /S); max. 500 Zeichen, keine Steuerzeichen; Standard leer.
    EN: NinjaOne text uninstallExeArguments; optional silent arguments for EXE uninstallers without
        QuietUninstallString (e.g. /S); max. 500 characters, no control characters; default empty.
.PARAMETER TimeoutMinutes
    DE: NinjaOne Text uninstallTimeoutMinutes; ganze Zahl 1-240; Standard 30.
    EN: NinjaOne text uninstallTimeoutMinutes; integer 1-240; default 30.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\uninstallSoftware.ps1 -Name '7-Zip 23.01 (x64)'
    DE: Nur Inventur: zeigt Treffer und geplante Methode (Exit 2, falls installiert).
    EN: Audit only: shows matches and the planned method (exit 2 if installed).
.EXAMPLE
    .\uninstallSoftware.ps1 -Name 'Notepad++' -MatchMode Contains -Allow true -WhatIf
    DE: Simuliert die Deinstallation; nichts wird gestartet.
    EN: Simulates the uninstall; nothing is started.
.EXAMPLE
    .\uninstallSoftware.ps1 -Name 'Example Tool' -Allow true -ExeArguments '/S' -CustomField uninstallReport
    DE: Deinstalliert still (EXE mit /S, falls keine QuietUninstallString) und schreibt das JSON.
    EN: Uninstalls silently (EXE with /S if there is no QuietUninstallString) and writes the JSON.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen; leer/'null' = Standard.
        Exit 0 = nicht installiert, Deinstallation erfolgreich (auch 3010/1641/1605) oder -WhatIf.
        Exit 1 = Eingabe-, Registry- oder Schreibfehler, zu viele Treffer, Zeitüberschreitung oder alle
                 Deinstallationen fehlgeschlagen.
        Exit 2 = Inventur (Allow=false) hat Treffer gefunden; oder teilweise fehlgeschlagen; oder Erfolgscode, aber
                 der Registry-Eintrag existiert weiterhin.
        ConfirmImpact Medium: keine Rückfragen bei unbeaufsichtigten NinjaOne-Läufen; -WhatIf simuliert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override NinjaOne variables; empty/'null' = default.
        Exit 0 = not installed, uninstall successful (including 3010/1641/1605) or -WhatIf.
        Exit 1 = input, registry or write error, too many matches, timeout or all uninstalls failed.
        Exit 2 = audit (Allow=false) found matches; or partially failed; or success code but the registry entry
                 still exists.
        ConfirmImpact Medium: no prompts in unattended NinjaOne runs; -WhatIf simulates.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Name = $env:uninstallSoftwareName,
    [string]$MatchMode = $env:uninstallMatchMode,
    [string]$Allow = $env:uninstallAllow,
    [string]$MaxMatches = $env:uninstallMaxMatches,
    [string]$ExeArguments = $env:uninstallExeArguments,
    [string]$TimeoutMinutes = $env:uninstallTimeoutMinutes,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$guidPattern = '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'
function Resolve-Setting {
    param([string]$Value, [string]$Default)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null') { return $Default }
    return $Value.Trim()
}
function ConvertTo-Boolean {
    param([string]$Value, [string]$Name)
    $parsed = $false
    if (-not [bool]::TryParse($Value, [ref]$parsed)) { throw ('{0}: true/false erforderlich / true/false required.' -f $Name) }
    return $parsed
}
function ConvertTo-BoundedInt {
    param([string]$Value, [string]$Name, [int]$Minimum, [int]$Maximum)
    $parsed = 0
    if ($Value -notmatch '^\d{1,9}$' -or -not [int]::TryParse($Value, [ref]$parsed) -or $parsed -lt $Minimum -or $parsed -gt $Maximum) {
        throw ('{0}: ganze Zahl {1}-{2} erforderlich / integer {1}-{2} required.' -f $Name, $Minimum, $Maximum)
    }
    return $parsed
}
function Get-UninstallEntry {
    $roots = [ordered]@{
        Registry64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        Registry32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    }
    foreach ($view in $roots.Keys) {
        if (-not (Test-Path -LiteralPath $roots[$view])) { continue }
        $enumErrors = $null
        $keys = @(Get-ChildItem -LiteralPath $roots[$view] -ErrorAction SilentlyContinue -ErrorVariable enumErrors)
        foreach ($enumError in @($enumErrors)) {
            if ($enumError.Exception -isnot [System.Management.Automation.ItemNotFoundException]) { throw $enumError.Exception }
        }
        foreach ($key in $keys) {
            $keyPath = '{0}\{1}' -f $roots[$view], $key.PSChildName
            # DE: Während Installationen entfernte Schlüssel überspringen. EN: Skip keys removed during installs.
            try { $props = Get-ItemProperty -LiteralPath $keyPath -ErrorAction Stop }
            catch [System.Management.Automation.ItemNotFoundException] { continue }
            $display = [string]$props.DisplayName
            if ([string]::IsNullOrWhiteSpace($display)) { continue }
            if ([string]$props.SystemComponent -eq '1' -or -not [string]::IsNullOrWhiteSpace([string]$props.ParentKeyName)) { continue }
            [pscustomobject]@{
                Name = $display.Trim(); Version = [string]$props.DisplayVersion; Publisher = [string]$props.Publisher
                RegistryView = $view; KeyName = [string]$key.PSChildName; KeyPath = $keyPath
                WindowsInstaller = [string]$props.WindowsInstaller -eq '1'
                UninstallString = [string]$props.UninstallString; QuietUninstallString = [string]$props.QuietUninstallString
            }
        }
    }
}
function Split-CommandLine {
    param([string]$CommandLine)
    $text = $CommandLine.Trim()
    if (-not $text) { return $null }
    if ($text.StartsWith('"')) {
        $end = $text.IndexOf('"', 1)
        if ($end -lt 2) { return $null }
        $file = $text.Substring(1, $end - 1)
        $arguments = $text.Substring($end + 1).Trim()
    }
    else {
        $match = [regex]::Match($text, '^(.+?\.exe)(?=\s|$)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) { return $null }
        $file = $match.Groups[1].Value
        $arguments = $text.Substring($match.Length).Trim()
    }
    [pscustomobject]@{ FilePath = [Environment]::ExpandEnvironmentVariables($file.Trim()); Arguments = $arguments }
}
function Get-MsiProductCode {
    param($Command)
    if ($null -eq $Command) { return $null }
    if ((Split-Path -Path $Command.FilePath -Leaf) -notmatch '^msiexec(\.exe)?$') { return $null }
    $match = [regex]::Match($Command.Arguments, ('(?i)^/[IX]\s*({0})' -f $guidPattern))
    if ($match.Success) { return $match.Groups[1].Value.ToUpperInvariant() }
    return ''
}
function Get-UninstallPlan {
    param($Entry, [string]$ExtraArguments, [string]$LogDirectory)
    $plan = [pscustomobject]@{ Method = 'None'; FilePath = $null; Arguments = $null; ProductCode = $null; Problem = $null }
    $uninstall = Split-CommandLine -CommandLine $Entry.UninstallString
    $uninstallMsi = Get-MsiProductCode -Command $uninstall
    $keyIsGuid = $Entry.KeyName -match ('^{0}$' -f $guidPattern)
    $productCode = $null
    if ($keyIsGuid -and ($Entry.WindowsInstaller -or -not $Entry.UninstallString -or $null -ne $uninstallMsi)) { $productCode = $Entry.KeyName.ToUpperInvariant() }
    elseif ($uninstallMsi) { $productCode = $uninstallMsi }
    $method = 'Msi'
    if (-not $productCode -and $Entry.QuietUninstallString) {
        $command = Split-CommandLine -CommandLine $Entry.QuietUninstallString
        $quietMsi = Get-MsiProductCode -Command $command
        if ($quietMsi) { $productCode = $quietMsi }
        elseif ($null -ne $command -and $null -eq $quietMsi) { $method = 'QuietUninstallString' }
        else { $plan.Problem = 'QuietUninstallString nicht auswertbar / not parsable'; return $plan }
    }
    elseif (-not $productCode -and $Entry.UninstallString -and $ExtraArguments) {
        if ($null -eq $uninstall -or $null -ne $uninstallMsi) { $plan.Problem = 'UninstallString nicht auswertbar / not parsable'; return $plan }
        $command = [pscustomobject]@{ FilePath = $uninstall.FilePath; Arguments = (($uninstall.Arguments + ' ' + $ExtraArguments).Trim()) }
        $method = 'UninstallStringWithArguments'
    }
    elseif (-not $productCode) { $plan.Problem = 'Keine stille Deinstallation / No silent uninstall available'; return $plan }
    if ($productCode) {
        $log = Join-Path $LogDirectory ('uninstall_{0}_{1:yyyyMMddHHmmss}.log' -f $productCode.Trim('{', '}'), [DateTime]::Now)
        $plan.Method = 'Msi'
        $plan.FilePath = 'msiexec.exe'
        $plan.Arguments = '/x {0} /qn /norestart /l*v "{1}"' -f $productCode, $log
        $plan.ProductCode = $productCode
        return $plan
    }
    if (-not [IO.Path]::IsPathRooted($command.FilePath) -or $command.FilePath.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) {
        $plan.Problem = 'Deinstallerpfad ungültig / Invalid uninstaller path'
        return $plan
    }
    $plan.Method = $method
    $plan.FilePath = $command.FilePath
    $plan.Arguments = $command.Arguments
    return $plan
}
function Invoke-Uninstaller {
    param($Plan, [int]$TimeoutMilliseconds)
    $startArguments = @{ FilePath = $Plan.FilePath; PassThru = $true; ErrorAction = 'Stop' }
    if ($Plan.Arguments) { $startArguments.ArgumentList = $Plan.Arguments }
    $process = Start-Process @startArguments
    # DE: Handle cachen, damit ExitCode unter PS 5.1 verfügbar bleibt. EN: Cache handle so ExitCode stays available on PS 5.1.
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutMilliseconds)) { return [pscustomobject]@{ TimedOut = $true; ExitCode = $null } }
    return [pscustomobject]@{ TimedOut = $false; ExitCode = [int]$process.ExitCode }
}
function Export-Report {
    param([System.Collections.IDictionary]$Data, [string]$Field)
    $json = ConvertTo-Json -Depth 5 -InputObject $Data
    if ($json.Length -gt 4000) { $json = ConvertTo-Json -Depth 5 -Compress -InputObject $Data }
    Write-Output $json
    if ($Field) {
        if ($json.Length -gt 4000) { throw 'Bericht überschreitet 4000 Zeichen / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $Field -Value $json | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
}
try {
    $Name = Resolve-Setting $Name ''
    if (-not $Name -or $Name.Length -gt 200 -or $Name -match '[\x00-\x1f\x7f*?]') { throw 'uninstallSoftwareName: 1-200 Zeichen, keine Steuerzeichen/Wildcards / 1-200 characters, no control characters/wildcards.' }
    $MatchMode = Resolve-Setting $MatchMode 'Exact'
    if ($MatchMode -notin @('Exact', 'Contains')) { throw 'uninstallMatchMode: Exact oder/or Contains.' }
    $MatchMode = if ($MatchMode -eq 'Exact') { 'Exact' } else { 'Contains' }
    $allowed = ConvertTo-Boolean -Value (Resolve-Setting $Allow 'false') -Name 'uninstallAllow'
    $maximum = ConvertTo-BoundedInt -Value (Resolve-Setting $MaxMatches '1') -Name 'uninstallMaxMatches' -Minimum 1 -Maximum 10
    $extra = Resolve-Setting $ExeArguments ''
    if ($extra.Length -gt 500 -or $extra -match '[\x00-\x1f\x7f]') { throw 'uninstallExeArguments: max. 500 Zeichen, keine Steuerzeichen / max. 500 characters, no control characters.' }
    $timeout = ConvertTo-BoundedInt -Value (Resolve-Setting $TimeoutMinutes '30') -Name 'uninstallTimeoutMinutes' -Minimum 1 -Maximum 240
    $CustomField = Resolve-Setting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $logDirectory = if ($env:TEMP -and [IO.Path]::IsPathRooted($env:TEMP)) { $env:TEMP } else { [IO.Path]::GetTempPath() }
    $entries = @(Get-UninstallEntry)
    $found = @($entries | Where-Object {
        if ($MatchMode -eq 'Exact') { $_.Name -eq $Name } else { $_.Name.IndexOf($Name, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
    } | Sort-Object Name, RegistryView)
    # DE: Gleiche MSI-Produktcodes nur einmal. EN: Count identical MSI product codes once.
    $seen = @{}
    $matched = @(foreach ($entry in $found) {
        if ($entry.KeyName -match ('^{0}$' -f $guidPattern)) {
            $code = $entry.KeyName.ToUpperInvariant()
            if ($seen.ContainsKey($code)) { continue }
            $seen[$code] = $true
        }
        $entry
    })
    if ($matched.Count -gt $maximum) {
        throw ('{0} Treffer > uninstallMaxMatches {1}; nichts deinstalliert / {0} matches > uninstallMaxMatches {1}; nothing uninstalled: {2}' -f $matched.Count, $maximum, ((@($matched | Select-Object -First 5 | ForEach-Object { $_.Name })) -join '; '))
    }
    $results = @()
    foreach ($entry in $matched) {
        $plan = Get-UninstallPlan -Entry $entry -ExtraArguments $extra -LogDirectory $logDirectory
        $result = [ordered]@{
            Name = $entry.Name; Version = $entry.Version; Publisher = $entry.Publisher; RegistryView = $entry.RegistryView
            Method = $plan.Method; Executable = $(if ($plan.FilePath) { Split-Path -Path $plan.FilePath -Leaf } else { $null })
            Result = 'Planned'; ExitCode = $null; RebootRequired = $false; EntryRemoved = $null; Problem = $plan.Problem
        }
        $results += $result
        if (-not $allowed) { continue }
        if (-not $PSCmdlet.ShouldProcess(('{0} {1} ({2})' -f $entry.Name, $entry.Version, $entry.RegistryView), ('Still deinstallieren / Uninstall silently ({0})' -f $plan.Method))) { $result.Result = 'WhatIf'; continue }
        if ($plan.Method -eq 'None') { $result.Result = 'NoSilentMethod'; continue }
        if ($plan.Method -ne 'Msi' -and -not (Test-Path -LiteralPath $plan.FilePath -PathType Leaf)) { $result.Result = 'UninstallerNotFound'; continue }
        try { $run = Invoke-Uninstaller -Plan $plan -TimeoutMilliseconds ($timeout * 60000) }
        catch {
            $result.Result = 'StartFailed'
            $result.Problem = ([string]$_.Exception.Message).Substring(0, [Math]::Min(150, ([string]$_.Exception.Message).Length))
            continue
        }
        if ($run.TimedOut) { $result.Result = 'Timeout'; continue }
        $result.ExitCode = $run.ExitCode
        $result.RebootRequired = $run.ExitCode -in @(3010, 1641)
        if ($run.ExitCode -notin @(0, 3010, 1641, 1605)) { $result.Result = 'Failed'; continue }
        $result.EntryRemoved = -not (Test-Path -LiteralPath $entry.KeyPath)
        if ($run.ExitCode -eq 1605) { $result.Result = 'NotInstalled' } else { $result.Result = 'Succeeded' }
        if (-not $result.EntryRemoved) { $result.Result = 'SucceededEntryRemains' }
    }
    $results = @($results | ForEach-Object { [pscustomobject]$_ })
    Export-Report -Field $CustomField -Data ([ordered]@{
        Computer = $env:COMPUTERNAME; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference; Name = $Name; MatchMode = $MatchMode
        MaxMatches = $maximum; ScannedEntries = $entries.Count; MatchCount = $matched.Count
        RebootRequired = @($results | Where-Object { $_.RebootRequired }).Count -gt 0; Matches = $results
    })
    if (-not $allowed) {
        if ($matched.Count -gt 0) { exit 2 }
        exit 0
    }
    if ($WhatIfPreference) { exit 0 }
    $succeeded = @($results | Where-Object { $_.Result -in @('Succeeded', 'NotInstalled') }).Count
    $remaining = @($results | Where-Object { $_.Result -eq 'SucceededEntryRemains' }).Count
    $failures = $results.Count - $succeeded - $remaining
    if (@($results | Where-Object { $_.Result -eq 'Timeout' }).Count -gt 0) { exit 1 }
    if ($failures -gt 0 -and ($succeeded + $remaining) -eq 0) { exit 1 }
    if ($failures -gt 0 -or $remaining -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
