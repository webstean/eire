#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$tenantId = $env:AZURE_TENANT_ID,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path -Path $PWD -ChildPath ("m365-tenant-snapshot-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphClientId = '1950a258-227b-4e31-a9cf-717495945fc2',  # <-- default for PowerShell CLI tools

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphCertificateThumbprint,

    [Parameter()]
    [switch]$UseAppOnlyGraph,

    [Parameter()]
    [switch]$SkipGraph,

    [Parameter()]
    [switch]$SkipExchange,

    [Parameter()]
    [switch]$SkipTeams,

    [Parameter()]
    [switch]$SkipSharePoint,

    [Parameter()]
    [switch]$DisconnectOnExit ## By Default, don't disconnect on exit, to allow users to inspect and run additional commands if desired against the connected sessions after the main collection is complete. Use this switch to have the script disconnect from all services on exit, which will also clear any cached credentials in the current session for Graph and Exchange modules.
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

function New-OutputFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }

    foreach ($child in @('graph', 'exchange', 'teams', 'sharepoint', 'meta')) {
        $full = Join-Path $Path $child
        if (-not (Test-Path -LiteralPath $full)) {
            $null = New-Item -ItemType Directory -Path $full -Force
        }
    }
}

function Write-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Depth = 100
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    $objectToWrite = $InputObject

    if ($null -eq $InputObject) {
        $objectToWrite = 'No data returned.'
    }
    elseif (
        $InputObject -is [System.Collections.IEnumerable] -and
        -not ($InputObject -is [string]) -and
        -not ($InputObject -is [hashtable])
    ) {
        $testArray = @($InputObject)
        if ($testArray.Count -eq 0) {
            $objectToWrite = 'No data returned.'
        }
    }

    $json = $objectToWrite | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}
function Add-ResultRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$List,

        [Parameter(Mandatory)]
        [string]$Area,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter()]
        [string]$Details = ''
    )

    $List.Add([pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            Area      = $Area
            Name      = $Name
            Status    = $Status
            Details   = $Details
        })
}

function Invoke-CollectorStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Area,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Manifest,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Errors
    )

    try {
        & $ScriptBlock
        Add-ResultRecord -List $Manifest -Area $Area -Name $Name -Status 'Success'
    }
    catch {
        $message = $_.Exception.Message
        Add-ResultRecord -List $Manifest -Area $Area -Name $Name -Status 'Failed' -Details $message
        Add-ResultRecord -List $Errors   -Area $Area -Name $Name -Status 'Error'  -Details $message
    }
}

function Get-AllMsGraphPages {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Uri = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies',

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetries = 3,

        [Parameter()]
        [switch]$OutputJson,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$JsonDepth = 100
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Write-GraphJsonLog {
        param(
            [string]$Uri,
            [string]$Json
        )

        $isGitHubRunner = -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)

        if ($isGitHubRunner) {
            Write-Verbose "GitHub runner detected. Writing JSON output to GITHUB_STEP_SUMMARY."

            if ($Json.Length -gt 20000) {
                $Json = $Json.Substring(0, 20000) + "`n...truncated..."
            }

            $content = @(
                "### Graph response page from $Uri"
                '```json'
                $Json
                '```'
                ''
            ) -join "`n"

            Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $content
        }
        else {
            Write-Verbose "Graph response page from $Uri (size: $($Json.Length) chars)"
            #Write-Host $Json
        }
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri

    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $attempt = 0
        $response = $null

        do {
            try {
                $attempt++
                Write-Verbose "Fetching URI: $next"
                $response = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
                break
            }
            catch {
                if ($attempt -ge $MaxRetries) { throw }

                Write-Warning "Request failed for URI '$next' on attempt $attempt of $MaxRetries. Retrying..."
                Start-Sleep -Seconds ([Math]::Min(2 * $attempt, 10))
            }
        } while ($attempt -lt $MaxRetries)

        if ($null -eq $response) {
            Write-Verbose "Received null response for URI: $next"
            break
        }

        # Optional per-page debug logging only
        if ($OutputJson) {
            $pageJson = $response | ConvertTo-Json -Depth $JsonDepth
            Write-GraphJsonLog -Uri $next -Json $pageJson
        }

        $valueProperty = $response.PSObject.Properties['value']
        $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']

        if ($null -ne $valueProperty) {
            foreach ($item in @($valueProperty.Value)) {
                $items.Add($item) | Out-Null
            }

            $next = if ($null -ne $nextLinkProperty) {
                [string]$nextLinkProperty.Value
            }
            else {
                $null
            }

            continue
        }

        if ($response -is [array]) {
            foreach ($item in $response) {
                $items.Add($item) | Out-Null
            }
            break
        }

        $items.Add($response) | Out-Null
        break
    }

    Write-Verbose "Total items retrieved: $($items.Count)"

    # FINAL OUTPUT DECISION
    if ($OutputJson) {
        Write-Verbose "Returning aggregated JSON output."
        return ($items | ConvertTo-Json -Depth $JsonDepth)
    }
    else {
        return $items
    }
}

