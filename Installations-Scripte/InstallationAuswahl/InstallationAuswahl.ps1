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

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PhinIT | Installationsauswahl"
        Width="1080" Height="760" MinWidth="900" MinHeight="620"
        WindowStartupLocation="CenterScreen"
        Background="#F4F6FA" FontFamily="Segoe UI" FontSize="13"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <SolidColorBrush x:Key="Ink" Color="#17243A"/>
        <SolidColorBrush x:Key="Muted" Color="#748197"/>
        <SolidColorBrush x:Key="Accent" Color="#3468D4"/>
        <SolidColorBrush x:Key="Line" Color="#E5EAF1"/>
        <Style TargetType="{x:Type Button}">
            <Setter Property="Foreground" Value="#34435A"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#DDE4EE"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,9"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Button}">
                        <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Background" Value="#F4F7FC"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.55"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="PrimaryButton" TargetType="{x:Type Button}" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="#3468D4"/>
            <Setter Property="BorderBrush" Value="#3468D4"/>
        </Style>
        <Style TargetType="{x:Type ListBoxItem}">
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Margin" Value="0,2"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ListBoxItem}">
                        <Border x:Name="CategoryBorder" Background="Transparent" CornerRadius="7" Padding="10,9">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="CategoryBorder" Property="Background" Value="#EAF0FC"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CategoryBorder" Property="Background" Value="#F0F4FA"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="{x:Type CheckBox}">
            <Setter Property="Foreground" Value="#26364D"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="4,6"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>
    <Grid Margin="26">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0" Margin="0,0,0,22">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock Text="Software bereitstellen" FontSize="25" FontWeight="Bold"
                           Foreground="{StaticResource Ink}"/>
                <TextBlock Text="Installationspakete auswählen und gemeinsam starten"
                           Margin="0,5,0,0" Foreground="{StaticResource Muted}"/>
            </StackPanel>
            <Border Grid.Column="1" Background="White" BorderBrush="{StaticResource Line}"
                    BorderThickness="1" CornerRadius="16" Padding="12,7" VerticalAlignment="Center">
                <StackPanel Orientation="Horizontal">
                    <Ellipse Width="7" Height="7" Fill="#35A879" Margin="0,0,8,0"/>
                    <TextBlock Text="Eigenständiger Modus" Foreground="#4F5E73" FontSize="12"/>
                </StackPanel>
            </Border>
        </Grid>
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="235"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="White" BorderBrush="{StaticResource Line}"
                    BorderThickness="1" CornerRadius="11" Padding="15">
                <DockPanel>
                    <StackPanel DockPanel.Dock="Top" Margin="2,2,2,10">
                        <TextBlock Text="KATEGORIEN" FontSize="11" FontWeight="Bold"
                                   Foreground="{StaticResource Muted}" Margin="0,0,0,5"/>
                        <TextBlock Text="Nach Bereich filtern" FontSize="12"
                                   Foreground="{StaticResource Muted}"/>
                    </StackPanel>
                    <ListBox x:Name="CategoryList" BorderThickness="0" Background="Transparent"
                             ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                        <ListBox.ItemTemplate>
                            <DataTemplate>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="{Binding Name}" VerticalAlignment="Center"
                                               Foreground="#34435A" TextTrimming="CharacterEllipsis"/>
                                    <Border Grid.Column="1" Background="#F0F3F8" CornerRadius="9"
                                            Padding="7,2" Margin="8,0,0,0">
                                        <TextBlock Text="{Binding Count}" FontSize="11"
                                                   Foreground="#68768B"/>
                                    </Border>
                                </Grid>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
                </DockPanel>
            </Border>
            <Grid Grid.Column="1" Margin="16,0,0,0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="190"/>
                </Grid.RowDefinitions>
                <Border Grid.Row="0" Background="White" BorderBrush="{StaticResource Line}"
                        BorderThickness="1" CornerRadius="11" Padding="18">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <Grid Grid.Row="0" Margin="0,0,0,12">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="260"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel>
                                <TextBlock x:Name="ItemsTitle" Text="Alle Installationen"
                                           FontSize="17" FontWeight="SemiBold" Foreground="{StaticResource Ink}"/>
                                <TextBlock x:Name="ItemsSubtitle" Text="Programme für die Auswahl"
                                           Margin="0,3,0,0" FontSize="12" Foreground="{StaticResource Muted}"/>
                            </StackPanel>
                            <TextBox x:Name="SearchBox" Grid.Column="1" Height="36"
                                     VerticalContentAlignment="Center" Padding="10,4"
                                     BorderBrush="{StaticResource Line}" BorderThickness="1"
                                     Background="#FAFBFD" Foreground="#34435A"
                                     ToolTip="Programme suchen"/>
                        </Grid>
                        <Border Grid.Row="1" Background="#F7F9FC" CornerRadius="6"
                                Padding="10,7" Margin="0,0,0,8">
                            <TextBlock Text="Mehrere Programme auswählen. Installiert wird erst nach Bestätigung."
                                       FontSize="12" Foreground="{StaticResource Muted}"/>
                        </Border>
                        <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto"
                                      HorizontalScrollBarVisibility="Disabled">
                            <ItemsControl x:Name="InstallerList">
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <Border BorderBrush="#EDF0F5" BorderThickness="0,0,0,1" Padding="5,3">
                                            <CheckBox Content="{Binding Name}" IsChecked="{Binding IsSelected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"/>
                                        </Border>
                                    </DataTemplate>
                                </ItemsControl.ItemTemplate>
                            </ItemsControl>
                        </ScrollViewer>
                    </Grid>
                </Border>
                <Border Grid.Row="1" Background="White" BorderBrush="{StaticResource Line}"
                        BorderThickness="1" CornerRadius="11" Padding="16" Margin="0,14,0,0">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <Grid Grid.Row="0" Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Ausführungsprotokoll" FontWeight="SemiBold"
                                       Foreground="{StaticResource Ink}"/>
                            <TextBlock x:Name="RunStatus" Grid.Column="1" Text="Bereit"
                                       Foreground="{StaticResource Muted}" FontSize="12"/>
                        </Grid>
                        <TextBox x:Name="ResultsBox" Grid.Row="1" IsReadOnly="True"
                                 Text="Ergebnisse und Protokollpfad erscheinen hier."
                                 Background="#F8FAFC" BorderThickness="0" Padding="10"
                                 Foreground="#536176" FontFamily="Consolas" FontSize="11"
                                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                                 TextWrapping="NoWrap"/>
                    </Grid>
                </Border>
            </Grid>
        </Grid>
        <Grid Grid.Row="2" Margin="0,18,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <Ellipse x:Name="SelectionDot" Width="8" Height="8" Fill="#A8B2C1" Margin="0,0,9,0"/>
                <TextBlock x:Name="SelectionCount" Text="0 Programme ausgewählt"
                           Foreground="#526176" FontWeight="SemiBold"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
                <Button x:Name="SelectAllButton" Content="Alle auswählen" Margin="0,0,8,0"/>
                <Button x:Name="ClearButton" Content="Auswahl aufheben" Margin="0,0,8,0"/>
                <Button x:Name="InstallButton" Content="Installation starten" Style="{StaticResource PrimaryButton}"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
