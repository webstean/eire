

## **Step ** Assign the Exchange Role to send email
On the assumption, that Access Permissions have been enabled, the Mail.Send permission won't work. To resolve this, the application must be explicity authorised to send emails to anyone in the organisation with the following PowerShell script: <br>

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

if ( ($null -eq $app) -or ($null -eq $sp) ) {
    throw 'Critical variables (app and sp) have not been defined - see previous step'
}

if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Host "Installing Exchange Online PowerShell module..." -ForegroundColor Cyan
    Install-PSResource `
        -Name ExchangeOnlineManagement `
        -Repository PSGallery `
        -TrustRepository `
        -Quiet
}
Write-Host "Importing Exchange Online module..." -ForegroundColor Cyan
Import-Module ExchangeOnlineManagement

Write-Host "Interactively connecting to Exchange Online..." -ForegroundColor Cyan
Connect-ExchangeOnline -ShowBanner:$false
Write-Host "Connected to Exchange Online." -ForegroundColor Green

## Create a management scope
$scope = New-ManagementScope `
    -Name "Migration-Mailbox-Sender" `
    -RecipientRestrictionFilter "PrimarySmtpAddress -eq 'migration@contoso.com'"

## Add role (part of ExchangeOnlineManagement module)
New-ManagementRoleAssignment `
    -Name "App-SMTP-SendAsApp-OrgWide" `
    -Role "Application SMTP.SendAsApp" `
    -App "$($app.Id)" `
    -CustomResourceScope "$($scope.DisplayName)"
```
