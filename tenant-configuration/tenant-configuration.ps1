#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

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
    [switch]$SkipSharePoint
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

    foreach ($child in @('graph','exchange','teams','sharepoint','meta')) {
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
        [string]$Path,

        [Parameter(Mandatory)]
        $InputObject,

        [Parameter()]
        [int]$Depth = 100
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    $json = $InputObject | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Write-TextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Content
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Add-ResultRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
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
        [System.Collections.Generic.List[object]]$Manifest,

        [Parameter(Mandatory)]
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

function Get-AllPages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $items = New-Object System.Collections.Generic.List[object]
    $next = $Uri

    while ($next) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        if ($null -ne $response.value) {
            foreach ($item in $response.value) {
                $items.Add($item)
            }
        }
        elseif ($null -ne $response) {
            $items.Add($response)
            $next = $null
            continue
        }

        $next = $response.'@odata.nextLink'
    }

    return $items
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

function Export-GraphObjectSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$RootFolderName,

        [Parameter(Mandatory)]
        [string]$CollectionFileName,

        [Parameter(Mandatory)]
        [string]$IndexFileName,

        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Items,

        [Parameter(Mandatory)]
        [scriptblock]$NameScriptBlock,

        [Parameter()]
        [scriptblock]$IndexProjectionScriptBlock
    )

    $folder = Join-Path $BasePath ("graph\{0}" -f $RootFolderName)
    if (-not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -ItemType Directory -Path $folder -Force
    }

    $itemArray = @($Items)

    Write-JsonFile -Path (Join-Path $BasePath ("graph\{0}" -f $CollectionFileName)) -InputObject $itemArray

    $index = foreach ($item in $itemArray) {
        $resolvedName = [string](& $NameScriptBlock $item)
        $safeName = ConvertTo-SafeFileName -Name $resolvedName -DefaultName $RootFolderName

        if ($IndexProjectionScriptBlock) {
            & $IndexProjectionScriptBlock $item $safeName
        }
        else {
            [pscustomobject]@{
                id       = $item.id
                name     = $resolvedName
                fileName = if ($item.id) { '{0}-{1}.json' -f $safeName, $item.id } else { '{0}.json' -f $safeName }
            }
        }
    }

    Write-JsonFile -Path (Join-Path $BasePath ("graph\{0}" -f $IndexFileName)) -InputObject $index

    foreach ($item in $itemArray) {
        $resolvedName = [string](& $NameScriptBlock $item)
        $safeName = ConvertTo-SafeFileName -Name $resolvedName -DefaultName $RootFolderName

        $fileName = if ($item.id) {
            '{0}-{1}.json' -f $safeName, $item.id
        }
        else {
            '{0}.json' -f $safeName
        }

        Write-JsonFile -Path (Join-Path $folder $fileName) -InputObject $item
    }
}

# ---------------------------------------------------------------------------
# Module checks
# ---------------------------------------------------------------------------

function Assert-ModuleAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        throw "Required module '$Name' is not installed."
    }
}

# ---------------------------------------------------------------------------
# Connections
# ---------------------------------------------------------------------------

