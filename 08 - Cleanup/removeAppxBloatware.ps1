#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Entfernt unerwünschte vorinstallierte AppX-Apps (Bloatware) für alle Benutzer und hebt die Bereitstellung auf.
    EN: Removes unwanted preinstalled AppX apps (bloatware) for all users and deprovisions them.
.DESCRIPTION
    DE: Für jeden Namen: Get-AppxPackage -AllUsers -Name <Name> -> Remove-AppxPackage -Package <PackageFullName>
        -AllUsers; optional (Deprovision) zusätzlich Get-AppxProvisionedPackage -Online (DisplayName gleich Name) ->
        Remove-AppxProvisionedPackage -Online -PackageName <PackageName>, damit neue Benutzer die App nicht erhalten.
        Frameworkpakete und als NonRemovable markierte Pakete werden nie entfernt.
        Standardliste (wenn Names leer): Microsoft.BingNews, Microsoft.BingWeather, Microsoft.BingSearch,
        Microsoft.GamingApp, Microsoft.GetHelp, Microsoft.Getstarted, Microsoft.MicrosoftOfficeHub,
        Microsoft.MicrosoftSolitaireCollection, Microsoft.People, Microsoft.PowerAutomateDesktop, Microsoft.SkypeApp,
        Microsoft.Todos, Microsoft.WindowsFeedbackHub, Microsoft.WindowsMaps, Microsoft.Xbox.TCUI, Microsoft.XboxApp,
        Microsoft.XboxGameOverlay, Microsoft.XboxGamingOverlay, Microsoft.XboxSpeechToTextOverlay, Microsoft.YourPhone,
        Microsoft.ZuneMusic, Microsoft.ZuneVideo, Microsoft.MixedReality.Portal, Microsoft.549981C3F5F10 (Cortana),
        Clipchamp.Clipchamp, MicrosoftTeams (Teams-Privat-Chat). Quick Assist ist bewusst nicht enthalten (IT-Support).
        Geschützte Pakete werden NIE entfernt; werden sie angefordert, endet das Skript mit Exit 1 ohne Änderung:
        Microsoft.WindowsStore, Microsoft.DesktopAppInstaller, Microsoft.StorePurchaseApp, Microsoft.SecHealthUI,
        Microsoft.Windows.ShellExperienceHost, Microsoft.Windows.StartMenuExperienceHost, Microsoft.AAD.BrokerPlugin,
        Microsoft.AccountsControl, Microsoft.UI.Xaml.*, Microsoft.VCLibs.*, Microsoft.NET.*,
        Microsoft.WindowsAppRuntime.*, Microsoft.Services.Store.Engagement, Microsoft.Windows.CloudExperienceHost,
        windows.immersivecontrolpanel.
        Ohne Allow=true wird nur inventarisiert; jede Entfernung läuft über ShouldProcess (-WhatIf).
        Bericht als JSON (nur gefundene Namen, max. 25), optional in ein MultiLine-Feld (max. 4000 Zeichen).
    EN: For every name: Get-AppxPackage -AllUsers -Name <name> -> Remove-AppxPackage -Package <PackageFullName>
        -AllUsers; optionally (Deprovision) also Get-AppxProvisionedPackage -Online (DisplayName equals name) ->
        Remove-AppxProvisionedPackage -Online -PackageName <PackageName>, so new users do not get the app.
        Framework packages and packages marked NonRemovable are never removed.
        Default list (if Names is empty): see the German list above (Bing, Xbox, Zune, Office hub, Solitaire,
        People, Skype, To Do, Feedback Hub, Maps, Phone Link, Mixed Reality Portal, Cortana, Clipchamp, Teams
        consumer chat, ...). Quick Assist is intentionally excluded (IT support).
        Protected packages are NEVER removed; if requested, the script ends with exit 1 without any change (list
        see above: Store, App Installer, Store purchase, Windows Security UI, shell/start menu hosts, AAD broker,
        accounts control, UI.Xaml/VCLibs/NET/WindowsAppRuntime frameworks, Store engagement, cloud experience host,
        immersive control panel).
        Without Allow=true the script only audits; every removal goes through ShouldProcess (-WhatIf).
        JSON report (only names found, max. 25), optionally written to a MultiLine field (max. 4000 characters).
.PARAMETER Allow
    DE: NinjaOne Checkbox/Text appxRemoveAllow; true/false; Standard false. Nur true entfernt Apps.
    EN: NinjaOne checkbox/text appxRemoveAllow; true/false; default false. Only true removes apps.
