#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Erfasst grundlegende Systeminformationen für NinjaOne.
    EN: Collects basic system information for NinjaOne.
.DESCRIPTION
    DE: Liest Betriebssystem, Modell, CPU und RAM, ohne Einstellungen zu ändern.
        Keine Seriennummern, Benutzerinformationen oder Zugangsdaten.
    EN: Reads operating system, model, CPU and RAM without changing settings.
        No serial numbers, user information or credentials.
.PARAMETER CustomField
    DE: Optionales Geräteattribut vom Typ MultiLine. Variable: systemInfoCustomField.
    EN: Optional device custom field of type MultiLine. Variable: systemInfoCustomField.
.EXAMPLE
    .\readSystemInfo.ps1
    DE: Gibt OS, Modell, CPU und RAM als JSON aus.
    EN: Outputs OS, model, CPU and RAM as JSON.
.EXAMPLE
    .\readSystemInfo.ps1 -CustomField systemInfo
    DE: Schreibt den JSON-Bericht zusätzlich in das MultiLine-Feld systemInfo.
    EN: Additionally writes the JSON report to the MultiLine field systemInfo.
.NOTES
    DE: Als SYSTEM ausführen. Explizite Parameter überschreiben Skriptvariablen.
        Exit 0 = erfolgreich, 1 = Abfrage- oder Schreibfehler.
    EN: Run as SYSTEM. Explicit parameters override script variables.
        Exit 0 = success, 1 = query or write failure.
#>
[CmdletBinding()]
param(
    [string]$CustomField = $env:systemInfoCustomField
)

$ErrorActionPreference = 'Stop'
try {
    # DE: Leere Variablen und NinjaOnes "null" deaktivieren den Feldexport.
    # EN: Empty variables and NinjaOne's "null" disable custom field export.
    $CustomField = $CustomField.Trim()
    if ($CustomField -eq 'null') { $CustomField = '' }
    if ($CustomField -and -not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) {
        throw 'Ninja-Property-Set fehlt / is unavailable.'
    }

    # DE: CIM statt Win32_Product verwenden; keine MSI-Reparaturen auslösen.
    # EN: Use CIM, not Win32_Product; do not trigger MSI repairs.
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $system = Get-CimInstance -ClassName Win32_ComputerSystem
    $processors = @(Get-CimInstance -ClassName Win32_Processor)
    if (-not $os -or -not $system -or $processors.Count -eq 0) {
        throw 'Unvollständige Systemdaten / Incomplete system information.'
    }
    $report = [ordered]@{
        ComputerName = $system.Name
        OperatingSystem = $os.Caption
        Version = $os.Version
        Build = $os.BuildNumber
        Architecture = $os.OSArchitecture
        Manufacturer = $system.Manufacturer
        Model = $system.Model
        Cpu = ($processors.Name -join '; ')
        LogicalProcessors = $system.NumberOfLogicalProcessors
        MemoryGiB = [Math]::Round($system.TotalPhysicalMemory / 1GB, 2)
    } | ConvertTo-Json
    Write-Output $report

    # DE: JSON als Klartext speichern, nicht als HTML; Feld benötigt Schreibrecht.
    # EN: Store JSON as plain text, not HTML; the field needs write permission.
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report too long (4000).' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom Field konnte nicht geschrieben werden / Custom field write failed.' }
    }
    exit 0
}
catch {
    Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message)
    exit 1
}