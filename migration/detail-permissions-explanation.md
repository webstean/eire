
We have developed numerous automation workflows to ensure the mailbox migration goes as smoothly as possible. This include comprehensive and continuous checking, validation and analysis of isuses. 

Our approach needs the following permissons in both the source and destination tenants via Entra ID multi-tenant app, that is created within the destination tenant and consented to by the source tenant.

**API: Office 365 Exchange Online**<br>
| Permission | Type | Critical | Purpose | Justification
|---|---|:---|:--|:--|
| Mailbox.Migration | Application | Essential | Migrate mailboxes | This is a recent additiona, that provide just enough access for the Mailbox Migration.
| Exchange.ManageAsApp | Application | Essential | Access Exchange as an application. | This permission is needed to logon to Exchange, as an Entra ID Service Principal and is a Microsoft requirement as per [here](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps)
| PeopleSettings.Read.All | Application | Desirable | Read (but not change) Exchage user settings. | Historically, we have had issues retreving mailbox information that is used for tracking the migration. These issues were resolved by user this permission.
| SMTP.SendAsApp | Application | Desirable | Send email for alerting/logging | Our automaation (typically every 10 minutes) will detect erorrs or issues and will create emails to the project teams. This is allow immediate response, but to also serve as an audit trail. We have previously used this, with service management systems, such as Service Now to generate tickets for relevant team, when necessary. Despite its name this permission does not allow the sending of email from any mailbox, this capability was removed many years ago and is this access is now further controlled via [this link](https://learn.microsoft.com/en-us/exchange/client-developer/legacy-protocols/smtp-app-rbac-onboarding)

**API: Microsoft Graph**<br>
| Permission | Type | Critical | Purpose | Justification
|---|---|:---|:--|:--|
| User.Read.All | Application | Desrable | Read (but not change) user information. | This is used to retrieve and confirm UPN (User Principal Name) as part of onboarding mailboxes into the migration. We also uses this permission to perform a variety of quality checks to ensure the account is ready for migration.
| Application.Read.All | Application | Desirable | Read (but not change) application information. | We uses this so the application, can read its own application registration / service principal information, which we have found to be important in troubleshooting any issues.
| Organization.Read.All | Application | Desirable |  Read (but not change) the Exchange orgnanization settings. | We have scripting design to check if configuration changes are made that will impact the migration. We do configuration check, typically once every 3 hours. And if the configuration changes, we provide alerting (typically via email) to imform the relevant members of the project team.
| Sites.Read.All | Application | No Longer Required | Read (but not change) sites. | Historically, we have used SharePoint sites with dedicated SharePoint lists , to record migration parameters and record migration progression as a method to centrally communciation to multiple stakeholders. Most of this functionality is no longer activately being used (or developed), but can be (re)enabled depending upon the project needs. 
| Group.Read.All<br>GroupMember.Read.All | Application | Desirable | Read (but not change) group information (for permission mapping). | We identity users targeted for migration via membership of a group, this permission allow use to identity that membership. Typically the source tenant will create the group, and we'll need to be read it, obtain its membership to add them to the migration batch (or list)
| Mail.Send | Application | Desirable | Send but cannot Read email | This is a more modern way of sendiing emails from scripts, that depending upon the tenant configuration, is sometime more optimal. As per above, we send email for status tracking throughout migration and providing an audit trail
| Polcy.Read.All | Application | Desirable | Read (but not change) policies | Our automation provides comprehensive messaging around errors and by being able to retreive policiy information (via this permission) we can typically determine the 'root cause' far faster than manual methods.

## Analysis

Going with just the 'essential' permissions, will mean the migration will needs to be undertaken 'blind'. We won't be able to use any of our tooling to properly monitoring the migration and we'll lack the ability to provide audit and comprehensive logging. We won't be confident that the migration is successful or otherwise.

Having undertaken numerous such migrations betwen large orgnaisations before, we have found our approach to be robust and can deliver on the desired outcomes.

Without it we cannot technically guarantee the outcome, since we will only have a primitive level of information and no audit trail.

## Reporting Examples

### Minimal (default Microsoft)

One view per mailbox, that then will need to be manually mapped to provide an overview of the whole migration.
```txt
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

### Comprehsnive (our Soluton)

```txt
Migration                      : TeantA to Teant B
MigrationType                  : ExchangeRemoteMove
Status                         : Completed
SourceTenant                   : 3f2c1c0a-6bfa-4a4a-9c5d-8a6c9c1e1234
DestinationTenant              : ab361e78-0baa-8921-67c2-45212aae78d1
NumbeofBatches                 : 3
BatchIds                       : MigrationBatch01, MigrationBatch02, MigrationFinal
TotalMailboxes                 : 722
TotalMailboxSize               : 958 GB
TotalItemsSynced               : 1157331
TotalItemsSkipped              : 0

Batch                          : MigeaitonBatch01
SourceGroup                    : c40d992f-c372-44a4-ac7c-06f40e9c3404
SourceGroupMembers             : 501
LargestMailbox                 : 87 GB
SmallestMailbox                : 0 GB

Batch                          : MigeaitonBatch02
SourceGroup                    : 54a9a25b-9090-40db-a8d4-efbbffea9e1d
SourceGroupMembers             : 214
LargestMailbox                 : 87 GB
SmallestMailbox                : 0 GB

Batch                          : MigeaitonFinal
SourceGroup                    : 5d0ef2da-006d-4689-9c6c-51c718af9419
SourceGroupMembers             : 7
LargestMailbox                 : 20 GB
SmallestMailbox                : 0 GB

Mailbox Mapping                : usera@source.com.au -> usera@destination.com.au SYNCED
                               : userb@source.com.au -> userb@destination.com.au SYNCED
                               : userc@source.com.au -> userc@destination.com.au SYNCED
                               : userd@source.com.au -> userd@destination.com.au SYNCED
                               : usere@source.com.au -> usere@destination.com.au SYNCED
                               : userf@source.com.au -> userf@destination.com.au SYNCED
                                ...

Mailbox Completion             : usera@source.com.au -> usera@destination.com.au COMPLETED
                               : userb@source.com.au -> userb@destination.com.au COMPLETED
                               : userc@source.com.au -> userc@destination.com.au COMPLETED
                               : userd@source.com.au -> userd@destination.com.au COMPLETED
                               : usere@source.com.au -> usere@destination.com.au COMPLETED
                               : userf@source.com.au -> userf@destination.com.au COMPLETED
                                ...

HealthCheckSource              : 601
HealthCheckDestination         : 603

HealthSource                   : No issues found!
HealthDesitnation              : No issues found!

ComnfigurationSource           : No issues found!
ComnfigurationDestination      : No issues found!

VerificationCheckSource        : No issies found!
VerificationCheckDestination   : No issies found!

```
plus mailbox migrations details for each mailbox migrated, designed for audit purposes.





