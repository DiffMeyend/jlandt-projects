# Wrapper script for quick use
Import-Module "$PSScriptRoot\..\src\SPO.SecureSite\SPO.SecureSite.psd1" -Force
New-HRSiteProvisioning @args
