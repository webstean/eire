@{
    RootModule        = 'eire-migration.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = '02234567-89ab-cdef-0123-456789abcdef'
    Author            = 'Andrew Webster'
    CompanyName       = 'Eire Systems'
    Description       = 'Microsoft Graph Connection, Utility and Copy Functions for PowerShell'

    #PowerShellVersion = '5.1' ## Minimum PowerShell version required to use this module
    PowerShellVersion = '7.4' ## Minimum PowerShell version required to use this module

    RequiredModules   = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Applications',
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Groups',
        'ExchangeOnlineManagement',
        'PnP.PowerShell'
    )

    FunctionsToExport = @(
        'Write-StepSummary',
        'Connect-MSGraphWithClientSecret',
        'Connect-ExchangeOnlineWithClientSecret',
        'Connect-MSGraphWithCertificate',
        'Connect-ExchangeOnlineWithCertificate',
        'Invoke-RobocopyMirrorforNAS',
        'Compare-DirectoryChecksum',
        'Get-DirectoryChecksum',
        'Get-SummaryofSharePoint',
        'Get-SummaryofDirectory',
        'Compare-AzureFilesToSharePoint'
    )
}

## Example: load this module by manifest path
## Script
#Import-Module -Name "$PSScriptRoot\eire-migration.psd1" -Force
## Interactive
#Import-Module -Name .\eire-migration.psd1 -Force

