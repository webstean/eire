# Mailbox Migration Tenant to Tenant (Draft for POC)
# DESTINATION tenant setup

## Introduction

This document describes (in detail) how the mailbox migration will be setup and performed.<br>

It is expected, the EIRE user principals (humans) will have atleast the 'Global Reader' Entra ID roles in both the source and destination tenants.<br>
Since these account are readonly, higher prvileges are required to actually perform the migrations.<br>
Our prefer approach is to use service principals (not user principal) to provide this higher level of access.<br>
We provide the following scripts to create these service principal, knowns inside Entra ID as 'app registrations' & 'enterprise applications'.

> ℹ️ **Requirement**
> All logons (User & Service Principals) must be able to satisfy the respective tenant's Conditional Access Policies.
>

The following setup scripts below are intended to be run interactively and will required certain authentication consents to already be enabled or being enabled during execution.<br>

## Permissions

The following are the required permission in the destination tenant to support the migration:

**API: Office 365 Exchange Online**<br>
| Permission | Type | Justification
|---|---|:---|
| Mailbox.Migration | Application | Migrate mailboxes
| Exchange.ManageAsApp | Application | Access Exchange as an application
| Organization.Read.All | Application | Read (but not change) Exchange settings
| PeopleSettings.Read.All | Application | Read (but not change) Exchage user settings 
| SMTP.SendAsApp | Application | Send email on behalf of app for reporting (cannot read emails)
| MailboxSettings.ReadWrite | Application | Create mailboxes 
| Mailbox Import Export | Application | Ability to import and export mailboxes (so PSTs can be imported)
| Mail Recipients | Application | Ability to managed mail recipents (so PSTs can be imported)




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

This needs to be <u>multi-tenant</u> Application Registration / Enterprise Application in the destination tenant.
with a suitable certificate/secret and ideally an OIDC federation subject identifier for a suitable Git respository.

## **Step 1:** Create App Registration / Enterprise Application
Create the migration application registration and enterprise application with the following PowerShell:
```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

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
    'Exchange.ManageAsApp',
    'Mailbox Import Export',
    'Mail Recipients'

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
## Step 2: **Perform Administrator Consent**
Now the correct permissions are assigned, perform an administrator consense for those permissions with the following PowwerShell script.
This should be executed by the tenant's, Global Administrator.
```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

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
You can inspect the result in the portal:-
<img width="1142" height="819" alt="image" src="https://github.com/user-attachments/assets/dac865f5-1b82-4c93-bde6-9c289977e458" />


Then via the portal - create a secret AND an oidc federation (Federated Credentials) for the application registration (as per below)<br>

```text
Scenario: GitHub Action
Subject Identifier: repo:webstean/eire:ref:refs/heads/main (or any other)
```
<img width="1421" height="610" alt="image" src="https://github.com/user-attachments/assets/43526dfa-11f4-4df1-8489-f68d2e26bb86" />
<img width="878" height="729" alt="image" src="https://github.com/user-attachments/assets/7c8f673c-44c1-45c8-bcdd-3e164b16fecc" />
<img width="1340" height="590" alt="image" src="https://github.com/user-attachments/assets/b63e1c64-42ba-4e55-b3c2-df16b9172197" />

**Provide** the client_id (application_id), tenant_id and secret plus confirm the oidc federation to EIRE (mailto:Andrew.Webster@eire.com)
<img width="1409" height="293" alt="image" src="https://github.com/user-attachments/assets/9a8dde79-6019-483b-81b8-024f8ca895de" />

On the assumption, that Access Permissions have been enabled, the Mail.Send permission won't work. To resolve this, the application must be explicity authorised to send emails to anyone in the organisation with the following:

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

$scopeName = 'Migration-Notification'
$filter = "Alias -like '*migration*'" ## change to the relevant mailbox

$scope = Get-ManagementScope `
    -Identity $scopeName `
    -ErrorAction SilentlyContinue

