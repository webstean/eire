# Mailbox Migration Tenant to Tenant (Draft for POC)
# SOURCE tenant setup

## Introduction

This document describes (in detail) setting up the M365 source tenant for migration to a M365 destination tenant.

> ℹ️ **Info**<br>
> EIRE user principals (humans) will need to atleast the 'Global Reader' Entra ID roles in both the source M365 tenant.<br>
>

However, since these accounts are readonly, higher prvileges are required to actually perform the migrations, which is enabled via a Service Principal that is created as per the procedure given below.

> ℹ️ **Requirement**<br>
> This procedure and the migraiton itself is dependent on statisfying the tenant's Conditional Access Policies.
>

These setup scripts are intended to be run interactively (by a human) and will required certain authentication consents to already be enabled or to be enabled during execution.<br>

> ℹ️ **Recommendation**<br>
> It is recommended that these stesp by performed by the source tenant's 'Global Administrator' <br>
>

## Permissions Overview

The following are the required permission in the source tenant:

> ℹ️ **Note**<br>
> The mailbox migration is utlimately controlled from the destination tenant.<br>
>

**API: Office 365 Exchange Online**<br>
| Permission | Type | Justification
|---|---|:---|
| Mailbox.Migration | Application | Migrate mailboxes
| Exchange.ManageAsApp | Application | Access Exchange as an application
| Organization.Read.All | Application | Read (but not change) Exchange settings
| PeopleSettings.Read.All | Application | Read (but not change) Exchage user settings 
| SMTP.SendAsApp | Application | Send email on behalf of app for reporting (cannot read emails)
| MailboxSettings.ReadWrite | Application | Create mailboxes 


**API: Microsoft Graph**<br>
| Permission | Type | Justification
|---|---|:---|
| User.Read.All | Application | Read (but not change) user information
| Application.Read.All | Application | Read (but not change) application information
| Organization.Read.All | Application | Read (but not change) organisation information
| Group.Read.All | Application | Read (but not change) group information (for permission mapping)
| GroupMember.Read.All | Application | Read (but not change) group membership (for permission mapping)  
| Sites.Read.All | Application | Read (but not change) sites
| Mail.Send | Application | Send email for status tracking throughout migration (cannot read emails)
| Policy.Read.All | Application | Read (but not change) policies including Conditional Access

These permission are required to be grant to a multi-tenant Entra ID Application Registration / Enterprise Application in the source tenant.

## **STEP 1:** Create Application Registration / Enterprise Application (PowerShell script)
```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$displayName = 'xxxx-migration-app' ## customise as required

$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications'
)
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing module: $module" -ForegroundColor Yellow
        Install-PSResource `
            -Name $module `
            -Repository PSGallery `
            -TrustRepository `
            -Quiet
    }
}
Write-Host "Importing Microsoft Graph modules..." -ForegroundColor Cyan
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

Write-Host "Connecting interactively to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes @(
    'Application.ReadWrite.All',
    'AppRoleAssignment.ReadWrite.All',
    'Directory.Read.All'
) ## You maybe prompted to consent to the scope, depending upon your tenancy configuration. You must consent for everything else to be succesful.
## You may have to run this more than once, due to the lag in the consent being recognised.

$graphAppId = '00000003-0000-0000-c000-000000000000' ## Microsoft Graph
$graphPermissionNames = @(
    'User.Read.All',
    'Application.Read.All',
    'Organization.Read.All',
    'Group.Read.All',
    'GroupMember.Read.All',
    'Mail.Send',
    'Sites.Read.All',
    'Policy.Read.All'
)
$graphSp = Get-MgServicePrincipal `
    -Filter "appId eq '$graphAppId'" `
    -Property Id,AppId,DisplayName,AppRoles
$graphResourceAccess = foreach ($permissionName in $graphPermissionNames) {
    $role = $graphSp.AppRoles | Where-Object {
        $_.Value -eq $permissionName -and
        $_.AllowedMemberTypes -contains 'Application' -and
        $_.IsEnabled
    }
    if (-not $role) {
        throw "Graph application permission not found: $permissionName"
    }
    @{
        Id   = $role.Id
        Type = 'Role'
    }
}

$exchangeAppId = '00000002-0000-0ff1-ce00-000000000000'  ## Office 365 Exchange Online
$exchangePermissionNames = @(
    'Mailbox.Migration',
    'Organization.Read.All',
    'PeopleSettings.Read.All',
    'MailboxSettings.ReadWrite',
    'SMTP.SendAsApp',
    'Exchange.ManageAsApp'
)
$exchangeSp = Get-MgServicePrincipal `
    -Filter "appId eq '$exchangeAppId'" `
    -Property Id,AppId,DisplayName,AppRoles
$exchangeResourceAccess = foreach ($permissionName in $exchangePermissionNames) {
    $role = $exchangeSp.AppRoles | Where-Object {
        $_.Value -eq $permissionName -and
        $_.AllowedMemberTypes -contains 'Application' -and
        $_.IsEnabled
    }
    if (-not $role) {
        throw "Graph application permission not found: $permissionName"
    }
    @{
        Id   = $role.Id
        Type = 'Role'
    }
}

$app = New-MgApplication `
    -DisplayName $displayName `
    -SignInAudience AzureADMultipleOrgs `
    -Web @{
        RedirectUris = @(
            'https://office.com'
        )
    } `
    -RequiredResourceAccess @(
        @{
            ResourceAppId  = $graphAppId
            ResourceAccess = $graphResourceAccess
        }
        @{
            ResourceAppId  = $exchangeAppId
            ResourceAccess = $exchangeResourceAccess
        }
    )

Write-Host "Application created successfully." -ForegroundColor Green
Write-Host "  Display Name : $($app.DisplayName)"
Write-Host "  App ID       : $($app.AppId)"
Write-Host "  Object ID    : $($app.Id)"
Write-Host ""

$sp = New-MgServicePrincipal -AppId $app.AppId

Write-Host "Service principal created successfully." -ForegroundColor Green
Write-Host "  Display Name : $($sp.DisplayName)"
Write-Host "  Object ID    : $($sp.Id)"
Write-Host "  App ID       : $($sp.AppId)"
Write-Host ""

```
## **Step 2:** Perfom the consent for the Entra ID permissions within the Application Registration with the following PowerShell script:-

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