.PARAMETER Names
    DE: NinjaOne Text appxRemoveNames; optionale kommagetrennte Paketnamen (ersetzt die Standardliste); max. 60,
        je ^[A-Za-z0-9][A-Za-z0-9.\-_]{1,127}$ (keine Wildcards); Standard leer = Standardliste.
    EN: NinjaOne text appxRemoveNames; optional comma-separated package names (replaces the default list);
        max. 60, each ^[A-Za-z0-9][A-Za-z0-9.\-_]{1,127}$ (no wildcards); default empty = default list.
.PARAMETER Deprovision
    DE: NinjaOne Checkbox/Text appxRemoveDeprovision; true/false; Standard true (Bereitstellung aufheben).
    EN: NinjaOne checkbox/text appxRemoveDeprovision; true/false; default true (deprovision).
.PARAMETER CustomField
    DE: NinjaOne Text resultCustomField; optionaler interner Name eines MultiLine-Feldes; Standard leer.
    EN: NinjaOne text resultCustomField; optional internal name of a MultiLine field; default empty.
.EXAMPLE
    .\removeAppxBloatware.ps1
    DE: Nur Inventur der Standardliste (Exit 2, falls Apps installiert/bereitgestellt sind).
    EN: Audit only of the default list (exit 2 if apps are installed/provisioned).
.EXAMPLE
    .\removeAppxBloatware.ps1 -Allow true -WhatIf
    DE: Simuliert das Entfernen der Standardliste; nichts wird geändert.
    EN: Simulates removing the default list; nothing is changed.
.EXAMPLE
    .\removeAppxBloatware.ps1 -Allow true -Names 'Microsoft.BingNews,Microsoft.ZuneMusic' -CustomField appxReport
    DE: Entfernt und deprovisioniert nur die zwei Apps und schreibt das JSON in appxReport.
    EN: Removes and deprovisions only the two apps and writes the JSON to appxReport.
