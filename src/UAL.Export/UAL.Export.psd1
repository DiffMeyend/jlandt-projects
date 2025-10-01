@{
    RootModule        = 'UAL.Export.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b99c1e9f-713b-4d8f-a222-000000000000'
    Author            = 'Jared Landt'
    CompanyName       = 'Community'
    Description       = 'Unified Audit Log (UAL) export helpers: normalize records, append paged results to CSV + NDJSON, pull full time slices.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Convert-UalToRows',
        'Write-UalPage',
        'Invoke-UalSlice'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('AuditLog','ExchangeOnline','Purview','UAL','Export','PowerShell')
        }
    }
}