## Administrator consent for Microsoft Graph API calls for migrations
foreach ($permissionName in $graphPermissionNames) {
    $role = $graphSp.AppRoles | Where-Object {
        $_.Value -eq $permissionName -and
        $_.AllowedMemberTypes -contains 'Application' -and
        $_.IsEnabled
    }

    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $sp.Id `
        -PrincipalId $sp.Id `
        -ResourceId $graphSp.Id `
        -AppRoleId $role.Id
}

## Administrator consent for Exchange Online API calls for migrations
foreach ($permissionName in $exchangePermissionNames) {
    $role = $exchangeSp.AppRoles | Where-Object {
        $_.Value -eq $permissionName -and
        $_.AllowedMemberTypes -contains 'Application' -and
        $_.IsEnabled
    }

    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $sp.Id `
        -PrincipalId $sp.Id `
        -ResourceId $exchangeSp.Id `
        -AppRoleId $role.Id
}
---

## **Step 3:** On the assumption, that Access Permissions have been enabled, the Mail.Send permission won't work. To resolve this, the application must be explicity authorised to send emails to anyone in the organisation with the following PowerShell script:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

## Add role (part of ExchangeOnlineManagement module)
New-ManagementRoleAssignment `
    -Name "App-SMTP-SendAsApp-OrgWide" `
    -Role "Application SMTP.SendAsApp" `
    -App "$($app.Id)" ## Application ID from above
```

## **Step 4:** Verification

You can inspect the result in the portal:-
<img width="1142" height="819" alt="image" src="https://github.com/user-attachments/assets/dac865f5-1b82-4c93-bde6-9c289977e458" />

## **Step 5:** Create Secret and OIDC FEderation

Then finally via the portal - create a secret AND an oidc federation (Federated Credentials) for the application registration (as per below)<br>

```text
Scenario: GitHub Action
Subject Identifier: repo:webstean/eire:ref:refs/heads/main
```
<img width="1421" height="610" alt="image" src="https://github.com/user-attachments/assets/43526dfa-11f4-4df1-8489-f68d2e26bb86" />
<img width="878" height="729" alt="image" src="https://github.com/user-attachments/assets/7c8f673c-44c1-45c8-bcdd-3e164b16fecc" />
<img width="1340" height="590" alt="image" src="https://github.com/user-attachments/assets/b63e1c64-42ba-4e55-b3c2-df16b9172197" />

**Provide** the client_id (application_id), tenant_id and secret plus confirm the oidc federation to EIRE (mailto:Andrew.Webster@eire.com)
<img width="1409" height="293" alt="image" src="https://github.com/user-attachments/assets/9a8dde79-6019-483b-81b8-024f8ca895de" />

