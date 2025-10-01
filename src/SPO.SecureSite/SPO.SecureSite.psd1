@{
    RootModule        = 'SPO.HRSite.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'd98e3e76-9fd7-42b2-a111-000000000000'
    Author            = 'Jared Landt'
    CompanyName       = 'Community'
    Description       = 'Provision standalone SharePoint Online communication sites with secure HR libraries.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('New-HRSiteProvisioning')
    PrivateData = @{
        PSData = @{
            Tags = @('SharePoint','PnP.PowerShell','Graph','Provisioning','Teams')
        }
    }
}
