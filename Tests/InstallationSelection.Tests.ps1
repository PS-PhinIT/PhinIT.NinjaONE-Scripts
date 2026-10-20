BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $selectionScript = Join-Path $root 'Installations-Scripte/InstallationAuswahl/InstallationAuswahl.ps1'
}

Describe 'Standalone installation selector / Eigenständige Installationsauswahl' {
    It 'lists all install scripts with a category and tool name / listet alle Installationsskripte kategorisiert' {
        $catalog = @(& $selectionScript -ListOnly | ConvertFrom-Json)
        $expectedCount = @(Get-ChildItem -LiteralPath (Join-Path $root 'Installations-Scripte') -Filter 'install*.ps1' -File).Count

        $catalog.Count | Should -Be $expectedCount
        @($catalog | Where-Object { [string]::IsNullOrWhiteSpace($_.Name) -or [string]::IsNullOrWhiteSpace($_.Category) }).Count | Should -Be 0
        @($catalog | Select-Object -ExpandProperty FileName -Unique).Count | Should -Be $expectedCount
    }

    It 'does not start the graphical interface in list-only mode / öffnet im Listenmodus keine Oberfläche' {
        { & $selectionScript -ListOnly | ConvertFrom-Json } | Should -Not -Throw
    }
}
