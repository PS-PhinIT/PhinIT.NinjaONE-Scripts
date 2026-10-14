#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft typische Windows-Indikatoren für einen ausstehenden Neustart.
    EN: Checks common Windows indicators for a pending reboot.
.DESCRIPTION
    DE: Prüft CBS, Windows Update und ausstehende Dateiumbenennungen.
        Die Prüfung ist nicht vollständig; sie startet das Gerät niemals neu.
    EN: Checks CBS, Windows Update and pending file rename operations.
        The check is not exhaustive; it never reboots the device.
.PARAMETER CustomField
    DE: Optionales Geräteattribut vom Typ Checkbox. Variable: rebootPendingCustomField.
    EN: Optional device custom field of type Checkbox. Variable: rebootPendingCustomField.
.EXAMPLE
    .\restartPendingCheck.ps1
    DE: Exit 2, wenn ein Neustart-Indikator gefunden wird.
    EN: Exit 2 if a pending reboot indicator is found.
.EXAMPLE
    .\restartPendingCheck.ps1 -CustomField rebootPending
    DE: Ergebnis zusätzlich in das Checkbox-Feld rebootPending schreiben.
    EN: Additionally write the result to the Checkbox field rebootPending.
.NOTES
    DE: Als SYSTEM mit 64-Bit-PowerShell ausführen. Parameter haben Vorrang.
        Exit 0 = kein Indikator, 1 = Fehler, 2 = Neustart ausstehend.
    EN: Run as SYSTEM using 64-bit PowerShell. Parameters take precedence.
        Exit 0 = no indicator, 1 = error, 2 = reboot pending.
#>
[CmdletBinding()]
param(
    [string]$CustomField = $env:rebootPendingCustomField
)

$ErrorActionPreference = 'Stop'
$registry = $null
try {
    $CustomField = $CustomField.Trim()
    if ($CustomField -eq 'null') { $CustomField = '' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }

    # DE: Registry64 verhindert falsche Ergebnisse durch WOW64-Umleitung.
    # EN: Registry64 prevents false results caused by WOW64 redirection.
    $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    $reasons = @()
    $paths = [ordered]@{
        CBS = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        WindowsUpdate = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    }
    foreach ($name in $paths.Keys) {
        $key = $registry.OpenSubKey($paths[$name])
        if ($null -ne $key) {
            try { $reasons += $name }
            finally { $key.Dispose() }
        }
    }
    $session = $registry.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager')
    if ($null -eq $session) { throw 'Session Manager fehlt / is missing.' }
    try {
        $renames = $session.GetValue('PendingFileRenameOperations')
        if (@($renames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            $reasons += 'PendingFileRenameOperations'
        }
    }
    finally { $session.Dispose() }

    $pending = $reasons.Count -gt 0
    Write-Output ("Neustart ausstehend / Reboot pending: {0}; Indikatoren / Indicators: {1}" -f $pending, ($reasons -join ', '))
    # DE: Immer schreiben, auch false; dadurch werden alte Warnungen gelöscht.
    # EN: Always write, including false; this clears stale warnings.
    if ($CustomField) {
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $pending | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom Field konnte nicht geschrieben werden / Custom field write failed.' }
    }
    if ($pending) { exit 2 }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}
finally {
    if ($null -ne $registry) { $registry.Dispose() }
}