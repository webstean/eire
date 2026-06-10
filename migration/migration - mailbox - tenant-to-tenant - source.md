# Mailbox Migration Tenant to Tenant (Draft for POC)
# SOURCE tenant setup

## Introduction

This document describes (in detail) setting up the M365 source tenant for supporting the migration of mailboxes to another M365 (destination) tenant.

> ℹ️ **Info**<br>
> EIRE user principals (humans) will need to atleast the 'Global Reader' Entra ID roles in the source M365 tenant.<br>
>

However, since these accounts are readonly, higher prvileges are required to actually perform the migrations, which is enabled via a Service Principal that is created as per the procedure given below.

> ℹ️ **Requirement**<br>
> This procedure and the migraiton itself is dependent on statisfying the tenant's Conditional Access Policies.
>

These setup scripts are intended to be run interactively (by a human) and will required certain authentication consents to already be enabled or to be enabled during execution.<br>

> ℹ️ **Recommendation**<br>
> It is recommended that these steps be performed by the source tenant's 'Global Administrator' <br>
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

**API: Microsoft Graph**<br>
| Permission | Type | Justification
|---|---|:---|
| User.Read.All | Application | Read (but not change) user information
| Application.Read.All | Application | Read (but not change) application information
| Organization.Read.All | Application | Read (but not change) organisation information
| Group.Read.All | Application | Read (but not change) group information (for permission mapping)
| GroupMember.Read.All | Application | Read (but not change) group membership (for permission mapping)  
| Mail.Send | Application | Send email for status tracking throughout migration (cannot read emails)

These permission are required to be grant to a multi-tenant Entra ID Application Registration / Enterprise Application in the source tenant.

## **STEP 1:** Create Application Registration / Enterprise Application
Execute the following PowerShell script to create a dedicated Application Registration / Enterprise Application with the correct permissions to support the migration.<br>

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$PSDefaultParameterValues['*:Verbose'] = $false

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
    'Mail.Send'
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
## **Step 2:** Perfom the consent for Application Registration
Execute the following PowerShell script to provide consent for the assigned application permissions.

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$PSDefaultParameterValues['*:Verbose'] = $false

if ( ($null -eq $app) -or ($null -eq $sp) ) {
    throw 'Critical variables (app and sp) have not been defined - see previous step'
}

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
```
## **Step 3:** Verification
You can inspect the result in the portal:-
<img width="1142" height="819" alt="image" src="https://github.com/user-attachments/assets/dac865f5-1b82-4c93-bde6-9c289977e458" />

## **Step 4A:** Create either a client secret or certificate for the created Enterprise Application
Via the portal - create either a client secret or certificate<br>
[English - Microsoft Documentation - Create a Certificate](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials?tabs=certificate#tabpanel_1_certificate)<br>
[Japanese - Microsoft Documentation - Create a Certificate](https://learn.microsoft.com/ja-JP/entra/identity-platform/how-to-add-credentials?tabs=certificate#tabpanel_1_certificate)<br>
or<br>
[English - Microsoft Documentation - Create a Client Secret](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials?tabs=certificate#tabpanel_1_client-secret)<br>
[Japanese - Microsoft Documentation - Create a Client Secret](https://learn.microsoft.com/ja-JP/entra/identity-platform/how-to-add-credentials?tabs=certificate#tabpanel_1_client-secret)<br>

## **Step 4B:** Configure OIDC Federation for the created Enterprise Application
Via the portal - create a oidc federation (Federated Credentials) for the application registration (as per below)<br>
[English - Microsoft Documentation - Create a Federated Credential](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials?tabs=certificate#tabpanel_1_federated-credential)<br>
[Japanese - Microsoft Documentation - Create a Federated Credential](https://learn.microsoft.com/jp-JA/entra/identity-platform/how-to-add-credentials?tabs=certificate#tabpanel_1_federated-credential)<br>

```text
Scenario: GitHub Action
Subject Identifier: repo:webstean/eire:ref:refs/heads/main
```
<img width="1421" height="610" alt="image" src="https://github.com/user-attachments/assets/43526dfa-11f4-4df1-8489-f68d2e26bb86" />
<img width="878" height="729" alt="image" src="https://github.com/user-attachments/assets/7c8f673c-44c1-45c8-bcdd-3e164b16fecc" />
<img width="1340" height="590" alt="image" src="https://github.com/user-attachments/assets/b63e1c64-42ba-4e55-b3c2-df16b9172197" />

## **Step 5:** Provide Details
Provide the following to EIRE (mailto:Andrew.Webster@eire.com)<br>
- the client_id (application_id)
- the tenant_id
- the secret or certificate (this will probably need to be sent via some sort of secure method) - These **SHOULD NOT** be emailed.
- confirmation that oidc federation has been configured as per above.

<img width="1409" height="293" alt="image" src="https://github.com/user-attachments/assets/9a8dde79-6019-483b-81b8-024f8ca895de" />

## **Step:** Once migration complete, set Out of Office on old mailboxes.

The migrated mailboxes will need to be recreated - properly as 'Shared Mailboxes' to avoid licensing costs.

Based a upon a CSV file, for example
```csv

```

```powershell
function Set-BulkMailboxOutOfOffice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CsvPath
    )

    Import-Csv $CsvPath | ForEach-Object {
        Set-MailboxAutoReplyConfiguration `
            -Identity $_.UserPrincipalName `
            -AutoReplyState Scheduled `
            -StartTime $_.StartTime `
            -EndTime $_.EndTime `
            -InternalMessage $_.InternalMessage `
            -ExternalMessage $_.ExternalMessage `
            -ExternalAudience All

        Write-Host "Updated OOF for $($_.UserPrincipalName)"
    }
}
```




