NAS via Migration Maager (with Windows Agents)
Mailbox via native tooling



1. POC Environment
2. Migration Procedure
3. Backup Plan
4. Testing & Verfication

Once Microsoft Migration Manager has been deployed, including the agents it can be automated as follows:

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
