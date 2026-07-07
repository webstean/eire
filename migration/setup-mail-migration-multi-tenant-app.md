Setup the minimial permissions for just mailbox migration.

The is a miulti-tenant app, that is defined on the destination tenant and then consented to by the source tenant.

- In the destination teannt: A Multi-Teant App, consisting of a Application Registration and Service Principal
- In the source tenant: A Multi-Teant App, represented as a single Service Principal
- Web Redirect URI of 'https://office.com'
- The following permisisons are required (applicable to both source and destination)

| API | Permission | Type | Purpose
|---|---|:---|:---|
| Exchange Online | Mailbox.Migration | Application | Migrate mailboxes
| Exchange Online | Exchange.ManageAsApp | Application | Logon as an app to Exchange (see)[link]
| Microsoft Graph | User.Read.All | Application | Read user account details, to confirm details are correct and provide reporting
| Microsoft Graph | Application.Read.All | Application | Read application objects to configuration is vlaid to continue to the migration

A script to create this is given below, and needs to be run on the destination teant.

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
Write-Host "  App ID       : $($sp.AppId)"
Write-Host "  Object ID    : $($sp.Id)"
Write-Host ""

```
