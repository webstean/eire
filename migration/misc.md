

## **Step ** Assign the Exchange Role to send email
On the assumption, that Access Permissions have been enabled, the Mail.Send permission won't work. To resolve this, the application must be explicity authorised to send emails to anyone in the organisation with the following PowerShell script: <br>

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$PSDefaultParameterValues['*:Verbose'] = $false

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

$scopeName = 'Hub-M365-Mailboxes'
$filter = "Alias -like 'HUB_*'"

$scope = Get-ManagementScope `
    -Identity $scopeName `
    -ErrorAction SilentlyContinue

if ($null -eq $scope) {
    Write-Host "Creating management scope: $scopeName"
    $scope = New-ManagementScope `
        -Name $scopeName `
        -RecipientRestrictionFilter $filter `
        -ErrorAction Stop
}
else {
    Write-Host "Updating management scope: $scopeName"
    $scope = Set-ManagementScope `
        -Identity $scopeName `
        -RecipientRestrictionFilter $filter `
        -Confirm:$false `
        -ErrorAction Stop

    $scope = Get-ManagementScope `
        -Identity $scopeName `
        -ErrorAction Stop
}

if ( ($null -eq $app) -or ($null -eq $sp) ) {
    throw 'Critical variables (app and sp) have not been defined - see previous step'
}

## Add role (part of ExchangeOnlineManagement module)
New-ManagementRoleAssignment `
    -Name "App-SMTP-SendAsApp-OrgWide" `
    -Role "Application SMTP.SendAsApp" `
    -App "$($app.Id)" `
    -CustomResourceScope "$($scope.Name)"
```
