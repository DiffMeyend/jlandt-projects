@{
    RootModule        = 'PUR.eDisc.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'c3c5b7a9-9f48-4f8b-9f13-000000000000'
    Author            = 'Jared Landt'
    CompanyName       = 'Community'
    Copyright         = '(c) 2025 Jared Landt. All rights reserved.'
    Description       = 'Helper module for Microsoft Purview eDiscovery (Standard).'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Invoke-PURLitigationSearch',
        'Connect-PurviewSafely',
        'Ensure-Module',
        'Ensure-Case',
        'Ensure-Search',
        'New-KqlQuery',
        'Start-SearchAndWait',
        'Start-Export',
        'Append-ChainLogRow'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('Purview','eDiscovery','Compliance','Litigation','PowerShell')
        }
    }
}