'@

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
$xmlReader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($xmlReader)

$categoryList = $window.FindName('CategoryList')
$itemsTitle = $window.FindName('ItemsTitle')
$itemsSubtitle = $window.FindName('ItemsSubtitle')
$searchBox = $window.FindName('SearchBox')
$installerList = $window.FindName('InstallerList')
$resultsBox = $window.FindName('ResultsBox')
$runStatus = $window.FindName('RunStatus')
$selectionCount = $window.FindName('SelectionCount')
$selectionDot = $window.FindName('SelectionDot')
$selectAllButton = $window.FindName('SelectAllButton')
$clearButton = $window.FindName('ClearButton')
$installButton = $window.FindName('InstallButton')

foreach ($entry in $catalog) {
    $entry | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false
}
$script:visibleCatalog = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$categoryItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$categoryItems.Add([pscustomobject]@{ Name = 'Alle Installationen'; Category = $null; Count = $catalog.Count })
foreach ($categoryName in @($catalog | Select-Object -ExpandProperty Category -Unique | Sort-Object)) {
    $count = @($catalog | Where-Object { $_.Category -eq $categoryName }).Count
    $categoryItems.Add([pscustomobject]@{ Name = $categoryName; Category = $categoryName; Count = $count })
}
$categoryList.ItemsSource = $categoryItems
$categoryList.SelectedIndex = 0
$installerList.ItemsSource = $script:visibleCatalog

function Show-SelectionSummary {
    param([bool]$InstallationActive = $false)
    $count = @($catalog | Where-Object { $_.IsSelected }).Count
    $selectionCount.Text = '{0} Programm{1} ausgewählt' -f $count, $(if ($count -eq 1) { '' } else { 'e' })
    $selectionDot.Fill = if ($count -gt 0) { [System.Windows.Media.Brushes]::SeaGreen } else { [System.Windows.Media.Brushes]::SlateGray }
    $installButton.IsEnabled = ($count -gt 0 -and -not $InstallationActive)
}

function Show-VisibleInstallerList {
    $selectedCategory = $categoryList.SelectedItem
    if ($null -eq $selectedCategory) { return }
    $searchTerm = [string]$searchBox.Text
    $itemsTitle.Text = $selectedCategory.Name
    if ($selectedCategory.Category) {
        $matchingCategory = @($catalog | Where-Object { $_.Category -eq $selectedCategory.Category })
    }
    else {
        $matchingCategory = $catalog
    }
    $filtered = @($matchingCategory | Where-Object {
        [string]::IsNullOrWhiteSpace($searchTerm) -or $_.Name.IndexOf($searchTerm, [StringComparison]::OrdinalIgnoreCase) -ge 0
    } | Sort-Object Name)
    $itemsSubtitle.Text = if ($filtered.Count -eq 1) { '1 Programm verfügbar' } else { '{0} Programme verfügbar' -f $filtered.Count }
    $script:visibleCatalog.Clear()
    foreach ($entry in $filtered) { $script:visibleCatalog.Add($entry) }
}

