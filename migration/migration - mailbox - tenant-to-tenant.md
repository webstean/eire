# Mailbox Migration Tenant to Tenant

## Introduction

This document describes (in detail) how the mailbox migration will be performed.

## Permissions

The following permission are required in both the source and destination tenants:

API: Office 365 Exchange Online<br>
* Mailbox.Migration [Application]

API: Microsoft Graph<br>
* User.Read.All [Application]
* Application.Read.All [Application]
* Organization.Read.All [Application]
* Group.Read.All [Application]
* GroupMember.Read.All [Application]
* Sites.Read.All [Application]
* Policy.Read.All [Application]

via a multi-tenant Application Registration / Enterprise Application in each tenant. 

## SOURCE tenant: Preparation:
```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Installing Microsoft Graph PowerShell modules..." -ForegroundColor Cyan

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
    else {
        Write-Host "Module already installed: $module" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Importing Microsoft Graph modules..." -ForegroundColor Cyan

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

Connect-MgGraph -Scopes @(
    'Application.ReadWrite.All',
    'AppRoleAssignment.ReadWrite.All',
    'Directory.Read.All'
)

$displayName = 'xxxx-migration-app' ## customise as required

$graphAppId = '00000003-0000-0000-c000-000000000000' ## Microsoft Graph
$graphPermissionNames = @(
    'User.Read.All',
    'Application.Read.All',
    'Organization.Read.All',
    'Group.Read.All',
    'GroupMember.Read.All',
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

$exchangeAppId = '00000003-0000-0000-c000-000000000000'  ## Office 365 Exchange Online
$exchangeSp = Get-MgServicePrincipal `
    -Filter "appId eq '$exchangeAppId'" `
    -Property Id,AppId,DisplayName,AppRoles
$exchangePermissionNames = @(
    'Mailbox.Migration',
)
$exchangeResourceAccess = foreach ($permissionName in $exchangePermissionNames) {
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
            ResourceAccess = $graphResourceAccess
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
Then consent the permissions with the following (or do the consent via the portal):-

```powershell
## Consent for Microsoft Graph
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

## Consent for Exchange Online
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
Finally (via the portal) - create a secret AND an oidc federation for the application registration.
Provide the client_id (application_id), tenant_id and secret and oidc federation to EIRE.

## DESTINATION tenant: Preparation:

Create a migration endpoint (authorised to talk to te source) and establish organisation relationship between destination and the source.

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Installing Exchange Online PowerShell module..." -ForegroundColor Cyan

if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Install-PSResource `
        -Name ExchangeOnlineManagement `
        -Repository PSGallery `
        -TrustRepository `
        -Quiet
}
else {
    Write-Host "Module already installed: ExchangeOnlineManagement" -ForegroundColor DarkGray
}

Write-Host "Importing Exchange Online module..." -ForegroundColor Cyan

Import-Module ExchangeOnlineManagement

Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan

Connect-ExchangeOnline `
    -ShowBanner:$false

Write-Host "Connected to Exchange Online." -ForegroundColor Green

$AppId = "[Guid copied from the source migrations app -above]"
$name = "xxx-migration"
$remote = "<source-tenant>.onmicrosoft.com"
$secret = "[secret copies from the source migration app -above]"
## Enable customization if tenant is dehydrated
$dehydrated = Get-OrganizationConfig | select isdehydrated
if ($dehydrated.isdehydrated -eq $true) {Enable-OrganizationCustomization}
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId, (ConvertTo-SecureString -String $secret -AsPlainText -Force)

New-MigrationEndpoint -RemoteServer outlook.office.com -RemoteTenant $remote -Credentials $Credential -ExchangeRemoteMove:$true -Name $name -ApplicationId $AppId

$sourceTenantId = "[tenant ID of your trusted partner, where the source mailboxes are]"
$orgrelname = "[name of your new organization relationship]"
$orgrels = Get-OrganizationRelationship
$existingOrgRel = $orgrels | ?{$_.DomainNames -like $sourceTenantId}
If ($null -ne $existingOrgRel)
{
    Set-OrganizationRelationship $existingOrgRel.Name -Enabled:$true -MailboxMoveEnabled:$true -MailboxMoveCapability Inbound
}
If ($null -eq $existingOrgRel)
{
    New-OrganizationRelationship $orgrelname -Enabled:$true -MailboxMoveEnabled:$true -MailboxMoveCapability Inbound -DomainNames $sourceTenantId
}
```

