Describe 'SPO.HRSite Module' {
    It 'Should import without errors' {
        { Import-Module "$PSScriptRoot\..\src\SPO.HRSite\SPO.HRSite.psd1" -Force } | Should -Not -Throw
    }

    It 'Should expose New-HRSiteProvisioning' {
        Get-Command New-HRSiteProvisioning -Module SPO.HRSite | Should -Not -BeNullOrEmpty
    }
}