.NOTES
    DE: Windows PowerShell 5.1, SYSTEM, 64-Bit. Parameter überschreiben NinjaOne-Variablen; leer/'null' = Standard.
        Exit 0 = nichts gefunden, alles entfernt oder -WhatIf.
        Exit 1 = Eingabefehler (auch: geschützter Name angefordert), Abfrage- oder Schreibfehler.
        Exit 2 = Inventur (Allow=false) hat installierte/bereitgestellte Apps gefunden; oder mindestens eine
                 Entfernung ist fehlgeschlagen (Teilfehler).
        ConfirmImpact Medium: keine Rückfragen bei unbeaufsichtigten NinjaOne-Läufen; -WhatIf simuliert.
    EN: Windows PowerShell 5.1, SYSTEM, 64-bit. Parameters override NinjaOne variables; empty/'null' = default.
        Exit 0 = nothing found, everything removed or -WhatIf.
        Exit 1 = input error (also: protected name requested), query or write error.
        Exit 2 = audit (Allow=false) found installed/provisioned apps; or at least one removal failed (partial).
        ConfirmImpact Medium: no prompts in unattended NinjaOne runs; -WhatIf simulates.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Allow = $env:appxRemoveAllow,
    [string]$Names = $env:appxRemoveNames,
    [string]$Deprovision = $env:appxRemoveDeprovision,
    [string]$CustomField = $env:resultCustomField
)
$ErrorActionPreference = 'Stop'
$defaultNames = @(
    'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GamingApp', 'Microsoft.GetHelp',
    'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People',
    'Microsoft.PowerAutomateDesktop', 'Microsoft.SkypeApp', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub',
    'Microsoft.WindowsMaps', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay',
    'Microsoft.XboxGamingOverlay', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.YourPhone', 'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo', 'Microsoft.MixedReality.Portal', 'Microsoft.549981C3F5F10', 'Clipchamp.Clipchamp', 'MicrosoftTeams'
)
$protectedNames = @(
    'Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller', 'Microsoft.StorePurchaseApp', 'Microsoft.SecHealthUI',
    'Microsoft.Windows.ShellExperienceHost', 'Microsoft.Windows.StartMenuExperienceHost', 'Microsoft.AAD.BrokerPlugin',
    'Microsoft.AccountsControl', 'Microsoft.Services.Store.Engagement', 'Microsoft.Windows.CloudExperienceHost',
    'windows.immersivecontrolpanel'
)
$protectedPrefixes = @('Microsoft.UI.Xaml', 'Microsoft.VCLibs', 'Microsoft.NET', 'Microsoft.WindowsAppRuntime')
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
function Test-ProtectedName {
    param([string]$PackageName)
    if ($protectedNames -contains $PackageName) { return $true }
    foreach ($prefix in $protectedPrefixes) {
        if ($PackageName -eq $prefix -or $PackageName.StartsWith($prefix + '.', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
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
    $allowed = ConvertTo-Boolean -Value (Resolve-Setting $Allow 'false') -Name 'appxRemoveAllow'
    $deprovisionEnabled = ConvertTo-Boolean -Value (Resolve-Setting $Deprovision 'true') -Name 'appxRemoveDeprovision'
    $nameText = Resolve-Setting $Names ''
    $source = 'Default'
    $requested = $defaultNames
    if ($nameText) {
        if ($nameText.Length -gt 8000) { throw 'appxRemoveNames zu lang / too long.' }
        $requested = @($nameText.Split(',') | ForEach-Object { $_.Trim() })
        $source = 'Custom'
        if ($requested.Count -gt 60 -or @($requested | Where-Object { $_ -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.\-_]{1,127}$' }).Count -gt 0) {
            throw 'Ungültige appxRemoveNames-Liste (max. 60, keine Wildcards) / Invalid appxRemoveNames list (max. 60, no wildcards).'
        }
    }
    $requested = @($requested | Sort-Object -Unique)
    $refused = @($requested | Where-Object { Test-ProtectedName -PackageName $_ })
    if ($refused.Count -gt 0) { throw ('Geschützte Pakete abgelehnt / Protected packages refused: {0}' -f ($refused -join ', ')) }
    $CustomField = Resolve-Setting $CustomField ''
    if ($CustomField -and $CustomField -notmatch '^[A-Za-z][A-Za-z0-9_]{0,99}$') { throw 'Ungültiges resultCustomField / Invalid resultCustomField.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich / 64-bit PowerShell required.' }

    $provisioned = @()
    if ($deprovisionEnabled) { $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) }
    $items = @()
    foreach ($name in $requested) {
        $packages = @(Get-AppxPackage -AllUsers -Name $name -ErrorAction Stop | Where-Object { $_.Name -eq $name } | Sort-Object -Property PackageFullName -Unique)
        $provisionedMatches = @($provisioned | Where-Object { $_.DisplayName -eq $name } | Sort-Object -Property PackageName -Unique)
        if ($packages.Count -eq 0 -and $provisionedMatches.Count -eq 0) { continue }
        $item = [ordered]@{ Name = $name; Installed = $packages.Count; Provisioned = $provisionedMatches.Count; Removed = 0; Deprovisioned = 0; Skipped = 0; Failed = 0 }
        $items += $item
        if (-not $allowed) { continue }
        foreach ($package in $packages) {
            # DE: Framework- und nicht entfernbare Pakete nie anfassen. EN: Never touch framework or non-removable packages.
            if ($package.IsFramework -eq $true -or $package.NonRemovable -eq $true -or (Test-ProtectedName -PackageName ([string]$package.Name))) { $item.Skipped++; continue }
            if (-not $PSCmdlet.ShouldProcess([string]$package.PackageFullName, 'AppX-Paket für alle Benutzer entfernen / Remove AppX package for all users')) { continue }
            try { Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop; $item.Removed++ }
            catch { $item.Failed++ }
        }
        foreach ($package in $provisionedMatches) {
            if (-not $PSCmdlet.ShouldProcess([string]$package.PackageName, 'Bereitstellung aufheben / Deprovision package')) { continue }
            try { Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null; $item.Deprovisioned++ }
            catch { $item.Failed++ }
        }
    }
    $items = @($items | ForEach-Object { [pscustomobject]$_ })
    $totalFailed = [int]($items | Measure-Object -Property Failed -Sum).Sum
    $maxRecords = 25
    Export-Report -Field $CustomField -Data ([ordered]@{
        Computer = $env:COMPUTERNAME; Allowed = $allowed; WhatIf = [bool]$WhatIfPreference; Deprovision = $deprovisionEnabled
        NameSource = $source; RequestedCount = $requested.Count; FoundCount = $items.Count
        Installed = [int]($items | Measure-Object -Property Installed -Sum).Sum
        Provisioned = [int]($items | Measure-Object -Property Provisioned -Sum).Sum
        Removed = [int]($items | Measure-Object -Property Removed -Sum).Sum
        Deprovisioned = [int]($items | Measure-Object -Property Deprovisioned -Sum).Sum
        Failed = $totalFailed; ItemsOmitted = [Math]::Max(0, $items.Count - $maxRecords)
        Items = @($items | Select-Object -First $maxRecords)
    })
    if (-not $allowed) {
        if ($items.Count -gt 0) { exit 2 }
        exit 0
    }
    if ($WhatIfPreference) { exit 0 }
    if ($totalFailed -gt 0) { exit 2 }
    exit 0
}
catch { Write-Output ("Fehler / Error: {0}" -f $_.Exception.Message); exit 1 }
