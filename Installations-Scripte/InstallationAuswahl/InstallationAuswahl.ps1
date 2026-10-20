#Requires -Version 5.1

<#
.SYNOPSIS
    DE: Zeigt Installationsskripte kategorisiert an und installiert eine Auswahl unabhängig von NinjaOne.
    EN: Displays installation scripts by category and installs a selection independently of NinjaOne.
.DESCRIPTION
    DE: Liest install*.ps1 aus dem übergeordneten Ordner, gruppiert sie nach Kategorien und erlaubt Mehrfachauswahl.
        Die ausgewählten Skripte werden nach ausdrücklicher Bestätigung einzeln mit installAllow=true gestartet.
        Dieses Werkzeug benötigt Windows PowerShell 5.1 in einer als Administrator gestarteten Sitzung.
    EN: Reads install*.ps1 from the parent folder, groups them by category and allows multi-selection.
        After explicit confirmation, each selected script is started with installAllow=true.
        This tool requires Windows PowerShell 5.1 in an elevated session.
.PARAMETER ListOnly
    DE: Gibt den erkannten Katalog als JSON aus, ohne die grafische Oberfläche zu öffnen.
    EN: Outputs the detected catalog as JSON without opening the graphical interface.
.EXAMPLE
    .\InstallationAuswahl.ps1
    DE: Öffnet die Auswahloberfläche.
    EN: Opens the selection interface.
.EXAMPLE
    .\InstallationAuswahl.ps1 -ListOnly
    DE: Gibt den Installationskatalog als JSON aus.
    EN: Outputs the installation catalog as JSON.
.NOTES
    DE: Die enthaltenen Installationsskripte installieren standardmäßig nur fehlende Programme; vorhandene Programme werden nicht aktualisiert.
        Protokolle liegen unter %TEMP%\PhinIT-Installation-Auswahl.
    EN: The included installation scripts install missing applications by default; existing applications are not upgraded.
        Logs are stored under %TEMP%\PhinIT-Installation-Auswahl.