function Connect-GraphTenant {
    [CmdletBinding()]
    param()

    Assert-ModuleAvailable -Name Microsoft.Graph.Authentication

    if ($UseAppOnlyGraph) {
        if ([string]::IsNullOrWhiteSpace($TenantId)) {
            throw 'TenantId is required when -UseAppOnlyGraph is specified.'
        }
        if ([string]::IsNullOrWhiteSpace($GraphClientId)) {
            throw 'GraphClientId is required when -UseAppOnlyGraph is specified.'
        }
        if ([string]::IsNullOrWhiteSpace($GraphCertificateThumbprint)) {
            throw 'GraphCertificateThumbprint is required when -UseAppOnlyGraph is specified.'
        }

        Connect-MgGraph `
            -TenantId $TenantId `
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

function Connect-ExchangeTenant {
    [CmdletBinding()]
    param()

    Assert-ModuleAvailable -Name ExchangeOnlineManagement
    Connect-ExchangeOnline -ShowBanner:$false
}

function Connect-TeamsTenant {
    [CmdletBinding()]
    param()

    Assert-ModuleAvailable -Name MicrosoftTeams
    Connect-MicrosoftTeams | Out-Null
}

function Connect-SharePointTenant {
    [CmdletBinding()]
    param()

    Assert-ModuleAvailable -Name Microsoft.Online.SharePoint.PowerShell

    if ([string]::IsNullOrWhiteSpace($TenantId)) {
        throw 'TenantId is required to derive the SharePoint admin URL reliably.'
    }

    $org = Get-MgOrganization
    $verifiedDomains = @($org.VerifiedDomains)
    $defaultDomain = @($verifiedDomains | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1).Name

    if ([string]::IsNullOrWhiteSpace($defaultDomain)) {
        throw 'Could not determine default domain from Graph organization object.'
    }

    $tenantPrefix = $defaultDomain.Split('.')[0]
    $adminUrl = "https://{0}-admin.sharepoint.com" -f $tenantPrefix

    Connect-SPOService -Url $adminUrl
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

    Write-JsonFile -Path (Join-Path $BasePath 'graph\organization.json') `
        -InputObject (Get-MgOrganization)

    Write-JsonFile -Path (Join-Path $BasePath 'graph\domains.json') `
        -InputObject (Get-MgDomain -All)

    Write-JsonFile -Path (Join-Path $BasePath 'graph\subscribedSkus.json') `
        -InputObject (Get-MgSubscribedSku -All)

    Write-JsonFile -Path (Join-Path $BasePath 'graph\directoryRoles.json') `
        -InputObject (Get-MgDirectoryRole)

    Write-JsonFile -Path (Join-Path $BasePath 'graph\administrativeUnits.json') `
        -InputObject (Get-MgDirectoryAdministrativeUnit -All)

    Write-JsonFile -Path (Join-Path $BasePath 'graph\users.json') `
        -InputObject (Get-MgUser -All -Property "id,displayName,userPrincipalName,accountEnabled,userType,assignedLicenses,onPremisesSyncEnabled,createdDateTime")

    Write-JsonFile -Path (Join-Path $BasePath 'graph\groups.json') `
        -InputObject (Get-MgGroup -All -Property "id,displayName,mail,mailEnabled,securityEnabled,groupTypes,membershipRule,membershipRuleProcessingState,createdDateTime")

    Write-JsonFile -Path (Join-Path $BasePath 'graph\applications.json') `
        -InputObject (Get-MgApplication -All)

    Write-JsonFile -Path (Join-Path $BasePath 'graph\servicePrincipals.json') `
        -InputObject (Get-MgServicePrincipal -All)
}

function Export-GraphConditionalAccessPolicyCopies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $policies = Get-AllPages -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'

    Export-GraphObjectSet `
        -BasePath $BasePath `
        -RootFolderName 'conditional-access-policies' `
        -CollectionFileName 'conditionalAccessPolicies.json' `
        -IndexFileName 'conditionalAccessPolicies.index.json' `
        -Items $policies `
        -NameScriptBlock {
            param($item)
            $item.displayName
        } `
        -IndexProjectionScriptBlock {
            param($item, $safeName)
            [pscustomobject]@{
                id               = $item.id
                displayName      = $item.displayName
                state            = $item.state
                createdDateTime  = $item.createdDateTime
                modifiedDateTime = $item.modifiedDateTime
                fileName         = if ($item.id) { '{0}-{1}.json' -f $safeName, $item.id } else { '{0}.json' -f $safeName }
            }
        }
}

function Export-GraphNamedLocationCopies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $namedLocations = Get-AllPages -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations'

    Export-GraphObjectSet `
        -BasePath $BasePath `
        -RootFolderName 'named-locations' `
        -CollectionFileName 'namedLocations.json' `
        -IndexFileName 'namedLocations.index.json' `
        -Items $namedLocations `
        -NameScriptBlock {
            param($item)
            if ($item.displayName) { return $item.displayName }
            if ($item.id) { return $item.id }
            return 'named-location'
        } `
        -IndexProjectionScriptBlock {
            param($item, $safeName)
            [pscustomobject]@{
                id                  = $item.id
                displayName         = $item.displayName
                type                = $item.'@odata.type'
                isTrusted           = $item.isTrusted
                createdDateTime     = $item.createdDateTime
                modifiedDateTime    = $item.modifiedDateTime
                fileName            = if ($item.id) { '{0}-{1}.json' -f $safeName, $item.id } else { '{0}.json' -f $safeName }
            }
        }
}

function Export-GraphAuthenticationStrengthPolicyCopies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $authStrengthPolicies = Get-AllPages -Uri 'https://graph.microsoft.com/v1.0/policies/authenticationStrengthPolicies'

    Export-GraphObjectSet `
        -BasePath $BasePath `
        -RootFolderName 'authentication-strength-policies' `
        -CollectionFileName 'authenticationStrengthPolicies.json' `
        -IndexFileName 'authenticationStrengthPolicies.index.json' `
        -Items $authStrengthPolicies `
        -NameScriptBlock {
            param($item)
            if ($item.displayName) { return $item.displayName }
            if ($item.id) { return $item.id }
            return 'authentication-strength-policy'
        } `
        -IndexProjectionScriptBlock {
            param($item, $safeName)
            [pscustomobject]@{
                id                 = $item.id
                displayName        = $item.displayName
                policyType         = $item.policyType
                requirementsSatisfied = $item.requirementsSatisfied
                createdDateTime    = $item.createdDateTime
                modifiedDateTime   = $item.modifiedDateTime
                fileName           = if ($item.id) { '{0}-{1}.json' -f $safeName, $item.id } else { '{0}.json' -f $safeName }
            }
        }
}

function Export-GraphPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $policyRoot = 'https://graph.microsoft.com/v1.0'

    Export-GraphConditionalAccessPolicyCopies -BasePath $BasePath
    Export-GraphNamedLocationCopies -BasePath $BasePath
    Export-GraphAuthenticationStrengthPolicyCopies -BasePath $BasePath

    Write-JsonFile -Path (Join-Path $BasePath 'graph\authorizationPolicy.json') `
        -InputObject (Invoke-MgGraphRequest -Method GET -Uri "$policyRoot/policies/authorizationPolicy")

    Write-JsonFile -Path (Join-Path $BasePath 'graph\identitySecurityDefaultsEnforcementPolicy.json') `
        -InputObject (Invoke-MgGraphRequest -Method GET -Uri "$policyRoot/policies/identitySecurityDefaultsEnforcementPolicy")

    Write-JsonFile -Path (Join-Path $BasePath 'graph\authenticationMethodsPolicy.json') `
        -InputObject (Invoke-MgGraphRequest -Method GET -Uri "$policyRoot/policies/authenticationMethodsPolicy")

    Write-JsonFile -Path (Join-Path $BasePath 'graph\roleManagementDirectoryRoleDefinitions.json') `
        -InputObject (Get-AllPages -Uri "$policyRoot/roleManagement/directory/roleDefinitions")

    Write-JsonFile -Path (Join-Path $BasePath 'graph\roleManagementDirectoryRoleAssignments.json') `
        -InputObject (Get-AllPages -Uri "$policyRoot/roleManagement/directory/roleAssignments")
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
            CollectedAt = (Get-Date).ToString('o')
            Notes = @(
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
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$manifest = [System.Collections.Generic.List[object]]::new()
$errors   = [System.Collections.Generic.List[object]]::new()

New-OutputFolder -Path $OutputPath

Write-Host ("Output path: {0}" -f $OutputPath)

if ([string]::IsNullOrWhiteSpace($TenantId)) {
    throw "TenantId is not defined or empty - cannot execute"
}

Write-JsonFile -Path (Join-Path $OutputPath 'meta\run.json') -InputObject @{
    StartedAt       = (Get-Date).ToString('o')
    ComputerName    = $env:COMPUTERNAME
    PowerShell      = $PSVersionTable.PSVersion.ToString()
    Parameters      = @{
        TenantId         = $TenantId
        UseAppOnlyGraph  = [bool]$UseAppOnlyGraph
        SkipGraph        = [bool]$SkipGraph
        SkipExchange     = [bool]$SkipExchange
        SkipTeams        = [bool]$SkipTeams
        SkipSharePoint   = [bool]$SkipSharePoint
    }
}

try {
    if (-not $SkipGraph) {
        Invoke-CollectorStep -Area 'Graph' -Name 'Connect' -Manifest $manifest -Errors $errors -ScriptBlock {
            Connect-GraphTenant
        }

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
    try { Disconnect-MgGraph | Out-Null } catch {}
    try { Disconnect-ExchangeOnline -Confirm:$false } catch {}
    try { Disconnect-MicrosoftTeams } catch {}
}

Write-JsonFile -Path (Join-Path $OutputPath 'meta\manifest.json') -InputObject $manifest
Write-JsonFile -Path (Join-Path $OutputPath 'meta\errors.json')   -InputObject $errors

Write-Host 'Completed.'
Write-Host ('Manifest : {0}' -f (Join-Path $OutputPath 'meta\manifest.json'))
Write-Host ('Errors   : {0}' -f (Join-Path $OutputPath 'meta\errors.json'))
