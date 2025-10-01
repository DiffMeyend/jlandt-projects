Describe 'UAL.Export Module' {
    It 'Should import without errors' {
        { Import-Module "$PSScriptRoot\..\src\UAL.Export\UAL.Export.psd1" -Force } | Should -Not -Throw
    }

    It 'Should expose expected functions' {
        Get-Command Convert-UalToRows -Module UAL.Export | Should -Not -BeNullOrEmpty
        Get-Command Write-UalPage -Module UAL.Export | Should -Not -BeNullOrEmpty
        Get-Command Invoke-UalSlice -Module UAL.Export | Should -Not -BeNullOrEmpty
    }
}
