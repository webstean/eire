
<#
.SYNOPSIS
    Ensures the current PowerShell session is running with local administrator rights.

.DESCRIPTION
    Validates whether the current identity is a member of the local Administrators
    group and throws if elevation is required.

.EXAMPLE
    Assert-LocalAdmin
#>
function Assert-LocalAdmin {
    [CmdletBinding()]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This must be run from an elevated (Run as Administrator) PowerShell session. Current user: $($identity.Name)"
    }
}

<#
.SYNOPSIS
    Displays robocopy and operating system version information.

.DESCRIPTION
    Writes robocopy executable version plus host OS details to assist with
    troubleshooting copy behavior across environments.

.EXAMPLE
    Get-Robocopyinfo
#>
function Get-Robocopyinfo {
    Write-Host '+========================================================='
    Write-Host 'RoboCopy Info:'
    (Get-Item "$env:SystemRoot\System32\Robocopy.exe").VersionInfo.FileVersion
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $type = if ($os.ProductType -eq 1) { 'Client' } else { 'Server' }
    Write-Host "$type - $($os.Caption) (Build $($os.BuildNumber))"
    Write-Host '+========================================================='
}  

<#
.SYNOPSIS
    Performs a lightweight outbound internet connectivity check.

.DESCRIPTION
    Requests the Microsoft connectivity test endpoint and returns a Boolean
    value indicating whether an HTTP 200 response was received.

.OUTPUTS
    System.Boolean

.EXAMPLE
    Test-InternetConnection
#>
function Test-InternetConnection {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $response = $null
    try {
        $request = [System.Net.WebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $request.Timeout = 5000
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        if ($response.StatusCode -eq [System.Net.HttpStatusCode]::OK) {
            return $true
        }
    } catch {
        return $false
    } finally {
        if ($null -ne $response) {
            $response.Close()
        }
    }

    return $false
}

<#
.SYNOPSIS
    Writes standardized status messages to host or GitHub step summary.

.DESCRIPTION
    Formats messages with timestamp and status prefix. When GITHUB_STEP_SUMMARY
    is available, appends output there; otherwise writes to host streams.

.PARAMETER InputObject
    Message text or pipeline input to render.

.PARAMETER Type
    Status category that controls prefix and output stream behavior.

.PARAMETER PassThru
    Returns the formatted line to the pipeline.

.PARAMETER ShowTimeStamp
    Includes a timestamp when set to true.

.EXAMPLE
    Write-StepSummary -Type success -InputObject 'Connection complete.'
#>
function Write-StepSummary {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, HelpMessage = 'Message text or object from the pipeline to format and output.')]
        [AllowNull()]
        $InputObject,

        [Parameter(HelpMessage = 'Message type used to choose output formatting and severity prefix.')]
        [ValidateSet('info', 'warning', 'success', 'error', 'debug', 'wait', 'waiting', 'warn', 'exception', 'skip', 'start', 'complete', 'completed')]
        [string]$Type = 'info',

        [Parameter(HelpMessage = 'Return the formatted message to the pipeline in addition to writing output.')]
        [switch]$PassThru,

        [Parameter(HelpMessage = 'Include a timestamp prefix on each emitted message line.')]
        [bool]$ShowTimeStamp = $true
    
    )

    begin {
        $useGitHubSummary = -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)

        $prefixMap = @{
            exception = '❌❌'
            info      = 'ℹ️'
            success   = '✅'
            error     = '❌'
            debug     = '🔍'
            wait      = '⏳'
            waiting   = '⏳'
            warn      = '⚠️'
            warning   = '⚠️'
            skip      = '⏭️'
            start     = '🚀'
            complete  = '🏁'
            completed = '🏁'
        }

        $prefix = $prefixMap[$Type]
    }

    process {
        $text = if ($null -eq $InputObject) {
            ''
        } elseif ($InputObject -is [string]) {
            $InputObject
        } else {
            ($InputObject | Out-String).TrimEnd()
        }

        if ($showTimeStamp) {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $line = "${timestamp}: ${prefix}: $text"
        } else {
            $line = "${prefix}: $text"
        }
        
        if ($useGitHubSummary) {
            Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $line -Encoding utf8
        } else {

            switch ($Type) {
                'error' {
                    Write-Error -Message $line
                }

                'exception' {
                    Write-Error -Message $line
                }

                'debug' {
                    Write-Verbose -Message $line
                }

                { $_ -in @('warn', 'warning') } {
                    Write-Warning -Message $line
                }

                default {
                    Write-Host $line
                }
            }
        }
        if ($PassThru) {
            $line
        }
    }
}

<#
.SYNOPSIS
    Connects to Microsoft Graph using application credentials (client secret).

.DESCRIPTION
    Ensures Microsoft.Graph.Authentication is installed/imported, authenticates
    using tenant ID, client ID, and secret, then returns connection metadata.

.PARAMETER Title
    Friendly label used in success and error messages.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER ClientId
    Application (client) ID.

.PARAMETER ClientSecret
    Application client secret in plain text.

.EXAMPLE
    Connect-MSGraphWithClientSecret -Title 'Destination' -TenantId $tenantId -ClientId $appId -ClientSecret $secret