function ConvertTo-SafeFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name,

        [Parameter()]
        [string]$DefaultName = 'unnamed'
    )

    $safe = $Name -replace '[^\p{L}\p{Nd}\-_\. ]', ''
    $safe = $safe -replace '\s+', ' '
    $safe = $safe.Trim()
    $safe = $safe -replace ' ', '_'

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return $DefaultName
    }

    return $safe
}

# ---------------------------------------------------------------------------
# Module checks
# ---------------------------------------------------------------------------

function Confirm-ModulesAvailable {
    [CmdletBinding()]
    param()

    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Identity.DirectoryManagement',
        'ExchangeOnlineManagement',
        'MicrosoftTeams',
        'Microsoft.Online.SharePoint.PowerShell'
    )

    foreach ($moduleName in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            throw "Required module '$moduleName' is not installed. Please install it and try again."
            return $false
        }
    }
    return $true
}

function Assert-ModuleAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Module -Name $Name)) {
        if (Get-Module -ListAvailable -Name $Name) {
            $PSDefaultParameterValues['*:Verbose'] = $false
            Import-Module -Name $Name
        }
        else {
            throw "Required module '$Name' is not installed."
        }
    }
}

# ---------------------------------------------------------------------------
# Connections
# ---------------------------------------------------------------------------

function Connect-GraphTenant {
    [CmdletBinding()]
    param()

    Assert-ModuleAvailable -Name Microsoft.Graph.Authentication

    try {
        if ($UseAppOnlyGraph) {
            if ([string]::IsNullOrWhiteSpace($tenantId)) {
                throw 'tenantId is required when -UseAppOnlyGraph is specified.'
            }
            if ([string]::IsNullOrWhiteSpace($GraphClientId)) {
                throw 'GraphClientId is required when -UseAppOnlyGraph is specified.'
            }
            if ([string]::IsNullOrWhiteSpace($GraphCertificateThumbprint)) {
                throw 'GraphCertificateThumbprint is required when -UseAppOnlyGraph is specified.'
            }

            Connect-MgGraph `
                -tenantId $tenantId `
                -ClientId $GraphClientId `
                -CertificateThumbprint $GraphCertificateThumbprint `
                -NoWelcome
        }
        else {
            Connect-MgGraph `
                -Scopes @(
                'Organization.Read.All',
                'Directory.Read.All',
                'Domain.Read.All',
                'Policy.Read.All',
                'User.Read.All',
                'Group.Read.All',
                'Application.Read.All',
                'RoleManagement.Read.Directory',
                'AuditLog.Read.All'
            ) `
                -NoWelcome
        }
    }
    catch {
        throw ("Failed to connect to Microsoft Graph. Please check credentials and permissions. Error: {0}" -f $_.Exception.Message)
    }
}

function Connect-ExchangeTenant {
    [CmdletBinding()]
    param()

    Assert-ModuleAvailable -Name ExchangeOnlineManagement
    try {
        Write-Host "Attempting to connect to Exchange Online..."
        Connect-ExchangeOnline -ShowBanner:$true
        Write-Host "Successfully connected to Exchange Online."
    }
    catch {
        throw ("Failed to connect to Exchange Online. Please check credentials and permissions. Error: {0}" -f $_.Exception.Message)
    }
}