if ($null -eq $scope) {
    Write-Host "Creating management scope: $scopeName"

    New-ManagementScope `
        -Name $scopeName `
        -RecipientRestrictionFilter $filter `
        -ErrorAction Stop | Out-Null
} else {
    Write-Host "Updating management scope: $scopeName"

    Set-ManagementScope `
        -Identity $scopeName `
        -RecipientRestrictionFilter $filter `
        -Confirm:$false `
        -ErrorAction Stop
}

$scope = Get-ManagementScope -Identity $scopeName -ErrorAction Stop

## Add role (part of ExchangeOnlineManagement module)
New-ManagementRoleAssignment `
    -Name "App-SMTP-SendAsApp-for-$($app.DisplayName)" `
    -Role "Application SMTP.SendAsApp" `
    -App "$($app.Id)" `
    -CustomResourceScope "$($scope.Name)"```
```

## Creation of Migration EndPoint
Create a migration endpoint (authorised to talk to the source) and then establish an organisation relationship from the destination to the source tenant.<br>

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

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

## Enable customization if tenant is dehydrated
$dehydrated = Get-OrganizationConfig | select isdehydrated
if ($dehydrated.isdehydrated -eq $true) {Enable-OrganizationCustomization}

## Create Credential - if using a client secret
$secret = "[secret from the source migration app -created as per above]"
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId, (ConvertTo-SecureString -String $secret -AsPlainText -Force)
Connect-ExchangeOnline -Credential $Credential

## Logon with Certificate (located in local key store)
$thumbprint = '[thumbprint of certifcate, in key store]'
## The tenant name should the intial, xxxx.onmicrosoft.com domain for certificate authentication to reliability work.
$TenantName = '[tenant name - destination tenant]'
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantName

## Logon with Certificate (certifcate as a local file)
$PfxPath      = "C:\Certs\exo-app-auth.pfx"
$PfxPassword  = ConvertTo-SecureString "<pfx-password>" -AsPlainText -Force
## The tenant name should the intial, xxxx.onmicrosoft.com domain for certificate authentication to reliability work.
$TenantName = '[tenant name - destination tenant]'
Connect-ExchangeOnline -AppId $AppId -Organization $Tenant -CertificateFilePath $PfxPath -CertificatePassword $PfxPassword

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
- [New-MigrationBatch (English) ](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/start-migrationbatch)
- [Complete-MigrationBatch (English) ](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/complete-migrationbatch)
- [New-MigrationBatch (Japanese) ](https://learn.microsoft.com/jp-JA/powershell/module/exchangepowershell/start-migrationbatch)
- [Complete-MigrationBatch (Japanese) ](https://learn.microsoft.com/jp-JA/powershell/module/exchangepowershell/complete-migrationbatch)

These cmdlets have a dependency that the organisational relationship be setup between the two tenants.

A test can be perform to esnure the mailbox endpoint is ready for migration
```powershell
## Source Tenant
## Assumed: already authenticated/authorised with Connect-ExchangeOnline cmdlet
$migration.MigrationEndpointName = ""
Test-MigrationServerAvailability -EndPoint '[migration endpoint name]' -TestMailbox '[Primary SMTP address of a MailUser in target tenant]'
```

A migration file will be automated generated via scripting, as per below:-

```powershell
## Source Tenant
## Assumed: already authenticated/authorised with Connect-ExchangeOnline cmdlet
Get-Mailbox -RecipientTypeDetails UserMailbox,SharedMailbox | Select-Object -ExpandProperty Alias | Export-Csv -Path '.\mailboxstomigrate.csv' -NoTypeInformation -Encoding UTF8
```
At this point, the '.\mailboxstomigrate.csv' can be modifed to include only the relevant users.
Alternatively, the '.\mailboxstomigrate.csv' can be generated from the known mailboxes to be migrated.

To gather a complete detailed information on each mailbox (highly recommended) for troublsheeting purposes. Execute the following:-
```powershell
## Source Tenant
## Assumed: already authenticated/authorised with Connect-ExchangeOnline cmdlet
$mailboxes = Import-Csv '.\mailboxstomigrate.csv'
$mailboxes | ForEach-Object { Get-Mailbox $_ } |
    Select-Object `
        PrimarySmtpAddress,
        Alias,
        SamAccountName,
        FirstName,
        LastName,
        DisplayName,
        Name,
        ExchangeGuid,
        ArchiveGuid,
        LegacyExchangeDn,
        EmailAddresses |
    Export-Csv `
        -Path '.\mailboxstomigrate-detailed.csv' `
        -NoTypeInformation `
        -Encoding UTF8
```
Transfer the file(s) from source tenant to destination tenant.

> ℹ️ **Dependency**
> The destination tenant must have the users provisioned (including the Exchange mailbox), as per the migrated users that are detalied above.
>

Once the mailboxe have bene created, a mapping CSV file will need to be created, detailing what mailbox from the source, needs to be migrated to destination and the fille will look this<br>
Simple Mailbox mapping (CSV)
```csv
SourceMailbox,TargetMailbox
user1@source.com,user1@target.com
```

> ℹ️ **Dependency**
> Both the source and destination tenants, should review the mapping file and explicitly confirm that it is correct.

Once the migration csv has been fully migrated, by all relevant parties. the mailbox migration can then commence.
Best practice is to batch the mailboxes into groups of no more than 200 mailboxes per batch for the best performance.

```powershell
## Destination Tenant
## Assumed: already authenticated/authorised with Connect-ExchangeOnline cmdlet
New-MigrationBatch `
  -Name "Batch1" `
  -SourceEndpoint "CrossTenantEndpoint" `
  -CSVData ([System.IO.File]::ReadAllBytes("users.csv")) `
  -AutoStart $true `
  -AutoComplete $false
```
> ℹ️ **Note**
> The AutoComplete is set to false, so the migration continues indefinately (delta), until it is explciily authorised to be completed.

At the appointed time the migration is set to "complete" which deletes the mailbox from the source tenants and fully enables it in the destination.

```powershell
## Destination Tenant
## Assumed: already authenticated/authorised with Connect-ExchangeOnline cmdlet
Complete-MigrationBatch -Identity "Batch1"
```

## Throughput

Theortical maximum is 10TB per day (as per Microsoft documentation), 2-5TB is typical.

A Pilot/POC should be utilised to determine the exact throughput available between the two tenants, based upon their geography and applicable network links.

# Monitoring

Get-MigrationUserStatistics https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-migrationuserstatistics?view=exchange-ps<br>
This commandlet can be run during or at the conclusion of the migration.

```powershell
## Part of ExchangeOnlineManagement module
## Assumed, already loggged on with ExchangeOnline cmdlet
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


