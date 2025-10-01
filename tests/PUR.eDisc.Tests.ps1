# Basic test file for PUR.eDisc
# Run with: Invoke-Pester -Path ./tests

Describe 'PUR.eDisc Module' {
    It 'Should import without errors' {
        { Import-Module "$PSScriptRoot\..\src\PUR.eDisc\PUR.eDisc.psd1" -Force } | Should -Not -Throw
    }

    It 'Should expose Invoke-PURLitigationSearch' {
        Get-Command Invoke-PURLitigationSearch -Module PUR.eDisc | Should -Not -BeNullOrEmpty
    }
}