function Connect-TeamsTenant {
    [CmdletBinding()]
    param()

    Assert-ModuleAvailable -Name MicrosoftTeams
    try {
        Write-Host "Attempting to connect to Microsoft Teams..."
        Connect-MicrosoftTeams | Out-Null
        Write-Host "Successfully connected to Microsoft Teams."
    }
    catch {
        throw ("Failed to connect to Microsoft Teams. Please check credentials and permissions. Error: {0}" -f $_.Exception.Message)
    }
}

function Connect-SharePointTenant {
    [CmdletBinding()]
    param()

    Assert-ModuleAvailable -Name Microsoft.Online.SharePoint.PowerShell

    try {
        if ([string]::IsNullOrWhiteSpace($tenantId)) {
            throw 'tenantId is required to derive the SharePoint admin URL reliably.'
        }

        $org = Get-MgOrganization
        $verifiedDomains = @($org.VerifiedDomains)
        $defaultDomain = @($verifiedDomains | Where-Object { $_.IsInitial -eq $true } | Select-Object -First 1).Name

        if ([string]::IsNullOrWhiteSpace($defaultDomain)) {
            throw 'Could not determine default domain from Graph organization object.'
        }

        $tenantPrefix = $defaultDomain.Split('.')[0]
        $adminUrl = "https://{0}-admin.sharepoint.com" -f $tenantPrefix

        Write-Host "Attempting to connect to SharePoint Online ${adminUrl}..."
        Connect-SPOService -Url $adminUrl -UseSystemBrowser $true
        Write-Host "Successfully connected to SharePoint Online ${adminUrl}."
    }
    catch {
        throw ("Failed to connect to SharePoint Online. Please check credentials and permissions. Error: {0}" -f $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# Graph collectors
# ---------------------------------------------------------------------------

function Export-GraphCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    Write-Host "Exporting Organization Information...."
    Write-JsonFile -Path (Join-Path $BasePath 'core\organization.json') `
        -InputObject (Get-MgOrganization)

    Write-Host "Exporting Domain Information...."
    Write-JsonFile -Path (Join-Path $BasePath 'core\domains.json') `
        -InputObject (Get-MgDomain -All)

    Write-Host "Exporting Subscribed SKUs...."
    Write-JsonFile -Path (Join-Path $BasePath 'core\subscribedSkus.json') `
        -InputObject (Get-MgSubscribedSku -All)

    Write-Host "Exporting Directory Roles...."
    Write-JsonFile -Path (Join-Path $BasePath 'core\directoryRoles.json') `
        -InputObject (Get-MgDirectoryRole)

    Write-Host "Exporting Any Administrative Units...."
    Write-JsonFile -Path (Join-Path $BasePath 'core\administrativeUnits.json') `
        -InputObject (Get-MgDirectoryAdministrativeUnit -All)

#    Write-Host "Exporting Users...."
#    Write-JsonFile -Path (Join-Path $BasePath 'core\users.json') `
#        -InputObject (Get-MgUser -All -Property "id,displayName,userPrincipalName,accountEnabled,userType,assignedLicenses,onPremisesSyncEnabled,createdDateTime")

#    Write-Host "Exporting Groups...."
#    Write-JsonFile -Path (Join-Path $BasePath 'core\groups.json') `
#        -InputObject (Get-MgGroup -All -Property "id,displayName,mail,mailEnabled,securityEnabled,groupTypes,membershipRule,membershipRuleProcessingState,createdDateTime")

    Write-Host "Exporting Applications...."
    Write-JsonFile -Path (Join-Path $BasePath 'core\applications.json') `
        -InputObject (Get-MgApplication -All)

    Write-Host "Exporting Service Principals...."
    Write-JsonFile -Path (Join-Path $BasePath 'core\servicePrincipals.json') `
        -InputObject (Get-MgServicePrincipal -All)
}

function Export-GraphPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $policyRoot = 'https://graph.microsoft.com/v1.0'
    Write-Host "policyRoot is $policyRoot"

    Write-Host "Exporting Conditional Access Policies...."
    Write-JsonFile -Path (Join-Path $BasePath 'policies\conditionalAccessPolicies.json') `
        -InputObject (Invoke-MgGraphRequest -Method GET -Uri "$policyRoot/identity/conditionalAccess/policies")

    Write-Host "Exporting Named Locations...."
    Write-JsonFile -Path (Join-Path $BasePath 'policies\namedLocations.json') `
        -InputObject (Invoke-MgGraphRequest -Method GET -Uri "$policyRoot/identity/conditionalAccess/namedLocations")

    Write-Host "Exporting Authentication Strength Policies...."
    Write-JsonFile -Path (Join-Path $BasePath 'policies\authenticationStrengthPolicies.json') `
        -InputObject (Invoke-MgGraphRequest -Method GET -Uri "$policyRoot/policies/authenticationStrengthPolicies")

    Write-Host "Exporting Authorization Policy...."
    Write-JsonFile -Path (Join-Path $BasePath 'policies\authorizationPolicy.json') `
        -InputObject (Invoke-MgGraphRequest -Method GET -Uri "$policyRoot/policies/authorizationPolicy")

    Write-Host "Exporting Identity Security Defaults Enforcement Policy...."
    Write-JsonFile -Path (Join-Path $BasePath 'policies\identitySecurityDefaultsEnforcementPolicy.json') `
        -InputObject (Invoke-MgGraphRequest -Method GET -Uri "$policyRoot/policies/identitySecurityDefaultsEnforcementPolicy")

    Write-JsonFile -Path (Join-Path $BasePath 'policies\authenticationMethodsPolicy.json') `
        -InputObject (Invoke-MgGraphRequest -Method GET -Uri "$policyRoot/policies/authenticationMethodsPolicy")

    Write-Host "Exporting Role Management Directory Role Definitions...."
    Write-JsonFile -Path (Join-Path $BasePath 'roles\roleManagementDirectoryRoleDefinitions.json') `
        -InputObject (Get-AllMsGraphPages -Uri "$policyRoot/roleManagement/directory/roleDefinitions")

    Write-JsonFile -Path (Join-Path $BasePath 'roles\roleManagementDirectoryRoleAssignments.json') `
        -InputObject (Get-AllMsGraphPages -Uri "$policyRoot/roleManagement/directory/roleAssignments")
}

function Export-GraphReportsMeta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $policyRoot = 'https://graph.microsoft.com/v1.0'

    Write-JsonFile -Path (Join-Path $BasePath 'graph\organizationSettings-summary.json') `
        -InputObject ([pscustomobject]@{
            CollectedAt  = (Get-Date).ToString('o')
            Notes        = @(
                'Graph usage reports are intentionally not fully expanded here.'
                'Add targeted report collectors if you need mailbox, Teams, OneDrive, or SharePoint usage exports.'
            )
            Organization = (Invoke-MgGraphRequest -Method GET -Uri "$policyRoot/organization")
        })
}

# ---------------------------------------------------------------------------
# Exchange collectors
# ---------------------------------------------------------------------------

function Export-ExchangeTenant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    Write-JsonFile -Path (Join-Path $BasePath 'exchange\organizationConfig.json') `
        -InputObject (Get-OrganizationConfig)

    Write-JsonFile -Path (Join-Path $BasePath 'exchange\acceptedDomains.json') `
        -InputObject (Get-AcceptedDomain)

    Write-JsonFile -Path (Join-Path $BasePath 'exchange\remoteDomains.json') `
        -InputObject (Get-RemoteDomain)

    Write-JsonFile -Path (Join-Path $BasePath 'exchange\transportConfig.json') `
        -InputObject (Get-TransportConfig)

    Write-JsonFile -Path (Join-Path $BasePath 'exchange\mailboxPlans.json') `
        -InputObject (Get-MailboxPlan)

    Write-JsonFile -Path (Join-Path $BasePath 'exchange\retentionPolicies.json') `
        -InputObject (Get-RetentionPolicy)

    Write-JsonFile -Path (Join-Path $BasePath 'exchange\sharingPolicies.json') `
        -InputObject (Get-SharingPolicy)

    Write-JsonFile -Path (Join-Path $BasePath 'exchange\owaMailboxPolicies.json') `
        -InputObject (Get-OwaMailboxPolicy)

    Write-JsonFile -Path (Join-Path $BasePath 'exchange\organizationRelationship.json') `
        -InputObject (Get-OrganizationRelationship)
}

