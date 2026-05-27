# NAS via Azure Data Box/Disk (Draft for POC)

## Technical Objective

Copy the contents of a number of NAS NFS exports to a physical Azure Data Box/Disk devices inside a source tenant, when can then be physically shipped to Microsoft/Azure to be uploaded into a destinaton (JV) tenant hosting an Azure Premium Storage Account configured with Azure Files, from there it can be imported into the destination tenant SharePoint sites/libraries, via the [SPMT](https://learn.microsoft.com/en-us/sharepointmigration/introducing-the-sharepoint-migration-tool) toolset and if require import PST files into Microsoft 365 mailboxes via the 'free' M365 Import Service (apart of Purview).

## Required Source Confguration Details

The following information is required to plan and ultimately execute the migration.
1. The manufacturer, exact model and the exact firmware level of the NAS device. The assumption is that there is only one.
2. A comprehensive list of all NFS exports to be migrated, include all their mount options (NFS v2, v3 etc..).
A list of NFS can be obtained as follows:
NFS client
```shell
showmount -e 192.168.1.20 ### This might be unrelaible with NFS v4 or later
rpcinfo -p emc-nas01          
```
NFS server (NAS device)
```shell
## varies between models

## EMC VNX / Celerra:
server_export server_2 -list
# or
nas_server -list
## PowerScale / Isilon:
isi nfs exports list

```
3. A precise sizing (number of files, number of folders & the total size) per NFS export for each each NFS export to migrated.
4. Confirm with the source tenant NAS SME (Subject Matter Experts) that a filesystem level readonly snapshot can be created for each NFS export on the NAS device, and that you can configure a separate NFS export to permit a client to mount that Snapshot (readonly). We are currently assuming this is achieavable, if it is not possible, then we need to develop some alternative approaches.  

## Source: Physical Workstation

The source tenant will host a workstation (including corporate virus protection software) with dual network adapters.<br>
One network adapter will be connected to the corporate network with access to the NAS device.<br>
Second network adapter will be connected to a private network to the Azure Data Box<br>

The workstation will need to be configured as follows:
- Active Corporate image/SOE with Microsoft Windows 2022 (or Microsoft Windows 11)
- Atleast 1 CPU Socket with 4 Cores (8 Cores preferred)
- Atleast 1 Terabyte local disk (Drive C:) hosted on a SSD (solid state disk)
- Atleast 32Gb of RAM
- 2 x NICs, with alteast one being 10 GbE (10GBASE-T copper) capable
- Windows Subsystem for Linux (WSL) installed with an Ubuntu distribution
- Windows NFS client installed (```-FeatureName ServicesForNFS-ClientOnly```)
- Local administrator rights

> ℹ️ **Recommendation**<br>
> The operating system should be installed with the all the typical corporate AV, EndPoint Protection, SIEM integration, transparent proxy (Zscaler, Netskope etc..) components.<br>
> This is recommedended to ensure that those services (AV, EDR, SIEM, proxy etc..) are active throughout the migration, providing protections.

## Source: Azure Data Box

> Azure Data Box Next-Gen devices are now available with no service fee and no shipping fee when using Microsoft managed shipping.<br>
> Extra day fee may apply for devices that are not returned within the allotted usage period.

The latest Azure Data Box (Next Gen) is availalbe in Available in 2 storage sizes: *SKU 1* - *120 TB* usable (150 TB raw) and *SKU 2* - *525 TB* usable (600 TB raw)<br>
The device itself is 7 RU (U) when placed in the rack on its side (cannot be rack-mounted), so it must sit on a shelf<br>
<img width="700" height="497" alt="image" src="https://github.com/user-attachments/assets/ea258b85-370e-463b-b10d-c4abf4365c74" />

# Azure DataBox Cabling requirement
- 1 X power cable (included from Microsoft)
- 2 X 10G-BaseT RJ45 cables(CAT-5e or CAT6) (not included, needs to be supplied by source tenant)
- 2 X 100-GbE QSFP28 passive direct attached cable (not included, needs to be supplied by source tenant). 
Either the copper (10G-BASET) or twinaux (DAC/passive direct attached) can be utilised for the connection to the workstation.<br>
Realistically, unless the workstation is capable of hosting 100-GbE QSFP28 network adapters, the connectivity is recommended to be via 2 x 10G-BASE-T (copper) cables.<br>
However, there is probably no reasonable need to have load-balancing/failover between the workstation and the Data Box.<br>
So, the assupmtion will be that only one (CAT-5e/CAT-6) cable will be required to physically connect the workstation and Azure Data Box.<br>

| Technical Reference Material | Japanese  | English
|---|:--|:---|
| Windows Subsystem for Linux installation | [https://learn.microsoft.com/ja-jp/windows/wsl/install]() | [https://learn.microsoft.com/en-US/windows/wsl/install]()
| Video intorduction to Azure Data Box (Next-Gen) | | [https://www.youtube.com/watch?v=7NXworNZEBw]()
| Azure Data Box Pricing | [https://azure.microsoft.com/ja-JP/pricing/details/databox/]() | [https://azure.microsoft.com/en-us/pricing/details/databox/]()

## Source: Copying Data to Azure Data Box

The anticipated process will be to perform a number of migrations, one initial migration and then one or more incremental migration.

1. A completed 'tenant configuration' as outline [here](https://github.com/webstean/eire/blob/main/tenant-configuration/tenant-configuration.ps1).
2. Each NFS export to be migrated, will be made available as a dedicated NFS export of a read-only Snapshot of the actual NFS export.
3. This NFS export will then be mounted, either inside WSL or native on Windows on the workstation (the choice will depend upon the NFS export options)
4. Mount the Azure Data Box (NET USE) share(s) on the workstation via the 10 GbE connection
5. Initial: Perform a Copy of the entire to NFS export to the DataBox share.
6. Initial: Perform a 'offline metadata file copy with rsync' - that will preserve the metadata of the files copied and their size/data etc..
7. Incremental: Refresh the Snapshot presented from the NAS Device to be latest version
8. Incremental: Perform a rsync incremental, leveraging the previously created metadata file

Repeat incremental as many times as required.

> ℹ️ **PST Files**<br>
> PST Files will be included in the copies to the Azure Data Box. There is no separate appraoch to PST in the source tenat.
>

## Destination: Azure Preparation

### Prepare EIRE User Principals (user accounts)

- Create applciable accounts with the Global Reader privilege permanently assigned.
- Either via PIM or Permanently assign the following roles to the EIRE accounts:
Role: SharePoint Administrator<br>
Role: Teams Administrator<br>
Role: Exchange Administrator<br>
Role: Microsoft 365 Migration Administrator<br>

### Prepare Azure Files
1. Create an Azure Management Group (aka migration)
2. Create a dedicated Azure subscription (recommended - for better isolation) or reuse an existing (which should be empty)
3. Assign EIRE as 'Owner' (recommended) or atleast 'Contributor' to the manaagement group and/or subscription
4. If required, block destination tenant admins (Global Administrators etc..) from bring able to access the subscription/resource group with Azure RBAC Deny Assignments, so that only certain (EIRE) individuals actual have access.
6. Create a Premium Azure Storage Account with Azue Files enabled with the resource group/Subscription/manmagement group - EIRE must be the 'Owner' of this storage account.
7. Record the subscription, resource group and Storage Account resource id to be given to Microsoft/Azure as the destination for the Azure Data Box.

### Prepare Azure VM
1. Create an Azure VM
2. Install Windows 2022 (recommended) or Windows 11
3. Ensure the standard corporate protection (AV, EDR) are installed or install Microsoft Defender (via extension)
4. Make the VM available via Azure Bastion (or whatever other service) to EIRE users
5. Ensure EIRE users are granted local admin to the machine
6. Install [SPMT](https://learn.microsoft.com/en-us/sharepointmigration/introducing-the-sharepoint-migration-tool)  

> ℹ️ **Information**<br>
> Windows Server 2022 is recommended for best performance.<br>
> Hardware Configuration: 2 x vCPU, 4x vSockets per vCPU (Total of 8 vSockets), 16GB of RAM, Single 1TB (SSD) C: Drive<br>
> The recommended disk type is a single **Premium SSD v2** with ```disk-iops-read-write = 5000 & disk-mbps-read-write = 180```<br>

> ℹ️ **Recommendation**<br>
> The operating system should be installed with the all the typical corporate AV, EndPoint Protection, SIEM integration, transparent proxy (Zscaler, Netskope etc..) components.<br>
> This is recommedended to ensure that those services (AV, EDR, SIEM, proxy etc..) are active throughout the migration, providing protections.


### Prepare Windows 365, AVD (VDI) etc..
1. Provide a standard AVD/VDI machine to EIRE user(s)
2. Install PowerShell 7.x is enabled and available on the machine.
3. Ensure the following PowerShell modules are installed:
- Microsoft.Graph
- ExchangeOnline
- SharePointOnline
- PowrShell.PnP

## Destination: Migration

### Objective
All the files are now available in the Azure Files (Storage Account) within the destinatiion tenant.<br>
- The non-PSTs need to be imported into SharePoint
- The PSTs need to be imported into Exchange Online

### Procedure

#### Access the Azure VM, that has access to the Azure Files.
- Use SPMT to upload applicable Azure Files share into a library within a the desitnation SharePointr site.
- Use the PST Import Service (via the Purview Portal) to create jobs to import PSTS into the destination Exchange Online

#### Access AVD/VDI and perform the following
- Leverage PowerSHell.Pnp to create the agreed Role-Based access controls in the destination.
- Adjust SharePoint Libraries to provide the best end-user experience.
- Develop end-user facing dcoumentation to help users find their files from the migration.

## Permissions
The following permissions are required for creating, supporting and operating the migration for the applicable user principals.<br>
ID Role: Global Reader<br>


## Procedure for enabling [Microsoft Migration Manager](https://learn.microsoft.com/en-us/sharepointmigration/migrate-to-sharepoint-online)

> ℹ️ **Limitations**<br>
> Microsoft Migration Manager is intended for SMB/CIFS file share migrations (plus other 3rd part cloud providers) to SharePoint libraries<br>
> It **does not** officially support NFS - but if the NFS export (dependencies on export options, NFS versions) can be mounted on a Windows then it typically be be migrated.<br>
> SharePoint destinations paths are limited to 400 characters (including both path and filename/extension) - this include the name of the destination SharePoint library.<br> 

1. Prepare a single Windows VM/server - must be one of Windows Server 2016, Windows Server 2019, Windows Server 2022, Windows 10 or Windows 11.


> ℹ️ **Note**<br>
> By default, Migration Manager uses Microsoft managed Azure Storage Blobs for temporary storage of content and manifest during migration.<br>
> Customisation of the Azure Storage Blob is possible, but is complex, generally problematic and is not recommended.


 

1. Setup certificate-based auth config
```powershell
function New-MigrationManagerCertificateAuthConfigFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId = "$env:AZURE_TENANT_ID",

        [Parameter(Mandatory = $false)]
        [string]$ClientId = "$env:AZURE_CLIENT_ID",

        [Parameter(Mandatory)]
        [string]$SharePointAdminUrl,

        [Parameter(Mandatory)]
        [string]$CertificateThumbprint,

        [Parameter()]
        [string]$OutputPath = '.\migration-manager-cba-config.json'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $cert = Get-ChildItem -Path Cert:\CurrentUser\My |
        Where-Object Thumbprint -eq $CertificateThumbprint |
        Select-Object -First 1

    if (-not $cert) {
        throw "Certificate not found in CurrentUser\My: $CertificateThumbprint"
    }

    $config = [ordered]@{
        Thumbprint = $CertificateThumbprint
        TenantId   = $TenantId
        ClientId   = $ClientId
        AdminUrl   = $SharePointAdminUrl
    }

    $config |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $OutputPath -Encoding utf8

    Write-Host "Created config: $((Resolve-Path -LiteralPath $OutputPath).Path)"
}
```
2. Install / Verify agent service/files
```powershell
function Install-MigrationManagerAgentPrereqs {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$MinimumFreeSpaceGB = 500
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.Caption -notmatch 'Windows Server 2016|Windows Server 2019|Windows Server 2022|Windows 10|Windows 11') {
        throw "Unsupported OS: $($os.Caption)"
    }

    $dotNetRelease = Get-ItemPropertyValue `
        -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' `
        -Name Release `
        -ErrorAction Stop

    if ($dotNetRelease -lt 394802) {
        throw '.NET Framework 4.6.2 or later is required.'
    }

    $systemDrive = Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')
    $freeGB = [math]::Round($systemDrive.Free / 1GB, 2)

    if ($freeGB -lt $MinimumFreeSpaceGB) {
        throw "Insufficient free disk space. Required: $MinimumFreeSpaceGB GB. Found: $freeGB GB."
    }

    Write-Host "Prerequisites look OK."
}

function Install-MigrationManagerAgent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [Parameter()]
        [string]$CertificateAuthConfigPath = '.\migration-manager-cba-config.json'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
        throw "Installer not found: $InstallerPath"
    }

    if ($CertificateAuthConfigPath -and -not (Test-Path -LiteralPath $CertificateAuthConfigPath -PathType Leaf)) {
        throw "Certificate auth config not found: $CertificateAuthConfigPath"
    }

    Install-MigrationManagerAgentPrereqs

    Write-Host "Launching Migration Manager agent installer..."
    Write-Host "Installer: $InstallerPath"

    if ($CertificateAuthConfigPath) {
        Write-Host "Use Certificate Authentication and select:"
        Write-Host $CertificateAuthConfigPath
    }

    $process = Start-Process `
        -FilePath $InstallerPath `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Installer exited with code $($process.ExitCode)"
    }

    Write-Host "Installer completed."
}
```

3. Use Migration Manager PowerShell to create tasks

```powershell
function Invoke-MigrationManagerFileShareMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantName,

        [Parameter(Mandatory)]
        [string]$CsvPath,

        [Parameter()]
        [string]$MigrationManagerModulePath = 'C:\Program Files\Migration Manager\Microsoft.SharePoint.MigrationManager.PowerShell.dll',

        [Parameter()]
        [string]$AgentGroup = 'Default',

        [Parameter()]
        [datetime]$ScheduleStartTime = (Get-Date).AddMinutes(5),

        [Parameter()]
        [switch]$DownloadReports
    )

    <#
    CSV FORMAT:

    TaskName,SourceUri,TargetSiteUrl,TargetListName
    Finance Shared Drive,\\fileserver\finance,https://contoso.sharepoint.com/sites/Finance,Documents
    HR Shared Drive,\\fileserver\hr,https://contoso.sharepoint.com/sites/HR,Documents
    #>

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    try {

        #
        # Validate module
        #
        if (-not (Test-Path -LiteralPath $MigrationManagerModulePath -PathType Leaf)) {
            throw "Migration Manager PowerShell module not found: $MigrationManagerModulePath"
        }

        Write-Host ''
        Write-Host '=== Loading Migration Manager PowerShell Module ==='

        Import-Module $MigrationManagerModulePath -Force

        #
        # Validate CSV
        #
        if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
            throw "CSV file not found: $CsvPath"
        }

        $tasks = Import-Csv -LiteralPath $CsvPath

        if (-not $tasks) {
            throw "CSV contains no migration tasks."
        }

        #
        # Connect
        #
        Write-Host ''
        Write-Host "=== Connecting to Migration Manager Tenant: $TenantName ==="

        Connect-MigrationService `
            -Tenant $TenantName

        #
        # Create Tasks
        #
        Write-Host ''
        Write-Host '=== Creating Migration Tasks ==='

        $createdTasks = @()

        foreach ($task in $tasks) {

            if ([string]::IsNullOrWhiteSpace($task.TaskName)) {
                throw 'TaskName missing in CSV.'
            }

            if ([string]::IsNullOrWhiteSpace($task.SourceUri)) {
                throw "SourceUri missing for task: $($task.TaskName)"
            }

            if ([string]::IsNullOrWhiteSpace($task.TargetSiteUrl)) {
                throw "TargetSiteUrl missing for task: $($task.TaskName)"
            }

            if ([string]::IsNullOrWhiteSpace($task.TargetListName)) {
                throw "TargetListName missing for task: $($task.TaskName)"
            }

            Write-Host ''
            Write-Host "Creating task: $($task.TaskName)"
            Write-Host "  Source : $($task.SourceUri)"
            Write-Host "  Target : $($task.TargetSiteUrl)"
            Write-Host "  Library: $($task.TargetListName)"

            $migrationTask = Add-MigrationTask `
                -TaskName $task.TaskName `
                -SourceUri $task.SourceUri `
                -TargetSiteUrl $task.TargetSiteUrl `
                -TargetListName $task.TargetListName `
                -ScheduleStartTime $ScheduleStartTime `
                -AgentGroup $AgentGroup `
                -Tags @(
                    'PowerShell',
                    'Automated'
                )

            $createdTasks += $migrationTask

            Write-Host "Task created successfully."
        }

        #
        # Summary
        #
        Write-Host ''
        Write-Host '=== Migration Tasks Created ==='

        foreach ($createdTask in $createdTasks) {

            Write-Host (
                '{0,-40} {1}' -f `
                $createdTask.TaskName,
                $createdTask.Status
            )
        }

        #
        # Optional Report Download
        #
        if ($DownloadReports) {

            $reportRoot = Join-Path `
                -Path $env:TEMP `
                -ChildPath ('MigrationManagerReports_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))

            New-Item `
                -ItemType Directory `
                -Path $reportRoot `
                -Force | Out-Null

            Write-Host ''
            Write-Host "=== Downloading Reports to: $reportRoot ==="

            foreach ($createdTask in $createdTasks) {

                try {

                    $safeTaskName = (
                        $createdTask.TaskName `
                            -replace '[\\/:*?"<>|]', '_'
                    )

                    $scanReportPath = Join-Path `
                        -Path $reportRoot `
                        -ChildPath "$safeTaskName-scan.csv"

                    $migrationReportPath = Join-Path `
                        -Path $reportRoot `
                        -ChildPath "$safeTaskName-migration.csv"

                    Write-Host ''
                    Write-Host "Downloading reports for: $($createdTask.TaskName)"

                    Get-ScanReport `
                        -TaskId $createdTask.TaskId `
                        -OutputPath $scanReportPath

                    Get-MigrationReport `
                        -TaskId $createdTask.TaskId `
                        -OutputPath $migrationReportPath

                    Write-Host 'Reports downloaded.'
                }
                catch {
                    Write-Warning "Failed downloading reports for task: $($createdTask.TaskName)"
                    Write-Warning $_.Exception.Message
                }
            }

            Write-Host ''
            Write-Host "Reports available at: $reportRoot"
        }

        Write-Host ''
        Write-Host '=== Migration Submission Complete ==='
    }
    catch {
        Write-Error $_
        throw
    }
}
```
