# scripts/Invoke-PUR_LitigationSearch.ps1
Import-Module "$PSScriptRoot\..\src\PUR.eDisc\PUR.eDisc.psd1" -Force
Invoke-PURLitigationSearch @args
