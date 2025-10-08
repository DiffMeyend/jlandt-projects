Describe 'SPO.SecureSite Module' {
    It 'Should import without errors' {
        { Import-Module "$PSScriptRoot\..\src\SPO.SecureSite\SPO.SecureSite.psd1" -Force } | Should -Not -Throw
    }

    It 'Should expose New-HRSiteProvisioning' {
        Get-Command New-HRSiteProvisioning -Module SPO.SecureSite | Should -Not -BeNullOrEmpty
    }
}
