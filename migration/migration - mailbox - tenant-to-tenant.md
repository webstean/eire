# Mailbox Migration Tenant to Tenant (Draft for POC)

## Introduction

This document describes (in detail) how the mailbox migration will be setup and performed.<br>

It is expected, the EIRE user principal will have atleast 'Global Reader' in both the source and destination tenants.<br>
But, higher prvileges are required to actually perform the migrations, which is enabled via a Service Principal that is created as per the procedure given below.

> ℹ️ **Requirement**
> All logons (User & Service Principals) must be able to satisfy the respective tenant's Conditional Access Policies.

All scripts are intended to be run interactively and will required certain authentication consents to already be enabled or being enabled during execution.

## Permissions

The following are the required permission in both the source and destination tenants:

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

via a multi-tenant Application Registration / Enterprise Application in each tenant. 

## SOURCE tenant: Preparation:
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
Then perfom an administrator consent for permissions with the following script (or do it interactively via the portal):-

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

```
Then via the portal - create a secret AND an oidc federation (Federated Credentials) for the application registration (as per below)
```text
repo:webstean/eire:ref:refs/heads/main
```
Provide the client_id (application_id), tenant_id, secret and confirm the oidc federation to EIRE.

On the assumption, that Access Permissions have been enabled, the Mail.Send permission won't work. To resolve this, the application must be explicity authorised to send emails to anyone in the organisation with the following:

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

## DESTINATION tenant: Preparation:

Create a migration endpoint (authorised to talk to the source) and then establish an organisation relationship from the destination to the source tenant.

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

Write-Host "Interactively connect to Exchange Online..." -ForegroundColor Cyan
Connect-ExchangeOnline -ShowBanner:$false
Write-Host "Connected to Exchange Online." -ForegroundColor Green

$AppId = "[Guid copied from the source migrations app -created as per above ($app.AppId))]"
$name = "xxx-migration"
$remote = "<source-tenant>.onmicrosoft.com" ## must be a domain name
$secret = "[secret from the source migration app -created as per above]"
## Enable customization if tenant is dehydrated
$dehydrated = Get-OrganizationConfig | select isdehydrated
if ($dehydrated.isdehydrated -eq $true) {Enable-OrganizationCustomization}
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId, (ConvertTo-SecureString -String $secret -AsPlainText -Force)

## Add migration endpoint (part of ExchangeOnlineManagement module)
New-MigrationEndpoint -RemoteServer outlook.office.com -RemoteTenant $remote -Credentials $Credential -ExchangeRemoteMove:$true -Name $name -ApplicationId $AppId

$sourceTenantId = "[tenant ID of your trusted partner, where the source mailboxes are]"
$orgrelname = "[name of your new organization relationship]"
$orgrels = Get-OrganizationRelationship
$existingOrgRel = $orgrels | ?{$_.DomainNames -like $sourceTenantId}
If ($null -ne $existingOrgRel)
{
    ## Enusre relationship is enabled (part of ExchangeOnlineManagement module)
    Set-OrganizationRelationship $existingOrgRel.Name -Enabled:$true -MailboxMoveEnabled:$true -MailboxMoveCapability Inbound
}
If ($null -eq $existingOrgRel)
{
    ## Add relationship and make it enabled (part of ExchangeOnlineManagement module)
    New-OrganizationRelationship $orgrelname -Enabled:$true -MailboxMoveEnabled:$true -MailboxMoveCapability Inbound -DomainNames $sourceTenantId
}
```

## Overview

The migration will be schedule and cordinated via PowerShell scripts.<br>
Specifically, the following two cmdlets<br>
- [New-MigrationBatch](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/start-migrationbatch)
- [Complete-MigrationBatch](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/complete-migrationbatch)

This requires has dependency of an authorised organisational relationship be setup between the two tenants (as per above):

Mailbox mapping (CSV)
```csv
SourceMailbox,TargetMailbox
user1@source.com,user1@target.com
```

Typically a script will be used to create the mailbox from the CSV file.
> ℹ️ **Information**
> A mailbox can only be created if the corresponding licensed user account already exists, as Exchange mailboxes are a licensed feature and won't be created unless the user/service principal is attached to an appropriate licese.

```powershell
## Assumed, already loggged on with ExchangeOnline cmdlet

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$csvPath = '.\mailboxes.csv'

$mailboxes = Import-Csv -LiteralPath $csvPath

foreach ($row in $mailboxes) {

    $sourceMailbox = $row.SourceMailbox
    $targetMailbox = $row.TargetMailbox

    Write-Host "Checking target mailbox: $targetMailbox" -ForegroundColor Cyan

    $existingMailbox = Get-EXOMailbox `
        -Identity $targetMailbox `
        -ErrorAction SilentlyContinue

    if ($existingMailbox) {
        Write-Host "Mailbox already exists: $targetMailbox" -ForegroundColor Green
        continue
    }

    Write-Host "Mailbox does not exist. Creating: $targetMailbox" -ForegroundColor Yellow

    New-Mailbox `
        -Name $targetMailbox `
        -Alias ($targetMailbox.Split('@')[0]) `
        -PrimarySmtpAddress $targetMailbox

    Write-Host "Created mailbox: $targetMailbox" -ForegroundColor Green
}
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