## Overview

The migration will be schedule and cordinated via PowerShell scripts.<br>
Specifically, the following two cmdlets<br>
- [New-MigrationBatch](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/start-migrationbatch)
- [Complete-MigrationBatch](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/complete-migrationbatch)

This requires an organisational relationship be setup between the source and desitnation tenants:

Organization relationship (target tenant)
```powershell
New-OrganizationRelationship
```

Migration endpoint (target → source tenant)
```powershell
New-MigrationEndpoint -RemoteServer outlook.office365.com -ExchangeRemoteMove
```

Mailbox mapping (CSV)
```csv
SourceMailbox,TargetMailbox
user1@source.com,user1@target.com
```


```powershell
New-MigrationBatch `
  -Name "Batch1" `
  -SourceEndpoint "CrossTenantEndpoint" `
  -CSVData ([System.IO.File]::ReadAllBytes("users.csv")) `
  -AutoStart $true `
  -AutoComplete $false
```
> ℹ️ **Note**
> The AutoComplete is set to false, so the migration continues indefinately (delta), until it is explciily authorised to be completed.


At the appointed timem the migration is set to "complete" which deletes the mailbox from the source tenants and fully enables it in the destination.

```powershell
Complete-MigrationBatch -Identity "Batch1"
```

## Throughput

Theortical maximum is 10TB per day (as per Microsoft documentation), 2-5TB is typical.

Pilot/POC will determine the exact throughput available between the two tenants.

# Monitoring

Get-MigrationUserStatistics https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-migrationuserstatistics?view=exchange-ps<br>
This commandlet can be run during or at the conclusion of the migration.

```powershell
Get-MigrationUser
Get-MigrationUserStatistics -Identity user@contoso.com -IncludeReport | Format-List Status,Error,Report
```

## Available Statistics

### Identity / status
- Identity<br>
- Status<br>
- StatusDetail<br>
- MigrationState<br>
- MigrationType<br>
- BatchId<br>

### Mailbox identity
- EmailAddress<br>
- MailboxGuid<br>
- ExchangeGuid<br>
- TargetMailboxGuid<br>

### Timing
- QueuedTime<br>
- StartTime<br>
- InitialSeedingCompletedTime<br>
- FinalSyncTime<br>
- CompletionTime<br>

### Progress
- PercentComplete<br>
- BytesTransferred<br>
- BytesTransferredPerMinute<br>
- ItemsTransferred<br>
- ItemsSkipped<br>

### Duration metrics
- TotalInProgressDuration<br>
- TotalQueuedDuration<br>
- TotalFailedDuration<br>
- TotalSuspendedDuration<br>

### Error / diagnostics
- FailureType<br>
- ErrorSummary<br>
- ErrorDetails<br>
- LastFailureTime<br>

### Misc
- SyncedItemCount<br>
- SkippedItemCount<br>

Example statistics:
```text
Identity                       : user@source.com
MigrationType                  : ExchangeRemoteMove
Status                         : Synced
BatchId                        : MigrationBatch01
MailboxGuid                    : 3f2c1c0a-6bfa-4a4a-9c5d-8a6c9c1e1234
MailboxSize                    : 3.45 GB (3,701,234,567 bytes)
ItemsSynced                    : 24873
ItemsSkipped                   : 0
EstimatedTransferSize          : 3.45 GB (3,701,234,567 bytes)
EstimatedTransferItemCount     : 24873
SyncedItemCount                : 24873
SyncedItemsSize                : 3.45 GB (3,701,234,567 bytes)
PercentComplete                : 100

LastSyncedTime                 : 22/04/2026 10:12:45 AM
QueuedTime                     : 22/04/2026 08:55:00 AM
StartTime                      : 22/04/2026 09:00:12 AM
EndTime                        : 22/04/2026 10:12:45 AM

TotalQueuedDuration            : 00:05:12
TotalInProgressDuration        : 01:12:33
TotalTransientFailureDuration  : 00:00:00
TotalIdleDuration              : 00:02:10

Error                          :
FailureCode                    :
FailureType                    :

StatusDetail                   : Completed
Direction                      : Onboarding
Flags                          : None

Report                         : {MailboxMigration, InitialSeedingCompleted, IncrementalSyncCompleted, CompletionFinalized}
```