#>
function Connect-MSGraphWithClientSecret {
    param(
        [Parameter(Mandatory, HelpMessage = 'Friendly label for the target context shown in status messages.')]
        [string]$Title,

        [Parameter(Mandatory, HelpMessage = 'Microsoft Entra tenant ID to authenticate against.')]
        [string]$TenantId,

        [Parameter(Mandatory, HelpMessage = 'Application (client) ID used for app-only authentication.')]
        [string]$ClientId,

        [Parameter(Mandatory, HelpMessage = 'Client secret value for the application registration.')]
        [string]$ClientSecret
    )

    if (-not (Get-Module Microsoft.Graph.Authentication -ListAvailable)) {
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $credential = [pscredential]::new($ClientId, $secureSecret)

    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome

    $context = Get-MgContext

    if (-not $context) {
        throw "Microsoft Graph connection failed to '$Title' with TenantId '$TenantId' and ClientId '$ClientId'"
    }

    Write-StepSummary -Type 'success' "Connected to Microsoft Graph '$Title'."

    [pscustomobject]@{
        Connected = $true
        TenantId  = $context.TenantId
        ClientId  = $context.ClientId
        AuthType  = $context.AuthType
    }
}

<#
.SYNOPSIS
    Connects to Exchange Online using application credentials (client secret).

.DESCRIPTION
    Acquires an OAuth token for Exchange Online and establishes an
    app-only Exchange Online PowerShell session.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER ClientId
    Application (client) ID.

.PARAMETER ClientSecret
    Application client secret in plain text.

.PARAMETER Organization
    Exchange Online organization or tenant domain.

.EXAMPLE
    Connect-ExchangeOnlineWithClientSecret -TenantId $tenantId -ClientId $appId -ClientSecret $secret -Organization contoso.onmicrosoft.com
#>
function Connect-ExchangeOnlineWithClientSecret {
    param(
        [Parameter(Mandatory, HelpMessage = 'Microsoft Entra tenant ID that issues the Exchange Online token.')]
        [string]$TenantId,

        [Parameter(Mandatory, HelpMessage = 'Application (client) ID used for app-only Exchange authentication.')]
        [string]$ClientId,

        [Parameter(Mandatory, HelpMessage = 'Client secret value for the application registration.')]
        [string]$ClientSecret,

        [Parameter(Mandatory, HelpMessage = 'Exchange Online organization value, typically tenant.onmicrosoft.com.')]
        [string]$Organization
    )

    if (-not (Get-Module ExchangeOnlineManagement -ListAvailable)) {
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
    }

    Import-Module ExchangeOnlineManagement -ErrorAction Stop

    $tokenBody = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = 'https://outlook.office365.com/.default'
        grant_type    = 'client_credentials'
    }

    $token = Invoke-RestMethod `
        -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Body $tokenBody `
        -ContentType 'application/x-www-form-urlencoded'

    Connect-ExchangeOnline `
        -AccessToken $token.access_token `
        -Organization $Organization `
        -ShowBanner:$false `
        -ErrorAction Stop

    Get-ConnectionInformation
}

<#
.SYNOPSIS
    Retrieves a certificate with a private key from the local certificate store.

.DESCRIPTION
    Resolves a certificate by thumbprint in the specified store location/name
    and validates that the certificate includes a private key.

.PARAMETER Thumbprint
    Certificate thumbprint to locate.

.PARAMETER StoreLocation
    Certificate store location: CurrentUser or LocalMachine.

.PARAMETER StoreName
    Certificate store name, such as My.

.OUTPUTS
    System.Security.Cryptography.X509Certificates.X509Certificate2

.EXAMPLE
    Get-LocalCertificateByThumbprint -Thumbprint $thumbprint -StoreLocation CurrentUser -StoreName My
#>
function Get-LocalCertificateByThumbprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'Certificate thumbprint to locate in the local certificate store.')]
        [string]$Thumbprint,

        [Parameter(HelpMessage = 'Certificate store location that contains the target certificate.')]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$StoreLocation = 'CurrentUser',

        [Parameter(HelpMessage = 'Certificate store name, such as My, where the certificate is stored.')]
        [ValidateNotNullOrEmpty()]
        [string]$StoreName = 'My'
    )

    $normalizedThumbprint = ($Thumbprint -replace '\s', '').ToUpperInvariant()
    $certPath = "Cert:\$StoreLocation\$StoreName\$normalizedThumbprint"
    $certificate = Get-Item -Path $certPath -ErrorAction SilentlyContinue

    if (-not $certificate) {
        throw "Certificate with thumbprint '$normalizedThumbprint' was not found in Cert:\$StoreLocation\$StoreName."
    }

    if (-not $certificate.HasPrivateKey) {
        throw "Certificate '$normalizedThumbprint' does not have a private key."
    }

    $certificate
}

<#
.SYNOPSIS
    Loads a certificate with private key from a file.

.DESCRIPTION
    Resolves the provided file path, loads the certificate with password,
    validates private key presence, and returns the certificate and file path.

.PARAMETER CertificateFilePath
    Path to the certificate file (for example, PFX).

.PARAMETER CertificatePassword
    Secure string password used to open the certificate file.

.OUTPUTS
    PSCustomObject

.EXAMPLE
    Get-LocalCertificateFromFile -CertificateFilePath 'C:\certs\app.pfx' -CertificatePassword $certPassword
#>
function Get-LocalCertificateFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'Path to the certificate file, typically a PFX file.')]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateFilePath,

        [Parameter(Mandatory, HelpMessage = 'Secure password used to open the certificate file.')]
        [securestring]$CertificatePassword
    )

    $resolvedFile = Resolve-Path -Path $CertificateFilePath -ErrorAction SilentlyContinue
    if (-not $resolvedFile) {
        throw "Certificate file '$CertificateFilePath' was not found."
    }

    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $resolvedFile.Path,
        $CertificatePassword
    )

    if (-not $certificate.HasPrivateKey) {
        throw "Certificate file '$($resolvedFile.Path)' does not contain a private key."
    }

    [pscustomobject]@{
        Certificate = $certificate
        Path        = $resolvedFile.Path
    }
}

<#
.SYNOPSIS
    Connects to Microsoft Graph using certificate-based app authentication.

.DESCRIPTION
    Supports certificate retrieval from local store or file path. After
    authenticating, returns connection context and certificate metadata.

.PARAMETER Title
    Friendly label used in success and error messages.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER ClientId
    Application (client) ID.

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate in local store (Store parameter set).

.PARAMETER CertificateStoreLocation
    Certificate store location used with CertificateThumbprint.

.PARAMETER CertificateStoreName
    Certificate store name used with CertificateThumbprint.

.PARAMETER CertificateFilePath
    Path to certificate file (File parameter set).

.PARAMETER CertificatePassword
    Password for certificate file. Defaults from CERT_PASSWORD environment variable.