#>
[CmdletBinding()]
param(
    [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'
$installFolder = Split-Path -Parent $PSScriptRoot

function Get-InstallationCategory {
    param([Parameter(Mandatory = $true)][string]$FileName)

    switch -Regex ($FileName) {
        '^install(1Password|Bitwarden|KeePass|Gpg4win|VeraCrypt|YubicoAuthenticator)' { return 'Sicherheit & Passwortmanager' }
        '^install(BraveBrowser|GoogleChrome|MicrosoftEdge|MicrosoftEdgeWebView2|MozillaFirefox)' { return 'Browser' }
        '^install(AdobeAcrobat|Foxit|LibreOffice|OnlyOffice|Microsoft365|PowerBI|PowerAutomate|Pdf)' { return 'Office & PDF' }
        '^install(CiscoJabber|CiscoWebex|GoToMeeting|Mattermost|Zoom|Jabra|EmClient|MozillaThunderbird)' { return 'Kommunikation & Zusammenarbeit' }
        '^install(Dropbox|GoogleDrive|MicrosoftOneDrive|BoxDrive|Nextcloud)' { return 'Cloud & Dateisynchronisierung' }
        '^install(AnyDesk|Citrix|Omnissa|OpenVpn|Tailscale|TeamViewer|Splashtop|Remote|RoyalTs|MobaXterm|RealVnc|WireGuard|SonicWall|PuTTY|WinSCP)' { return 'Fernzugriff & VPN' }
        '^install(DotNet|Temurin|Python|NodeJs|VcRedist|MsOdbc)' { return 'Laufzeiten & Frameworks' }
        '^install(Git|TortoiseGit|TortoiseSvn|DBeaver|VisualStudioCode|SqlServerManagement)' { return 'Entwicklung & Datenbanken' }
        '^install(AwsCli|Azure|AdvancedIpScanner|Wireshark|DellCommand|LenovoSystem|IntelDriver)' { return 'Administration & Netzwerk' }
        default { return 'Werkzeuge & Multimedia' }
    }
}

function Get-InstallationCatalog {
    $catalog = foreach ($file in Get-ChildItem -LiteralPath $installFolder -Filter 'install*.ps1' -File | Sort-Object Name) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        $nameMatch = [regex]::Match($content, '(?m)^\s*Name\s*=\s*''([^'']+)''')
        if (-not $nameMatch.Success) {
            Write-Warning ('Kein Tool-Name in {0} gefunden; Dateiname wird verwendet.' -f $file.Name)
        }
        [pscustomobject]@{
            Name     = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { $file.BaseName }
            Category = Get-InstallationCategory -FileName $file.Name
            Path     = $file.FullName
            FileName = $file.Name
        }
    }
    return @($catalog)
}

$catalog = @(Get-InstallationCatalog)
if ($ListOnly) {
    $catalog | ConvertTo-Json -Depth 3
    return
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Die grafische Auswahl benötigt Windows. Use -ListOnly to inspect the catalog on another platform.'
}
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Bitte Windows PowerShell 5.1 (powershell.exe) verwenden, nicht PowerShell 7.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Bitte Windows PowerShell mit "Als Administrator ausführen" starten.'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'PhinIT – Installationsauswahl'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1000, 700)
$form.MinimumSize = New-Object System.Drawing.Size(820, 560)

$description = New-Object System.Windows.Forms.Label
$description.Text = 'Programme nach Kategorie auswählen. Die Installation startet erst nach Bestätigung.'
$description.AutoSize = $false
$description.Location = New-Object System.Drawing.Point(14, 12)
$description.Size = New-Object System.Drawing.Size(950, 24)
$form.Controls.Add($description)

$tree = New-Object System.Windows.Forms.TreeView
$tree.CheckBoxes = $true
$tree.HideSelection = $false
$tree.Location = New-Object System.Drawing.Point(14, 42)
$tree.Size = New-Object System.Drawing.Size(430, 560)
$tree.Anchor = 'Top, Bottom, Left'
$form.Controls.Add($tree)

$results = New-Object System.Windows.Forms.TextBox
$results.Multiline = $true
$results.ReadOnly = $true
$results.ScrollBars = 'Vertical'
$results.WordWrap = $false
$results.Location = New-Object System.Drawing.Point(458, 42)
$results.Size = New-Object System.Drawing.Size(510, 560)
$results.Anchor = 'Top, Bottom, Left, Right'
$results.Text = 'Ergebnisse der Installationsauswahl erscheinen hier.'
$form.Controls.Add($results)

$selectionLabel = New-Object System.Windows.Forms.Label
$selectionLabel.AutoSize = $true
$selectionLabel.Location = New-Object System.Drawing.Point(14, 612)
$selectionLabel.Text = '0 Programme ausgewählt'
$selectionLabel.Anchor = 'Bottom, Left'
$form.Controls.Add($selectionLabel)

$selectAllButton = New-Object System.Windows.Forms.Button
$selectAllButton.Text = 'Alle auswählen'
$selectAllButton.Location = New-Object System.Drawing.Point(458, 612)
$selectAllButton.Size = New-Object System.Drawing.Size(120, 30)
$selectAllButton.Anchor = 'Bottom, Left'
$form.Controls.Add($selectAllButton)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = 'Auswahl löschen'
$clearButton.Location = New-Object System.Drawing.Point(586, 612)
$clearButton.Size = New-Object System.Drawing.Size(120, 30)
$clearButton.Anchor = 'Bottom, Left'
$form.Controls.Add($clearButton)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = 'Installation Auswahl durchführen'
$installButton.Location = New-Object System.Drawing.Point(714, 612)
$installButton.Size = New-Object System.Drawing.Size(210, 30)
$installButton.Anchor = 'Bottom, Right'
$form.Controls.Add($installButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'Schließen'
$closeButton.Location = New-Object System.Drawing.Point(930, 612)
$closeButton.Size = New-Object System.Drawing.Size(75, 30)
$closeButton.Anchor = 'Bottom, Right'
$form.Controls.Add($closeButton)

$script:updatingTree = $false
$script:installationRunning = $false
$categories = @($catalog | Select-Object -ExpandProperty Category -Unique | Sort-Object)
foreach ($categoryName in $categories) {
    $categoryNode = New-Object System.Windows.Forms.TreeNode($categoryName)
    foreach ($entry in @($catalog | Where-Object { $_.Category -eq $categoryName } | Sort-Object Name)) {
        $itemNode = New-Object System.Windows.Forms.TreeNode($entry.Name)
        $itemNode.Tag = $entry.Path
        $categoryNode.Nodes.Add($itemNode) | Out-Null
    }
    $categoryNode.Expand()
    $tree.Nodes.Add($categoryNode) | Out-Null
}

$tree.Add_AfterCheck({
    param($sender, $eventArgs)
    if ($script:updatingTree) { return }
    $script:updatingTree = $true
    try {
        if ($eventArgs.Node.Nodes.Count -gt 0) {
            foreach ($child in $eventArgs.Node.Nodes) { $child.Checked = $eventArgs.Node.Checked }
        }
        elseif ($eventArgs.Node.Parent) {
            $siblings = @($eventArgs.Node.Parent.Nodes)
            $eventArgs.Node.Parent.Checked = ($siblings.Count -gt 0 -and @($siblings | Where-Object { -not $_.Checked }).Count -eq 0)
        }
        $selectedCount = 0
        foreach ($group in $tree.Nodes) {
            foreach ($item in $group.Nodes) {
                if ($item.Checked) { $selectedCount++ }
            }
        }
        $selectionLabel.Text = '{0} Programme ausgewählt' -f $selectedCount
    }
    finally {
        $script:updatingTree = $false
    }
})

$selectAllButton.Add_Click({
    foreach ($group in $tree.Nodes) { $group.Checked = $true }
})
$clearButton.Add_Click({
    foreach ($group in $tree.Nodes) { $group.Checked = $false }
})
$closeButton.Add_Click({ $form.Close() })
$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:installationRunning) {
        $eventArgs.Cancel = $true
        [System.Windows.Forms.MessageBox]::Show(
            'Bitte warten, bis die laufende Installation abgeschlossen ist.',
            'Installation läuft',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
})

$installButton.Add_Click({
    $selected = @(
        foreach ($group in $tree.Nodes) {
            foreach ($item in $group.Nodes) {
                if ($item.Checked) {
                    [pscustomobject]@{ Name = $item.Text; Path = [string]$item.Tag }
                }
            }
        }
    )
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            'Bitte mindestens ein Programm auswählen.',
            'Keine Auswahl',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }
    $names = ($selected | ForEach-Object { '• ' + $_.Name }) -join [Environment]::NewLine
    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        "Folgende Programme werden nacheinander installiert:`r`n`r`n$names`r`n`r`nVorhandene Programme werden standardmäßig nicht aktualisiert. Fortfahren?",
        'Installation bestätigen',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $script:installationRunning = $true
    $installButton.Enabled = $false
    $selectAllButton.Enabled = $false
    $clearButton.Enabled = $false
    $tree.Enabled = $false
    $results.Clear()
    $logRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'PhinIT-Installation-Auswahl'
    $runLog = Join-Path $logRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -Path $runLog -ItemType Directory -Force | Out-Null
    $results.AppendText(('Protokollordner: {0}{1}{1}' -f $runLog, [Environment]::NewLine))

    try {
        foreach ($entry in $selected) {
            $results.AppendText(('Starte: {0}{1}' -f $entry.Name, [Environment]::NewLine))
            $safeName = [regex]::Replace($entry.Name, '[^\p{L}\p{Nd}._-]', '_')
            $stdout = Join-Path $runLog ($safeName + '.stdout.log')
            $stderr = Join-Path $runLog ($safeName + '.stderr.log')
            try {
                $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
                    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $entry.Path), '-AllowInstall', 'true') `
                    -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
                while (-not $process.HasExited) {
                    [System.Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 200
                }
                $process.WaitForExit()
                $status = if ($process.ExitCode -eq 0) { 'ERFOLG' } else { 'FEHLER' }
                $results.AppendText(('{0}: {1} (Exitcode {2}){3}' -f $status, $entry.Name, $process.ExitCode, [Environment]::NewLine))
            }
            catch {
                $results.AppendText(('FEHLER: {0}: {1}{2}' -f $entry.Name, $_.Exception.Message, [Environment]::NewLine))
            }
            foreach ($logFile in @($stdout, $stderr)) {
                if (Test-Path -LiteralPath $logFile) {
                    $logContent = @(Get-Content -LiteralPath $logFile -ErrorAction SilentlyContinue)
                    if ($logContent.Count -gt 0) {
                        $results.AppendText(($logContent -join [Environment]::NewLine) + [Environment]::NewLine)
                    }
                }
            }
            $results.AppendText([Environment]::NewLine)
            $results.SelectionStart = $results.TextLength
            $results.ScrollToCaret()
        }
        [System.Windows.Forms.MessageBox]::Show(
            ('Die Auswahl ist abgeschlossen. Protokolle: {0}' -f $runLog),
            'Installation abgeschlossen',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    finally {
        $script:installationRunning = $false
        $installButton.Enabled = $true
        $selectAllButton.Enabled = $true
        $clearButton.Enabled = $true
        $tree.Enabled = $true
    }
})

$form.ShowDialog() | Out-Null
