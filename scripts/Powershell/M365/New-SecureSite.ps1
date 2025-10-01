# Wrapper script for quick use
Import-Module "$PSScriptRoot\..\src\SPO.HRSite\SPO.HRSite.psd1" -Force
New-HRSiteProvisioning @args
