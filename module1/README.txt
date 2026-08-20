
This modules provides the following functions:

Write-StepSummary                       # Pretty output for log, status files
Connect-MSGraphWithClientSecret         # Connect to the Microsoft Graph API with a client secret
Connect-ExchangeOnlineWithClientSecret  # Connect to the Exchange Online with a client secret
Connect-MSGraphWithCertificate          # Connect to the Microsoft Graph API with a certificate
Connect-ExchangeOnlineWithCertificate   # Connect to the Exchange Online with a certificate

Invoke-RobocopyMirrorforNAS             # Azure Files to NAS copies
Compare-DirectoryChecksum               # Compare the checksum between two directory
Get-DirectoryChecksum                   # Get the directory checksum for a single directory
Compare-AzureFilesToSharePoint          # Compare 

## Example: load this module by manifest path
## Script
#Import-Module -Name "$PSScriptRoot\eire-migration.psd1" -Force
## Interactive
#Import-Module -Name .\eire-migration.psd1 -Force

# Example: load this module by name after installation
#Import-Module -Name 'eire-migration' -Force
