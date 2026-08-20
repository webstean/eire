
This modules provides the following functions:

Write-StepSummary                       # Pretty output for log, status files
Connect-MSGraphWithClientSecret         # Connect to the Microsoft Graph API with a client secret
Connect-ExchangeOnlineWithClientSecret  # Connect to the Exchange Online with a client secret
Connect-MSGraphWithCertificate          # Connect to the Microsoft Graph API with a certificate
Connect-ExchangeOnlineWithCertificate   # Connect to the Exchange Online with a certificate

Invoke-RobocopyMirrorforNAS             # Perform an Azure Files to NAS copy
Get-DirectoryChecksum                   # Get the directory checksum for a single directory
Compare-DirectoryChecksum               # Compare the checksum on the contents of two directories
Compare-AzureFilesToSharePoint          # Compare the contents of a ShareSite folder to a file shares (one-level only)
Get-SummaryofSharePoint                 # Generate a complete list of all the contents of SharePoint site, including name and size of all files
Get-SummaryofDirectory                  # Generate a complete list of all the contents of Azure Files directory, including name and size of all files


## Example: load this module by manifest path
## Script
#Import-Module -Name "$PSScriptRoot\eire-migration.psd1" -Force
## Interactive
#Import-Module -Name .\eire-migration.psd1 -Force

# Example: load this module by name after installation
#Import-Module -Name 'eire-migration' -Force