# ---------------------------------------------------------------------------
# Teams collectors
# ---------------------------------------------------------------------------

function Export-TeamsTenant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    Write-JsonFile -Path (Join-Path $BasePath 'teams\tenant.json') `
        -InputObject (Get-CsTenant)

    Write-JsonFile -Path (Join-Path $BasePath 'teams\tenantFederationConfiguration.json') `
        -InputObject (Get-CsTenantFederationConfiguration)

    Write-JsonFile -Path (Join-Path $BasePath 'teams\tenantLicensingConfiguration.json') `
        -InputObject (Get-CsTenantLicensingConfiguration)

    try {
        Write-JsonFile -Path (Join-Path $BasePath 'teams\multiTenantOrganizationConfiguration.json') `
            -InputObject (Get-CsTeamsMultiTenantOrganizationConfiguration)
    }
    catch {
        Write-Warning ("Skipping Get-CsTeamsMultiTenantOrganizationConfiguration: {0}" -f $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# SharePoint collectors
# ---------------------------------------------------------------------------

function Export-SharePointTenant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    Write-JsonFile -Path (Join-Path $BasePath 'sharepoint\tenant.json') `
        -InputObject (Get-SPOTenant)

    Write-JsonFile -Path (Join-Path $BasePath 'sharepoint\sites-summary.json') `
        -InputObject (Get-SPOSite -Limit All | Select-Object Url, Title, Template, Owner, StorageUsageCurrent, LockState, SharingCapability)

    Write-JsonFile -Path (Join-Path $BasePath 'sharepoint\cdn.json') `
        -InputObject (Get-SPOTenantCdnPolicies -Type Public)
}

function New-ZipFileFromFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )

    $parent = Split-Path -Path $FolderPath -Parent
    $leaf = Split-Path -Path $FolderPath -Leaf
    $zipPath = Join-Path -Path $parent -ChildPath "$leaf.zip"

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Compress-Archive -Path "$FolderPath\*" -DestinationPath $zipPath -Force

    return $zipPath
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

## Turn off verbose
$preserve = $PSDefaultParameterValues['*:Verbose']
$PSDefaultParameterValues['*:Verbose'] = $false

Confirm-ModulesAvailable

$manifest = [System.Collections.Generic.List[object]]::new()
$errors = [System.Collections.Generic.List[object]]::new()

if ([string]::IsNullOrWhiteSpace($tenantId)) {
    throw "tenantId is not defined or empty - cannot execute"
}

[guid]$parsed = [guid]::Empty
if (-not [guid]::TryParse($tenantId, [ref]$parsed)) {
    throw "tenantId is not a valid GUID: $tenantId"
}

# Connect to Graph to get tenant name for output path
Write-Host "Connecting to Graph Tenant..."
Connect-GraphTenant
$tenantName = (Get-MgOrganization).DisplayName
Write-Host ("Connected to Graph Tenant: {0}" -f $tenantName)

$safeTenantName = $tenantName -replace '[^\w\s-]', '' -replace '\s+', '-'
$OutputPath = Join-Path -Path $PWD -ChildPath ("m365-tenant-snapshot-{0}-{1}" -f $safeTenantName, (Get-Date -Format 'yyyyMMdd-HHmmss'))

New-OutputFolder -Path $OutputPath

Write-Host ("Output path: {0}" -f $OutputPath)

Write-JsonFile -Path (Join-Path $OutputPath 'meta\run.json') -InputObject @{
    StartedAt    = (Get-Date).ToString('o')
    ComputerName = $env:COMPUTERNAME
    PowerShell   = $PSVersionTable.PSVersion.ToString()
    Parameters   = @{
        TenantName      = $tenantName
        tenantId        = $tenantId
        UseAppOnlyGraph = [bool]$UseAppOnlyGraph
        SkipGraph       = [bool]$SkipGraph
        SkipExchange    = [bool]$SkipExchange
        SkipTeams       = [bool]$SkipTeams
        SkipSharePoint  = [bool]$SkipSharePoint
    }
}

try {
    if (-not $SkipGraph) {
        Invoke-CollectorStep -Area 'Graph' -Name 'Core' -Manifest $manifest -Errors $errors -ScriptBlock {
            Export-GraphCore -BasePath $OutputPath
        }

        Invoke-CollectorStep -Area 'Graph' -Name 'Policies' -Manifest $manifest -Errors $errors -ScriptBlock {
            Export-GraphPolicies -BasePath $OutputPath
        }

        Invoke-CollectorStep -Area 'Graph' -Name 'ReportsMeta' -Manifest $manifest -Errors $errors -ScriptBlock {
            Export-GraphReportsMeta -BasePath $OutputPath
        }
    }

    if (-not $SkipExchange) {
        Invoke-CollectorStep -Area 'Exchange' -Name 'Connect' -Manifest $manifest -Errors $errors -ScriptBlock {
            Connect-ExchangeTenant
        }

        Invoke-CollectorStep -Area 'Exchange' -Name 'TenantConfig' -Manifest $manifest -Errors $errors -ScriptBlock {
            Export-ExchangeTenant -BasePath $OutputPath
        }
    }

    if (-not $SkipTeams) {
        Invoke-CollectorStep -Area 'Teams' -Name 'Connect' -Manifest $manifest -Errors $errors -ScriptBlock {
            Connect-TeamsTenant
        }

        Invoke-CollectorStep -Area 'Teams' -Name 'TenantConfig' -Manifest $manifest -Errors $errors -ScriptBlock {
            Export-TeamsTenant -BasePath $OutputPath
        }
    }

    if (-not $SkipSharePoint) {
        if ($SkipGraph) {
            throw 'SharePoint collection in this script depends on Graph being connected first so it can derive the default tenant domain.'
        }

        Invoke-CollectorStep -Area 'SharePoint' -Name 'Connect' -Manifest $manifest -Errors $errors -ScriptBlock {
            Connect-SharePointTenant
        }

        Invoke-CollectorStep -Area 'SharePoint' -Name 'TenantConfig' -Manifest $manifest -Errors $errors -ScriptBlock {
            Export-SharePointTenant -BasePath $OutputPath
        }
    }
}
finally {
    if ($DisconnectOnExit) {
        Write-Host 'Disconnecting from Microsoft API Endpoints...'
        try { Disconnect-MgGraph | Out-Null } catch {}
        try { Disconnect-ExchangeOnline -Confirm:$true } catch {}
        try { Disconnect-MicrosoftTeams } catch {}
    }
    $PSDefaultParameterValues['*:Verbose'] = $preserve
}

Write-JsonFile -Path (Join-Path $OutputPath 'meta\manifest.json') -InputObject $manifest
Write-JsonFile -Path (Join-Path $OutputPath 'meta\errors.json')   -InputObject $errors

Write-Host 'Completed.'
Write-Host ('Manifest : {0}' -f (Join-Path $OutputPath 'meta\manifest.json'))
Write-Host ('Errors   : {0}' -f (Join-Path $OutputPath 'meta\errors.json'))

try {
    $zipFile = New-ZipFileFromFolder -FolderPath $OutputPath
    Write-Host ('Archive  : {0}' -f $zipFile)
    Write-Host -ForegroundColor Green ('Please email the above ZIP file to andrew.webster@eiresystems.com for analysis.')
}
catch {
    Write-Warning ("Failed to create ZIP archive: {0}" -f $_.Exception.Message)
}