.EXAMPLE
    Connect-MSGraphWithCertificate -Title 'Source' -TenantId $tenantId -ClientId $appId -CertificateThumbprint $thumbprint

.EXAMPLE
    Connect-MSGraphWithCertificate -Title 'Source' -TenantId $tenantId -ClientId $appId -CertificateFilePath 'C:\certs\app.pfx' -CertificatePassword $certPassword
#>
function Connect-MSGraphWithCertificate {
    [CmdletBinding(DefaultParameterSetName = 'Store')]
    param(
        [Parameter(Mandatory, HelpMessage = 'Friendly label for the target context shown in status messages.')]
        [string]$Title,

        [Parameter(Mandatory, HelpMessage = 'Microsoft Entra tenant ID to authenticate against.')]
        [string]$TenantId,

        [Parameter(Mandatory, HelpMessage = 'Application (client) ID used for app-only authentication.')]
        [string]$ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Store', HelpMessage = 'Certificate thumbprint in local store (Store parameter set).')]
        [string]$CertificateThumbprint,

        [Parameter(ParameterSetName = 'Store', HelpMessage = 'Certificate store location for thumbprint-based lookup.')]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$CertificateStoreLocation = 'CurrentUser',

        [Parameter(ParameterSetName = 'Store', HelpMessage = 'Certificate store name for thumbprint-based lookup, such as My.')]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateStoreName = 'My',

        [Parameter(Mandatory = $false, ParameterSetName = 'File', HelpMessage = 'Path to certificate file used for file-based authentication.')]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateFilePath,

        [Parameter(Mandatory = $false, ParameterSetName = 'File', HelpMessage = 'Secure password for the certificate file; defaults from CERT_PASSWORD environment variable.')]
        [securestring]$CertificatePassword = (ConvertTo-SecureString -String "$env:CERT_PASSWORD" -AsPlainText -Force)
    )

    if (-not (Get-Module Microsoft.Graph.Authentication -ListAvailable)) {
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $certificate = $null
    $certificateSource = $null
    $certificateFile = $null

    if ($PSCmdlet.ParameterSetName -eq 'Store') {
        $certificate = Get-LocalCertificateByThumbprint `
            -Thumbprint $CertificateThumbprint `
            -StoreLocation $CertificateStoreLocation `
            -StoreName $CertificateStoreName
        $certificateSource = "Store:Cert:\$CertificateStoreLocation\$CertificateStoreName"
    } else {
        $fileCertificate = Get-LocalCertificateFromFile `
            -CertificateFilePath $CertificateFilePath `
            -CertificatePassword $CertificatePassword
        $certificate = $fileCertificate.Certificate
        $certificateFile = $fileCertificate.Path
        $certificateSource = 'File'
    }

    Connect-MgGraph `
        -TenantId $TenantId `
        -ClientId $ClientId `
        -Certificate $certificate `
        -NoWelcome

    $context = Get-MgContext

    if (-not $context) {
        throw "Microsoft Graph connection failed to '$Title' with TenantId '$TenantId' and ClientId '$ClientId'."
    }

    Write-StepSummary -Type 'success' "Connected to Microsoft Graph '$Title' with certificate auth."

    [pscustomobject]@{
        Connected             = $true
        TenantId              = $context.TenantId
        ClientId              = $context.ClientId
        AuthType              = $context.AuthType
        CertificateThumbprint = $certificate.Thumbprint
        CertificateSubject    = $certificate.Subject
        CertificateSource     = $certificateSource
        CertificateFilePath   = $certificateFile
    }
}

<#
.SYNOPSIS
    Connects to Exchange Online using certificate-based app authentication.

.DESCRIPTION
    Supports local-store thumbprint or certificate file authentication and
    returns Exchange connection details with certificate metadata.

.PARAMETER Title
    Friendly label used in success messages.

.PARAMETER ClientId
    Application (client) ID.

.PARAMETER Organization
    Exchange Online organization or tenant domain.

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate in local store (Store parameter set).

.PARAMETER CertificateStoreLocation
    Certificate store location used with CertificateThumbprint.

.PARAMETER CertificateStoreName
    Certificate store name used with CertificateThumbprint.

.PARAMETER CertificateFilePath
    Path to certificate file (File parameter set).

.PARAMETER CertificatePassword
    Password for certificate file. Defaults from CERT_PASSWORD environment variable.

.EXAMPLE
    Connect-ExchangeOnlineWithCertificate -Title 'Destination' -ClientId $appId -Organization contoso.onmicrosoft.com -CertificateThumbprint $thumbprint
#>
function Connect-ExchangeOnlineWithCertificate {
    [CmdletBinding(DefaultParameterSetName = 'Store')]
    param(
        [Parameter(Mandatory, HelpMessage = 'Friendly label for the target context shown in status messages.')]
        [string]$Title,

        [Parameter(Mandatory, HelpMessage = 'Application (client) ID used for app-only Exchange authentication.')]
        [string]$ClientId,

        [Parameter(Mandatory, HelpMessage = 'Exchange Online organization value, typically tenant.onmicrosoft.com.')]
        [string]$Organization,

        [Parameter(Mandatory, ParameterSetName = 'Store', HelpMessage = 'Certificate thumbprint in local store (Store parameter set).')]
        [string]$CertificateThumbprint,

        [Parameter(ParameterSetName = 'Store', HelpMessage = 'Certificate store location for thumbprint-based lookup.')]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$CertificateStoreLocation = 'CurrentUser',

        [Parameter(ParameterSetName = 'Store', HelpMessage = 'Certificate store name for thumbprint-based lookup, such as My.')]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateStoreName = 'My',

        [Parameter(Mandatory, ParameterSetName = 'File', HelpMessage = 'Path to certificate file used for file-based authentication.')]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateFilePath,

        [Parameter(Mandatory = $false, ParameterSetName = 'File', HelpMessage = 'Secure password for the certificate file; defaults from CERT_PASSWORD environment variable.')]
        [securestring]$CertificatePassword = (ConvertTo-SecureString -String "$env:CERT_PASSWORD" -AsPlainText -Force)
    )

    if (-not (Get-Module ExchangeOnlineManagement -ListAvailable)) {
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
    }

    Import-Module ExchangeOnlineManagement -ErrorAction Stop

    $certificate = $null
    $certificateSource = $null
    $certificateFile = $null

    if ($PSCmdlet.ParameterSetName -eq 'Store') {
        $certificate = Get-LocalCertificateByThumbprint `
            -Thumbprint $CertificateThumbprint `
            -StoreLocation $CertificateStoreLocation `
            -StoreName $CertificateStoreName

        Connect-ExchangeOnline `
            -AppId $ClientId `
            -Organization $Organization `
            -CertificateThumbprint $certificate.Thumbprint `
            -ShowBanner:$false `
            -ErrorAction Stop

        $certificateSource = "Store:Cert:\$CertificateStoreLocation\$CertificateStoreName"
    } else {
        $fileCertificate = Get-LocalCertificateFromFile `
            -CertificateFilePath $CertificateFilePath `
            -CertificatePassword $CertificatePassword

        $certificate = $fileCertificate.Certificate
        $certificateFile = $fileCertificate.Path

        Connect-ExchangeOnline `
            -AppId $ClientId `
            -Organization $Organization `
            -CertificateFilePath $certificateFile `
            -CertificatePassword $CertificatePassword `
            -ShowBanner:$false `
            -ErrorAction Stop

        $certificateSource = 'File'
    }

    $connectionInfo = Get-ConnectionInformation

    Write-StepSummary -Type 'success' "Connected to Exchange Online '$Title' with certificate auth."

    [pscustomobject]@{
        Connected             = $true
        Organization          = $Organization
        AppId                 = $ClientId
        CertificateThumbprint = $certificate.Thumbprint
        CertificateSubject    = $certificate.Subject
        CertificateSource     = $certificateSource
        CertificateFilePath   = $certificateFile
        ConnectionInformation = $connectionInfo
    }
}

<#
.SYNOPSIS
    Validates required app-role and directory-role consent for a multi-tenant app.

.DESCRIPTION
    Checks whether the service principal exists, evaluates required Microsoft Graph
    and Exchange app-role assignments, and verifies required directory role
    assignments for the app service principal.

.PARAMETER AppId
    Application (client) ID of the multi-tenant app.

.PARAMETER RequiredGraphRoles
    Graph application roles that must be granted.

.PARAMETER RequiredExchangeRoles
    Exchange Online application roles that must be granted.

.PARAMETER RequiredDirectoryRoles
    Directory roles that must be assigned to the app service principal.

.OUTPUTS
    PSCustomObject

.EXAMPLE
    Test-MultiTenantAppConsent -AppId $appId
#>
function Test-MultiTenantAppConsent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'Application (client) ID of the multi-tenant app to validate.')]
        [string]$AppId,

        [Parameter(HelpMessage = 'List of Microsoft Graph app roles that must be consented in the tenant.')]
        [string[]]$RequiredGraphRoles = @(
            'User.Read.All',
            'Application.Read.All'
        ),

        [Parameter(HelpMessage = 'List of Exchange Online app roles that must be consented in the tenant.')]
        [string[]]$RequiredExchangeRoles = @(
            'Exchange.ManageAsApp',
            'Mailbox.Migration'
        ),

        [Parameter(HelpMessage = 'Directory roles the service principal must be assigned for required permissions.')]
        [string[]]$RequiredDirectoryRoles = @(
            'Exchange Administrator'
        )
    )

    $GraphAppId = '00000003-0000-0000-c000-000000000000'
    $ExchangeAppId = '00000002-0000-0ff1-ce00-000000000000'

    $requiredScopes = @(
        'Application.Read.All',
        'AppRoleAssignment.ReadWrite.All',
        'Directory.Read.All',
        'RoleManagement.Read.Directory'
    )

    $ctx = Get-MgContext
    if (-not $ctx) {
        throw "Not connected to Microsoft Graph. Run: Connect-MgGraph -TenantId <destinationTenantId> -Scopes '$($requiredScopes -join "','")'"
    }

    $clientSp = Get-MgServicePrincipal `
        -Filter "appId eq '$AppId'" `
        -Property 'id,appId,displayName' `
        -ConsistencyLevel eventual

    if (-not $clientSp) {
        return [pscustomobject]@{
            AppId          = $AppId
            Exists         = $false
            FullyConsented = $false
            Missing        = 'Service principal does not exist in this tenant'
        }
    }

    $assignments = Get-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $clientSp.Id `
        -All

    <#
    .SYNOPSIS
        Gets a resource service principal by application ID.

    .PARAMETER ResourceAppId
        Application ID of the target resource service principal.
    #>
    function Get-ResourceSp {
        param(
            [Parameter(Mandatory, HelpMessage = 'Application ID of the resource service principal to resolve.')]
            [string]$ResourceAppId
        )

        Get-MgServicePrincipal `
            -Filter "appId eq '$ResourceAppId'" `
            -Property 'id,appId,displayName,appRoles' `
            -ConsistencyLevel eventual
    }

    $graphSp = Get-ResourceSp -ResourceAppId $GraphAppId
    $exchangeSp = Get-ResourceSp -ResourceAppId $ExchangeAppId

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($roleName in $RequiredGraphRoles) {
        $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $roleName }

        $granted = $false
        if ($role) {
            $granted = [bool]($assignments | Where-Object {
                    $_.ResourceId -eq $graphSp.Id -and $_.AppRoleId -eq $role.Id
                })
        }

        $results.Add([pscustomobject]@{
                Resource  = 'Microsoft Graph'
                Role      = $roleName
                AppRoleId = if ($role) { $role.Id } else { $null }
                Granted   = $granted
            })
    }

    foreach ($roleName in $RequiredExchangeRoles) {
        $role = $exchangeSp.AppRoles | Where-Object { $_.Value -eq $roleName }

        $granted = $false
        if ($role) {
            $granted = [bool]($assignments | Where-Object {
                    $_.ResourceId -eq $exchangeSp.Id -and $_.AppRoleId -eq $role.Id
                })
        }

        $results.Add([pscustomobject]@{
                Resource  = 'Office 365 Exchange Online'
                Role      = $roleName
                AppRoleId = if ($role) { $role.Id } else { $null }
                Granted   = $granted
            })
    }

    $directoryRoleResults = foreach ($roleName in $RequiredDirectoryRoles) {
        $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition `
            -Filter "displayName eq '$roleName'" `
            -Property 'id,displayName'

        $roleAssignments = @()

        if ($roleDefinition) {
            $roleAssignments = Get-MgRoleManagementDirectoryRoleAssignment `
                -Filter "principalId eq '$($clientSp.Id)' and roleDefinitionId eq '$($roleDefinition.Id)'" `
                -All
        }

        [pscustomobject]@{
            Role    = $roleName
            Granted = [bool]$roleAssignments
        }
    }

    $missingAppRoles = $results | Where-Object { -not $_.Granted }
    $missingDirRoles = $directoryRoleResults | Where-Object { -not $_.Granted }

    [pscustomobject]@{
        AppId                 = $AppId
        DisplayName           = $clientSp.DisplayName
        ServicePrincipalId    = $clientSp.Id
        Exists                = $true
        FullyConsented        = (-not $missingAppRoles -and -not $missingDirRoles)
        AppRoleConsent        = $results
        DirectoryRoleConsent  = $directoryRoleResults
        MissingAppRoles       = $missingAppRoles
        MissingDirectoryRoles = $missingDirRoles
    }
}

