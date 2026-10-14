#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Prüft, ob die Windows-Wiederherstellungsumgebung (WinRE) aktiviert ist, und meldet den Speicherort.
    EN: Checks whether the Windows Recovery Environment (WinRE) is enabled and reports its location.
.DESCRIPTION
    DE: Ruft "reagentc /info" auf und wertet die Ausgabe möglichst sprachunabhängig aus:
        Ein Pfad \\?\GLOBALROOT\device\harddiskN\partitionM\... (WinRE-Speicherort) oder eine von
        00000000-0000-0000-0000-000000000000 verschiedene BCD-GUID bedeuten Enabled; nur die Null-GUID
        ohne Pfad bedeutet Disabled. Erst wenn beides fehlt, werden die Statuswörter Enabled/Disabled
        bzw. Aktiviert/Deaktiviert (EN/DE) herangezogen; andere Sprachen ohne GUID/Pfad führen zu
        Exit 1. Ein Registry-Merkmal wird bewusst nicht genutzt, da nicht verlässlich dokumentiert.
        WinRE wird für BitLocker-Recovery und Systemzurücksetzung benötigt. Keine Änderungen.
    EN: Runs "reagentc /info" and parses the output as locale-independently as possible:
        A path \\?\GLOBALROOT\device\harddiskN\partitionM\... (WinRE location) or a BCD GUID other
        than 00000000-0000-0000-0000-000000000000 means Enabled; only the zero GUID without a path
        means Disabled. Only if both are missing, the status words Enabled/Disabled or
        Aktiviert/Deaktiviert (EN/DE) are used; other languages without GUID/path lead to exit 1.
        A registry indicator is intentionally not used because it is not reliably documented.
        WinRE is needed for BitLocker recovery and system reset. No changes.
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField: interner Name eines MultiLine-Feldes (max. 4000 Zeichen); Standard leer.
    EN: NinjaOne Text resultCustomField: internal name of a MultiLine field (max. 4000 characters); default empty.
.EXAMPLE
    .\checkWinREStatus.ps1
    DE: Meldet Status, Datenträger und Partition von WinRE.
    EN: Reports WinRE status, disk and partition.
.EXAMPLE
    .\checkWinREStatus.ps1 -CustomField winreStatus
    DE: Wie oben; JSON zusätzlich ins Feld winreStatus.
    EN: As above; JSON additionally to field winreStatus.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit (reagentc benötigt Administratorrechte). Nur lesend.
        Exit 0 = WinRE aktiviert, 1 = Eingabe-/Abfrage-/Schreibfehler oder nicht auswertbare Ausgabe,
        2 = WinRE deaktiviert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit (reagentc needs administrator rights). Read-only.
        Exit 0 = WinRE enabled, 1 = input/query/write error or unparseable output,
        2 = WinRE disabled.
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
    $global:LASTEXITCODE = 0
    $previous = $ErrorActionPreference
    # DE: stderr unter PS 5.1 nicht als Abbruch werten. EN: Do not turn stderr into a terminating error under PS 5.1.
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(reagentc /info 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "reagentc /info Exit $code" }
    $text = $lines -join "`n"
    $location = ''
    $disk = $null; $partition = $null
    $pathMatch = [regex]::Match($text, '\\\\\?\\GLOBALROOT\\device\\harddisk(\d+)\\partition(\d+)\\[^\r\n]*', 'IgnoreCase')
    if ($pathMatch.Success) {
        $location = $pathMatch.Value.Trim()
        $disk = [int]$pathMatch.Groups[1].Value; $partition = [int]$pathMatch.Groups[2].Value
    }
    $guids = @([regex]::Matches($text, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') | ForEach-Object { $_.Value })
    $bcd = @($guids | Where-Object { $_ -ne '00000000-0000-0000-0000-000000000000' }) | Select-Object -First 1
    $method = 'PathOrGuid'
    if ($location -or $bcd) { $status = 'Enabled' }
    elseif ($guids.Count -gt 0) { $status = 'Disabled' }
    else {
        $method = 'StatusText'
        if ($text -match '(?im)^\s*Windows RE[^:\r\n]*:\s*(Disabled|Deaktiviert)\s*$') { $status = 'Disabled' }
        elseif ($text -match '(?im)^\s*Windows RE[^:\r\n]*:\s*(Enabled|Aktiviert)\s*$') { $status = 'Enabled' }
        else { throw 'reagentc-Ausgabe nicht auswertbar / reagentc output not parseable.' }
    }
    $report = ConvertTo-Json -InputObject ([ordered]@{
        WinREStatus = $status; Location = $location; DiskNumber = $disk; PartitionNumber = $partition
        BcdIdentifier = $bcd; DetectionMethod = $method
    }) -Depth 3 -Compress
    Write-Output $report
    if ($CustomField) {
        if ($report.Length -gt 4000) { throw 'Bericht zu lang / Report exceeds 4000 characters.' }
        if (-not (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue)) { throw 'Ninja-Property-Set fehlt / unavailable.' }
        $global:LASTEXITCODE = 0
        Ninja-Property-Set -Name $CustomField -Value $report | Out-Null
        if ($global:LASTEXITCODE -ne 0) { throw 'Custom-Field-Schreibfehler / Custom field write failed.' }
    }
    if ($status -eq 'Disabled') { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
