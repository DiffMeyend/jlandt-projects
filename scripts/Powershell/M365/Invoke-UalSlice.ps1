# Thin wrapper for quick runs
Import-Module "$PSScriptRoot\..\src\UAL.Export\UAL.Export.psd1" -Force
Invoke-UalSlice @args