<#
.SYNOPSIS
    Mirrors a source directory to destination with robocopy tuned for NAS migrations.

.DESCRIPTION
    Runs robocopy with mirror settings, Unicode-safe logging, and optional
    post-copy verification for missing items. Attempts to temporarily adjust
    Defender network scanning and restores the original setting on exit.

.PARAMETER Source
    Source directory path.

.PARAMETER Destination
    Destination directory path.

.PARAMETER Threads
    Robocopy multithread count.

.PARAMETER LogDirectory
    Directory where robocopy log files are written.

.PARAMETER VerifyAfterCopy
    Runs additional source/destination item verification after robocopy completes.

.OUTPUTS
    PSCustomObject

.EXAMPLE
    Invoke-RobocopyMirrorforNAS -Source 'D:\Data' -Destination '\\nas\migration\Data' -Threads 32 -VerifyAfterCopy
#>
function Invoke-RobocopyMirrorforNAS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'Source directory path to mirror from.')]
        [string]$Source,
        [Parameter(Mandatory, HelpMessage = 'Destination directory path to mirror to.')]
        [string]$Destination,
        [Parameter(HelpMessage = 'Robocopy multithreading level between 1 and 128.')]
        [ValidateRange(1, 128)]
        [int]$Threads = $DefaultThreads,
        [Parameter(HelpMessage = 'Directory where robocopy log files will be created.')]
        [string]$LogDirectory = 'C:\Logs',
        [Parameter(HelpMessage = 'Run post-copy verification to detect missing items after mirroring.')]
        [switch]$VerifyAfterCopy
    )

    Assert-LocalAdmin
    Set-MpPreference -DisableScanningNetworkFiles $true
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source path not found: $Source"
    }
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force *> $null
    }

    # Diagnostic info only — must not land on the pipeline alongside the return object
    $robocopyVersion = (Get-Item "$env:SystemRoot\System32\Robocopy.exe").VersionInfo.FileVersion
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $type = if ($os.ProductType -eq 1) { 'Client' } else { 'Server' }
    Write-Verbose "Robocopy $robocopyVersion on $type - $($os.Caption) (Build $($os.BuildNumber))"

    # Capture original Defender setting so it can be restored — this is a machine-wide
    # security-relevant setting and must not be left disabled after the function returns
    $originalDisableScanningNetworkFiles = $null
    $mpPreferenceChanged = $false
    try {
        $originalDisableScanningNetworkFiles = (Get-MpPreference -ErrorAction Stop).DisableScanningNetworkFiles
        Set-MpPreference -DisableScanningNetworkFiles $true -ErrorAction Stop
        $mpPreferenceChanged = $true
    } catch {
        Write-Warning "Could not adjust Defender network-file scanning preference (may require admin, or Defender is managed by policy): $($_.Exception.Message)"
    }

    # Ensure console/session can render non-English output correctly (cosmetic, but prevents
    # garbled display if anything gets written to host during the run)
    $originalOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    $logPath = Join-Path -Path $LogDirectory -ChildPath "robocopy-mirror-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $robocopyArgs = @(
        "`"$Source`"",
        "`"$Destination`"",
        '/MIR',
        '/COPY:DAT',
        '/DCOPY:DAT',
        "/MT:$Threads",
        '/R:1',
        '/W:1',
        '/NP',
        '/NDL',
        "/UNILOG:`"$logPath`"",   # Unicode-encoded log so non-English filenames render correctly (plain /LOG produces gibberish)
        '/UNICODE',                # forces Unicode console/output stream from robocopy itself
        '/TEE'
    )

    try {
        $process = Start-Process -FilePath 'robocopy.exe' -ArgumentList $robocopyArgs -Wait -NoNewWindow -PassThru
        if ($process.ExitCode -ge 8) {
            throw "Robocopy failed with exit code $($process.ExitCode). See log: $logPath"
        }

        $result = [PSCustomObject]@{
            Source          = $Source
            Destination     = $Destination
            ExitCode        = $process.ExitCode
            LogPath         = $logPath
            Success         = $true
            VerificationRun = $false
            MissingItems    = @()
        }

        # Robocopy can silently fail to copy items with malformed/invalid UTF-16 names
        # (unpaired surrogates) and reports success with no error. This step catches that
        # by independently comparing recursive item counts/paths, not relying on robocopy's own reporting.
        if ($VerifyAfterCopy) {
            Write-Verbose 'Running post-copy verification for silent Unicode failures...'

            # OrdinalIgnoreCase: NTFS/SMB are case-insensitive, default HashSet comparer is not
            $sourceItems = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $destItems = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($path in [System.IO.Directory]::EnumerateFileSystemEntries($Source, '*', 'AllDirectories')) {
                [void]$sourceItems.Add($path.Substring($Source.Length).TrimStart('\'))
            }
            foreach ($path in [System.IO.Directory]::EnumerateFileSystemEntries($Destination, '*', 'AllDirectories')) {
                [void]$destItems.Add($path.Substring($Destination.Length).TrimStart('\'))
            }

            $missing = $sourceItems | Where-Object { -not $destItems.Contains($_) }
            $result.VerificationRun = $true
            $result.MissingItems = @($missing)
            if ($missing.Count -gt 0) {
                Write-Warning "$($missing.Count) item(s) present in source but missing from destination — possible malformed Unicode names. See MissingItems on the returned object."
            }
        }

        return $result
    } finally {
        [Console]::OutputEncoding = $originalOutputEncoding
        if ($mpPreferenceChanged) {
            Set-MpPreference -DisableScanningNetworkFiles $originalDisableScanningNetworkFiles
        }
    }
}

function Compare-FileChecksum {
    <#
    .SYNOPSIS
        Compares two files by MD5 checksum to verify they are identical.

    .DESCRIPTION
        Computes an MD5 hash for each file independently and compares them.
        Useful for verifying copy integrity across a migration/transfer path
        (e.g. NFS -> DataBox, robocopy destination verification) without
        relying on file size/timestamp alone.

    .PARAMETER Path1
        Path to the first file.

    .PARAMETER Path2
        Path to the second file, typically at a different location.

    .EXAMPLE
        Compare-FileChecksum -Path1 'D:\Source\file.zip' -Path2 '\\nas\share\file.zip'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'Path to the first file to hash and compare.')]
        [string]$Path1,

        [Parameter(Mandatory, HelpMessage = 'Path to the second file to hash and compare.')]
        [string]$Path2
    )

    if (-not (Test-Path -LiteralPath $Path1)) {
        throw "File not found: $Path1"
    }
    if (-not (Test-Path -LiteralPath $Path2)) {
        throw "File not found: $Path2"
    }

    $hash1 = Get-FileHash -LiteralPath $Path1 -Algorithm MD5
    $hash2 = Get-FileHash -LiteralPath $Path2 -Algorithm MD5

    [PSCustomObject]@{
        Path1        = $Path1
        Path2        = $Path2
        Hash1        = $hash1.Hash
        Hash2        = $hash2.Hash
        AreIdentical = $hash1.Hash -eq $hash2.Hash
    }
}

function Compare-DirectoryChecksum {
    <#
    .SYNOPSIS
        Compares two directories, one level deep only, verifying both file
        count and MD5 checksum match for every file.

    .DESCRIPTION
        Does NOT recurse into subdirectories — only files directly inside
        Path1/Path2 are compared. Subdirectories themselves are ignored
        entirely (neither counted nor descended into). Useful as a quick
        top-level integrity check after a copy/migration step, without the
        cost of a full recursive hash of an entire tree.

    .PARAMETER Path1
        First directory path.

    .PARAMETER Path2
        Second directory path, typically the migration/copy destination.

    .EXAMPLE
        Compare-DirectoryChecksum -Path1 'D:\Source\Finance' -Path2 '\\nas\share\Finance'

    .EXAMPLE
        Compare-DirectoryChecksum -Path1 'D:\Source' -Path2 'D:\Dest' | Select-Object -ExpandProperty MismatchedFiles
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'Path to the first directory to compare.')]
        [string]$Path1,

        [Parameter(Mandatory, HelpMessage = 'Path to the second directory to compare.')]
        [string]$Path2
    )

    if (-not (Test-Path -LiteralPath $Path1 -PathType Container)) {
        throw "Directory not found: $Path1"
    }
    if (-not (Test-Path -LiteralPath $Path2 -PathType Container)) {
        throw "Directory not found: $Path2"
    }

    # -File with no -Recurse: only files directly in the folder, subfolders
    # are neither counted nor entered.
    $files1 = Get-ChildItem -LiteralPath $Path1 -File
    $files2 = Get-ChildItem -LiteralPath $Path2 -File

    $countMatch = $files1.Count -eq $files2.Count

    # Build name -> hash lookups so files are matched by name, not by
    # directory listing order (Get-ChildItem order isn't guaranteed identical
    # across two different filesystems/shares).
    $hashes1 = @{}
    foreach ($f in $files1) {
        $hashes1[$f.Name] = (Get-FileHash -LiteralPath $f.FullName -Algorithm MD5).Hash
    }
    $hashes2 = @{}
    foreach ($f in $files2) {
        $hashes2[$f.Name] = (Get-FileHash -LiteralPath $f.FullName -Algorithm MD5).Hash
    }

    $onlyInPath1 = @($hashes1.Keys | Where-Object { -not $hashes2.ContainsKey($_) })
    $onlyInPath2 = @($hashes2.Keys | Where-Object { -not $hashes1.ContainsKey($_) })

    $mismatchedFiles = @(
        foreach ($name in $hashes1.Keys) {
            if ($hashes2.ContainsKey($name) -and $hashes1[$name] -ne $hashes2[$name]) {
                [PSCustomObject]@{
                    FileName = $name
                    Hash1    = $hashes1[$name]
                    Hash2    = $hashes2[$name]
                }
            }
        }
    )

    $isIdentical = $countMatch -and
    $onlyInPath1.Count -eq 0 -and
    $onlyInPath2.Count -eq 0 -and
    $mismatchedFiles.Count -eq 0

    [PSCustomObject]@{
        Path1           = $Path1
        Path2           = $Path2
        FileCount1      = $files1.Count
        FileCount2      = $files2.Count
        CountMatch      = $countMatch
        OnlyInPath1     = $onlyInPath1
        OnlyInPath2     = $onlyInPath2
        MismatchedFiles = $mismatchedFiles
        IsIdentical     = $isIdentical
    }
}

function Get-DirectoryChecksum {
    <#
    .SYNOPSIS
        Generates MD5 checksums for files in a single directory (top level only).

    .DESCRIPTION
        Computes MD5 hashes for each file directly inside the specified directory.
        This function does not recurse into subdirectories and performs no
        source/destination comparison.

    .PARAMETER Path
        Directory path to hash.

    .EXAMPLE
        Get-DirectoryChecksum -Path 'D:\Source\Finance'

    .EXAMPLE
        Get-DirectoryChecksum -Path 'D:\Source\Finance' | Select-Object -ExpandProperty FileChecksums
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'Path to the directory whose file checksums will be generated.')]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Directory not found: $Path"
    }

    # -File with no -Recurse means only files directly in this folder are hashed.
    $files = Get-ChildItem -LiteralPath $Path -File

    $fileChecksums = @(
        foreach ($file in $files) {
            [PSCustomObject]@{
                FileName = $file.Name
                FullName = $file.FullName
                Size     = $file.Length
                Hash     = (Get-FileHash -LiteralPath $file.FullName -Algorithm MD5).Hash
            }
        }
    )

    [PSCustomObject]@{
        Path          = $Path
        FileCount     = $files.Count
        FileChecksums = $fileChecksums
    }
}

function Compare-AzureFilesToSharePoint {
    <#
    .SYNOPSIS
        Compares files between an Azure Files share and a SharePoint Online document library folder by MD5 hash.

    .DESCRIPTION
        Recursively enumerates files from a local/UNC Azure Files path and a SharePoint Online folder,
        computes MD5 hashes for each file, and produces a comparison report identifying matches,
        hash mismatches, and files missing from either side.

        SharePoint files are downloaded transiently to a temp directory for hashing and immediately
        deleted — no persistent local copy is retained.

        Requires an active PnP.PowerShell connection established before calling this function
        (Connect-PnPOnline).

    .PARAMETER AzureFilesPath
        Local or UNC path to the Azure Files share root or subfolder to compare.
        Examples:
          Z:\migrated-data
          \\storageacct.file.core.windows.net\share\folder

    .PARAMETER SharePointFolderPath
        Server-relative URL of the SharePoint folder to compare against.
        Example: /sites/mysite/Shared Documents/migrated-data

    .PARAMETER ReportPath
        Path for the output CSV report. Defaults to .\comparison-report.csv.
        Encoding is UTF-8 BOM for Excel compatibility.

    .PARAMETER TempDir
        Temporary directory used to download SPO files for hashing.
        Created if it does not exist; cleaned up on completion.
        Defaults to $env:TEMP\spo-hash-tmp.

    .PARAMETER PassThru
        When specified, returns the comparison result objects to the pipeline in addition
        to writing the CSV report.

    .INPUTS
        None. Parameters only.

    .OUTPUTS
        None by default. With -PassThru, outputs PSCustomObject[] with properties:
          RelativePath    - Path relative to both root locations
          Status          - Match | HashMismatch | MissingFromSPO | MissingFromAzureFiles
          AzureHash       - MD5 hash from Azure Files side (empty if missing)
          SPOHash         - MD5 hash from SharePoint side (empty if missing)
          AzureSize       - File size in bytes from Azure Files (0 if missing)
          SPOSize         - File size in bytes from SharePoint (0 if missing)

    .EXAMPLE
        Connect-PnPOnline -Url https://contoso.sharepoint.com/sites/mysite -Interactive

        Compare-AzureFilesToSharePoint `
            -AzureFilesPath Z:\migrated-data `
            -SharePointFolderPath "/sites/mysite/Shared Documents/migrated-data"

        Compares all files under Z:\migrated-data against the corresponding SharePoint folder,
        writes results to .\comparison-report.csv.

    .EXAMPLE
        Connect-PnPOnline -Url https://contoso.sharepoint.com/sites/mysite -ManagedIdentity

        $results = Compare-AzureFilesToSharePoint `
            -AzureFilesPath \\storageacct.file.core.windows.net\share\data `
            -SharePointFolderPath "/sites/mysite/Shared Documents/data" `
            -ReportPath C:\reports\migration-$(Get-Date -Format yyyyMMdd).csv `
            -PassThru

        $results | Where-Object Status -ne 'Match' | Format-Table

        Runs comparison with a managed identity connection, outputs CSV to a dated path,
        and returns objects to the pipeline for further filtering.

    .NOTES
        - PnP.PowerShell must be installed and Connect-PnPOnline called before use.
        - SharePointFolderPath is case-sensitive on SharePoint Online.
        - For libraries with 5000+ items, PnP handles list view threshold automatically.
        - MD5 is used for speed; not intended as a cryptographic integrity check.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, HelpMessage = 'Local or UNC path to the Azure Files share folder.')]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$AzureFilesPath,

        [Parameter(Mandatory, HelpMessage = 'Server-relative URL of the SharePoint folder, e.g. /sites/mysite/Shared Documents/folder.')]
        [ValidatePattern('^/')]
        [string]$SharePointFolderPath,

        [Parameter(HelpMessage = 'Output CSV report path. Default: .\comparison-report.csv')]
        [string]$ReportPath = '.\comparison-report.csv',

        [Parameter(HelpMessage = 'Temp directory for transient SPO file downloads.')]
        [string]$TempDir = "$env:TEMP\spo-hash-tmp",

        [Parameter(HelpMessage = 'Return result objects to the pipeline.')]
        [switch]$PassThru
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    #region Private helpers

    function script:Get-MD5HashFromFile {
        param(
            [Parameter(Mandatory, HelpMessage = 'Full path to a file whose MD5 hash will be calculated.')]
            [string]$FilePath
        )
        $md5 = [System.Security.Cryptography.MD5]::Create()
        try {
            $stream = [System.IO.File]::OpenRead($FilePath)
            try {
                return [BitConverter]::ToString($md5.ComputeHash($stream)) -replace '-', ''
            } finally {
                $stream.Dispose()
            }
        } finally {
            $md5.Dispose()
        }
    }

    function script:Get-SPOFilesRecursive {
        param(
            [Parameter(Mandatory, HelpMessage = 'Server-relative URL of the SharePoint folder to enumerate recursively.')]
            [string]$FolderServerRelativeUrl,
            [Parameter(Mandatory, HelpMessage = 'Base server-relative URL used to compute relative output paths.')]
            [string]$BaseServerRelativeUrl
        )
        $files = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderServerRelativeUrl -ItemType File -ErrorAction Stop
        foreach ($file in $files) {
            [PSCustomObject]@{
                RelativePath      = ($file.ServerRelativeUrl.Substring($BaseServerRelativeUrl.Length).TrimStart('/')) -replace '/', [IO.Path]::DirectorySeparatorChar
                ServerRelativeUrl = $file.ServerRelativeUrl
                Size              = $file.Length
            }
        }
        $subfolders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderServerRelativeUrl -ItemType Folder -ErrorAction Stop
        foreach ($folder in $subfolders) {
            script:Get-SPOFilesRecursive -FolderServerRelativeUrl $folder.ServerRelativeUrl -BaseServerRelativeUrl $BaseServerRelativeUrl
        }
    }

    #endregion

    #region Index: Azure Files

    Write-Host "Indexing Azure Files: $AzureFilesPath" -ForegroundColor Cyan
    $azureIndex = @{}
    $azureItems = @(Get-ChildItem -Path $AzureFilesPath -Recurse -File)
    $basePath = $AzureFilesPath.TrimEnd('\', '/')

    for ($i = 0; $i -lt $azureItems.Count; $i++) {
        $file = $azureItems[$i]
        $relPath = $file.FullName.Substring($basePath.Length).TrimStart('\', '/')
        Write-Progress -Activity 'Hashing Azure Files' -Status $relPath -PercentComplete (($i + 1) / $azureItems.Count * 100)
        $azureIndex[$relPath] = [PSCustomObject]@{
            Hash = script:Get-MD5HashFromFile -FilePath $file.FullName
            Size = $file.Length
        }
    }
    Write-Progress -Activity 'Hashing Azure Files' -Completed
    Write-Host "  $($azureIndex.Count) file(s) found." -ForegroundColor Gray

    #endregion

    #region Index: SharePoint Online

    Write-Host "Indexing SharePoint: $SharePointFolderPath" -ForegroundColor Cyan
    $spoIndex = @{}
    $baseSpoUrl = $SharePointFolderPath.TrimEnd('/')
    $null = New-Item -ItemType Directory -Path $TempDir -Force

    try {
        $spoItems = @(script:Get-SPOFilesRecursive -FolderServerRelativeUrl $baseSpoUrl -BaseServerRelativeUrl $baseSpoUrl)

        for ($i = 0; $i -lt $spoItems.Count; $i++) {
            $item = $spoItems[$i]
            $tmpName = [IO.Path]::GetRandomFileName()
            $tmpFile = Join-Path $TempDir $tmpName
            Write-Progress -Activity 'Hashing SharePoint files' -Status $item.RelativePath -PercentComplete (($i + 1) / $spoItems.Count * 100)
            try {
                Get-PnPFile -Url $item.ServerRelativeUrl -Path $TempDir -Filename $tmpName -AsFile -Force *> $null
                $spoIndex[$item.RelativePath] = [PSCustomObject]@{
                    Hash = script:Get-MD5HashFromFile -FilePath $tmpFile
                    Size = $item.Size
                }
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }
        Write-Progress -Activity 'Hashing SharePoint files' -Completed
        Write-Host "  $($spoIndex.Count) file(s) found." -ForegroundColor Gray
    } finally {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    #endregion

    #region Compare

    Write-Host 'Comparing...' -ForegroundColor Cyan
    $results = [Collections.Generic.List[PSCustomObject]]::new()
    $allKeys = ($azureIndex.Keys + $spoIndex.Keys) | Sort-Object -Unique

    foreach ($key in $allKeys) {
        $inAzure = $azureIndex.ContainsKey($key)
        $inSpo = $spoIndex.ContainsKey($key)

        $results.Add([PSCustomObject]@{
                RelativePath = $key
                Status       = if ($inAzure -and $inSpo) {
                    if ($azureIndex[$key].Hash -eq $spoIndex[$key].Hash) { 'Match' } else { 'HashMismatch' }
                } elseif ($inAzure) { 'MissingFromSPO' } else { 'MissingFromAzureFiles' }
                AzureHash    = if ($inAzure) { $azureIndex[$key].Hash } else { '' }
                SPOHash      = if ($inSpo) { $spoIndex[$key].Hash } else { '' }
                AzureSize    = if ($inAzure) { $azureIndex[$key].Size } else { 0 }
                SPOSize      = if ($inSpo) { $spoIndex[$key].Size } else { 0 }
            })
    }

    #endregion

    #region Report

    $results | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8BOM

    Write-Host ''
    Write-Host 'Results:' -ForegroundColor Cyan
    foreach ($g in ($results | Group-Object Status)) {
        $colour = switch ($g.Name) {
            'Match' { 'Green' }
            'HashMismatch' { 'Red' }
            'MissingFromSPO' { 'Yellow' }
            'MissingFromAzureFiles' { 'Yellow' }
            default { 'White' }
        }
        Write-Host ('  {0,-25} {1}' -f $g.Name, $g.Count) -ForegroundColor $colour
    }

    $issueCount = ($results | Where-Object { $_.Status -ne 'Match' }).Count
    if ($issueCount -eq 0) {
        Write-Host "`nAll files match." -ForegroundColor Green
    } else {
        Write-Host "`n$issueCount issue(s) found. Report: $ReportPath" -ForegroundColor Red
    }

    if ($PassThru) { $results.ToArray() }

    #endregion
}