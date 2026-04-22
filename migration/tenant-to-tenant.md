# Mailbox Migration Tenant to Tenant

## Introduction

This document describes (in detail) how the mailbox migration will be performed.

## Permissions

The following permission are required in both the source and destination tenants:

* Mailbox.Migration [Application]
* User.Read.All [Application]
* Organization.Read.All [Application]

via an Application Registration / Enterprise Application 

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

```powershell
Complete-MigrationBatch -Identity "Batch1"
```

## Throughput

Theortical maximum is 10TB per day, but this is not real world.

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
Identity                       : user@contoso.com
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


