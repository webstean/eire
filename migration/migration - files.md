# NAS via Azure Data Box/Disk (Draft for POC)

## Technical Objective

Copy the contents of a number of NAS NFS exports to a physical Azure Data Box/Disk devices inside a source tenant, when can then be physically shipped to Microsoft/Azure to be uploaded into a destinaton (JV) tenant hosting an Azure Premium Storage Account configured with Azure Files, from there it can be imported into the destination tenant SharePoint sites/libraries, via the [SPMT](https://learn.microsoft.com/en-us/sharepointmigration/introducing-the-sharepoint-migration-tool) toolset and if require import PST files into Microsoft 365 mailboxes via the 'free' M365 Import Service (apart of Purview).

## Required Source Confguration Details

The following information is required to plan and ultimately execute the migration.
1. A completed 'tenant configuration' that can be obtained by executiing this [script](https://github.com/webstean/eire/blob/main/tenant-configuration/tenant-configuration.ps1) as per this detailed [documentation](https://github.com/webstean/eire/blob/main/tenant-configuration/tenant-configuration.md). 
2. The manufacturer, exact model and the exact firmware level of the NAS device. The assumption is that there is only one.
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
>
> ℹ️ **Information**<br>
> The workstation needs to store detailed meta data (created by rsync), in order to do perform incremental copies of data. This data will need to be preserved throughout the duration of the whole migration

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
| Video introduction to Azure Data Box (Next-Gen) | | [https://www.youtube.com/watch?v=7NXworNZEBw]()
| Windows Subsystem for Linux installation | [https://learn.microsoft.com/ja-jp/windows/wsl/install]() | [https://learn.microsoft.com/en-US/windows/wsl/install]()
| Azure Data Box Pricing | [https://azure.microsoft.com/ja-JP/pricing/details/databox/]() | [https://azure.microsoft.com/en-us/pricing/details/databox/]()

## Source: Copying Data to Azure Data Box

The anticipated process will be to perform a number of migrations, one initial migration and then one or more incremental migration.

1. Each NFS export to be migrated, will be made available as a dedicated NFS export of a read-only Snapshot of the actual NFS export.
> ℹ️ **Assumption:** Storage array is a: Dell PowerScale / EMC Isilon OneFS cluster
```bash
## 1. Create a snapshot
## Example: NFS export points to: /ifs/data/projects
##
isi snapshot snapshots create \
  --path=/ifs/data/projects \
  --name=MigrationSnap_20260610

## 2. Verify:
isi snapshot snapshots list
# or
isi snapshot snapshots view MigrationSnap_20260610

## 3. Access the snapshot
## Snapshots are exposed through the hidden .snapshot directory:
## 
/ifs/data/projects/.snapshot/MigrationSnap_20260610
## You can browse it directly from an NFS client if snapshot access is enabled.
```

3. This NFS export will then be mounted read-only, in either inside WSL or native on Windows on the workstation (the choice will depend upon the NFS export options)
```bash
## Example NFS mount
sudo mount -t nfs -o ro,vers=3 nfs-server:/export/path /mnt/nfs-source
```
3. Mount the Azure Data Box (NET USE) share(s) on the workstation via the 10 GbE connection
4. Initial: Perform a 'offline metadata file copy with rsync' - that will preserve the metadata of the files copied and their size/data etc..
```bash
SRC="/mnt/nfs-source/"
DEST="/mnt/cifs-dest/"
BASELINE="/mnt/cifs-dest/.baseline-manifest.tsv"

rsync -rlt \
  --no-owner --no-group \
  --omit-dir-times \
  --partial --delay-updates \
  --info=progress2,stats2 \
  "$SRC" "$DEST"

cd "$SRC"
find . -type f -printf '%P\t%s\t%T@\n' | sort > "$BASELINE"```
```
5. Incremental: Refresh the Snapshot presented from the NAS Device to be latest version
```bash
SRC="/mnt/nfs-source/"
DEST="/mnt/cifs-delta/"
BASELINE="/path/to/.baseline-manifest.tsv"
CURRENT="/tmp/current-manifest.tsv"
CHANGED="/tmp/changed-files.txt"

cd "$SRC"

find . -type f -printf '%P\t%s\t%T@\n' | sort > "$CURRENT"

comm -23 "$CURRENT" "$BASELINE" |
  cut -f1 > "$CHANGED"

rsync -rlt \
  --no-owner --no-group \
  --omit-dir-times \
  --partial --delay-updates \
  --files-from="$CHANGED" \
  "$SRC" "$DEST"
```

Repeat incremental as many times as required, with a new Azure Data Box.

> ℹ️ **PST Files**<br>
> All PST Files will be included in the copies to the Azure Data Box and will be treated as ordinary files.
>

## Destination: Azure Preparation

### Prepare Migration User Principals (user accounts)

- Create applicable accounts with the Global Reader privilege permanently assigned.
- Ideally, the following Entra ID roles, should not be required, but in case the service principal cannot be created, then the following is required.<br>
Either via PIM or Permanently assign the following roles to the applicable EIRE accounts:<br>
Role: SharePoint Administrator<br>
Role: Teams Administrator<br>
Role: Exchange Administrator<br>
Role: Microsoft 365 Migration Administrator<br>

### Prepare Migration Service Principals

The creation of the file migration service principals is outline [here](https://github.com/webstean/eire/blob/main/migration/migration%20-%20mailbox%20-%20tenant-to-tenant%20-%20destination.md)

### Prepare Azure Resources
1. Create a dedicated 'Azure Management Group' (called migration or similar)
2. Create a dedicated 'Azure subscription' (recommended for better isolation) or reuse an existing (which should be empty)
3. Move the 'Azure Subscription' under that 'migration' 'Azure Management Group' in the destination tenant's hierarchy
4. Assign EIRE as 'Owner' (recommended) or atleast 'Contributor' to the management group and/or subscription
5. If required, block destination tenant admins (Global Administrators etc..) from being able to access the management group/subscription/resource group with Azure RBAC Deny Assignments, so that only certain (EIRE/project/nominated security) individuals/service principal actual have access.
6. Create a single Azure VNet and subnets in the preferred zone
7. Create a Azure Storage Account (Preferred storage type: Azure Files, Performance: Premium, Premium Account Type: File Shars, Redunancy: LRS or higher)
8. Ensure EIRE principals (user or service) is assgied as the owner of the Storage Account.
9. Highly recommendeded: Create a Private Endpoint to this Storage Account via a dedicated subnet (private-endpoint) within the single VNet, and disabled external access to the Storage Account.
10. Record the subscription, resource group and Storage Account resource id to be given to Microsoft/Azure as the destination for the import of the Azure Data Box.

> ℹ️ **Important**<br>
> At a minimum, these steps should be performed before the Azure Data Box is ordered!
>

### Prepare Azure VM
1. Within the management group/subscription/resource group create as per above, Create a single Azure VM
2. The Azure VM will need to be install Windows Server 2022 (recommended) or Windows 11
3. Ensure the standard corporate protection (AV, EDR) are installed or altrnaitvely install Microsoft Defender (via VM extension)
4. Ensure the VM has network access to the storage account, that was created above. It's recommended, that the NIC should be in the same VNet that was created above.
5. Enusre the VM has outbound network access to the Internet via whatever applicable proxy/firewall is being utilised. EIRE does not recommend the use of a Azure NGS/VM specific firewall rules, if a suitably robust proxy/firewall solution is already in place.  
6. Ensure the new VM is available via Azure Bastion, AVD or Windows 365 (or whatever external access solution you use) to the nominated external EIRE users
7. Ensure EIRE users are granted local admin to the Azure VM
9. Ensure that SharePoint Migration tool is (installed)[this procedure](https://learn.microsoft.com/en-us/sharepointmigration/introducing-the-sharepoint-migration-tool)  

> ℹ️ **Information**<br>
> Windows Server 2022 is recommended for the best performance.<br>
> Minimal hardware configuration: 2 x vCPU, 4x vSockets per vCPU (Total of 8 vSockets), 16GB of RAM, Single 1TB (SSD) C: Drive<br>
> The recommended disk type is a single **Premium SSD v2** with ```disk-iops-read-write = 5000 & disk-mbps-read-write = 180```<br>

> ℹ️ **Recommendation**<br>
> The operating system should be installed with the all the typical corporate AV, EndPoint Protection, SIEM integration, transparent proxy (Zscaler, Netskope etc..) components.<br>
> This is to ensure that those services (AV, EDR, SIEM, proxy etc..) are active throughout the migration, providing as usual protections.

### Prepare Windows 365, AVD (VDI) etc..
1. Provide a standard AVD/VDI/Windows 365 machine to EIRE user(s)
2. Ensure that PowerShell 7.x is installed and fully enabled (if constrained mode is enabled, it must be in audit mode)
3. Ensure the following PowerShell modules are installed:
- Microsoft.Graph
- ExchangeOnline
- SharePointOnline
- PnP.PowerShell

> ℹ️ **Information**<br>
> This machine will be utilised for implementing the agreed security scheme for the SharePoint site(s) typically via PnP.PowerShell utilising scripts.

## Destination: File/PST Migration Procedures

### Objective
All the files are now available in the Azure Files (Storage Account) within the destination tenant.<br>
- The non-PSTs will need to be imported into the nominated SharePoint site (or sites)
- The PSTs can optionally be imported into Exchange Online

### Procedures

#### Uploading files into SharePoint
- Use SPMT to upload the contents of the applicable Azure Files share into the SharePoint library within a the destination SharePoint site as per the following<br>

```powershell
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string] $SourcePath,

  [Parameter(Mandatory)]
  [string] $TargetSiteUrl,

  [Parameter(Mandatory)]
  [string] $TargetLibraryName,

  [string] $TargetFolder = ""
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.SharePoint.MigrationTool.PowerShell -ErrorAction Stop

Register-SPMTMigration -SPOCredential (Get-Credential -Message "SharePoint Online admin/site admin credential") -Force -ErrorAction Stop
Add-SPMTTask -FileShareSource $SourcePath -TargetSiteUrl $TargetSiteUrl -TargetList $TargetLibraryName -TargetListRelativePath $TargetFolder -ErrorAction Stop
Start-SPMTMigration -ErrorAction Stop
```

#### Uploading PSTs into Exchange Online (if required)

- Use the PST Import Service (via the Purview Portal) to create jobs to import PSTS into the destination Exchange Online
- The precise procedure is given [here - English](https://learn.microsoft.com/en-US/purview/pst-import-network-upload) or [here - Japanese](https://learn.microsoft.com/jp-JA/purview/pst-import-network-upload)  

#### Implement agreed security model
- Leverage PowerShell.PnP powershell modules to create the agreed Role-Based access controls in the destination.
- Adjust SharePoint Libraries to provide the best end-user experience.
- Provide end-user facing dcoumentation to help users find their files post-migration.