$categoryList.Add_SelectionChanged({ Show-VisibleInstallerList })
$searchBox.Add_TextChanged({ Show-VisibleInstallerList })
$checkedHandler = [System.Windows.RoutedEventHandler]{ Show-SelectionSummary }
$installerList.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent, $checkedHandler)
$installerList.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, $checkedHandler)
$selectAllButton.Add_Click({
    foreach ($entry in $script:visibleCatalog) { $entry.IsSelected = $true }
    $installerList.Items.Refresh()
    Show-SelectionSummary
})
$clearButton.Add_Click({
    foreach ($entry in $catalog) { $entry.IsSelected = $false }
    $installerList.Items.Refresh()
    Show-SelectionSummary
})
function Invoke-WpfDispatcherPump {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $stopFrame = [Action]{ $frame.Continue = $false }
    $null = $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, $stopFrame)
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

$installButton.Add_Click({
    $selected = @($catalog | Where-Object { $_.IsSelected } | Sort-Object Category, Name)
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            $window,
            'Bitte mindestens ein Programm auswählen.',
            'Keine Auswahl',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
        return
    }
    $names = ($selected | ForEach-Object { '• ' + $_.Name }) -join [Environment]::NewLine
    $confirmation = [System.Windows.MessageBox]::Show(
        $window,
        "Folgende Programme werden nacheinander installiert:`r`n`r`n$names`r`n`r`nVorhandene Programme werden standardmäßig nicht aktualisiert. Fortfahren?",
        'Installation bestätigen',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    if ($confirmation -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $selectAllButton.IsEnabled = $false
    $clearButton.IsEnabled = $false
    $categoryList.IsEnabled = $false
    $searchBox.IsEnabled = $false
    $installerList.IsEnabled = $false
    $runStatus.Text = 'Installation läuft'
    $resultsBox.Clear()
    $logRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'PhinIT-Installation-Auswahl'
    $runLog = Join-Path $logRoot (Get-Date -Format 'yyyyMMdd-HHmmss')

    try {
        New-Item -Path $runLog -ItemType Directory -Force | Out-Null
        $resultsBox.AppendText(('Protokollordner: {0}{1}{1}' -f $runLog, [Environment]::NewLine))
        foreach ($entry in $selected) {
            $resultsBox.AppendText(('Starte: {0}{1}' -f $entry.Name, [Environment]::NewLine))
            $resultsBox.ScrollToEnd()
            Invoke-WpfDispatcherPump
            $safeName = [regex]::Replace($entry.Name, '[^\p{L}\p{Nd}._-]', '_')
            $stdout = Join-Path $runLog ($safeName + '.stdout.log')
            $stderr = Join-Path $runLog ($safeName + '.stderr.log')
            try {
                $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
                    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $entry.Path), '-AllowInstall', 'true') `
                    -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
                while (-not $process.HasExited) {
                    Start-Sleep -Milliseconds 200
                    Invoke-WpfDispatcherPump
                }
                $process.WaitForExit()
                $status = if ($process.ExitCode -eq 0) { 'ERFOLG' } else { 'FEHLER' }
                $resultsBox.AppendText(('{0}: {1} (Exitcode {2}){3}' -f $status, $entry.Name, $process.ExitCode, [Environment]::NewLine))
            }
            catch {
                $resultsBox.AppendText(('FEHLER: {0}: {1}{2}' -f $entry.Name, $_.Exception.Message, [Environment]::NewLine))
            }
            foreach ($logFile in @($stdout, $stderr)) {
                if (Test-Path -LiteralPath $logFile) {
                    $logContent = @(Get-Content -LiteralPath $logFile -ErrorAction SilentlyContinue)
                    if ($logContent.Count -gt 0) {
                        $resultsBox.AppendText(($logContent -join [Environment]::NewLine) + [Environment]::NewLine)
                    }
                }
            }
            $resultsBox.AppendText([Environment]::NewLine)
            $resultsBox.ScrollToEnd()
            Invoke-WpfDispatcherPump
        }
        $runStatus.Text = 'Auswahl abgeschlossen'
        [System.Windows.MessageBox]::Show(
            $window,
            ('Die Auswahl ist abgeschlossen. Protokolle: {0}' -f $runLog),
            'Installation abgeschlossen',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        ) | Out-Null
    }
    catch {
        $runStatus.Text = 'Fehler beim Ausführen'
        $resultsBox.AppendText(('FEHLER: {0}{1}' -f $_.Exception.Message, [Environment]::NewLine))
    }
    finally {
        $selectAllButton.IsEnabled = $true
        $clearButton.IsEnabled = $true
        $categoryList.IsEnabled = $true
        $searchBox.IsEnabled = $true
        $installerList.IsEnabled = $true
        Show-SelectionSummary
    }
})

Show-VisibleInstallerList
Show-SelectionSummary
$window.ShowDialog() | Out-Null
