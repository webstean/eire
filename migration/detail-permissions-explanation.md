
# Our Approach to Mailbox Migration

We have developed multiple automation workflows to make mailbox migrations as smooth, predictable, and low risk as possible. These workflows include continuous checks, validation, and built-in analysis to detect and explain issues early.

Our approach requires the permissions listed below in both the source and destination tenants. Access is provided through a Microsoft Entra ID multi-tenant application that is created in the destination tenant and then consented to in the source tenant.

## Technical Approach

Application Object: Defines the application in its home tenant. It acts as the template for how tokens are issued and what API access the app can request.

Service Principal Object: Represents that application inside each tenant. It is the identity that actually receives permissions and is used for authentication and authorization.

In this model, the application object is created in the destination tenant. The source tenant then grants consent to the same application so it can operate across both tenants.

The following permissions are used by the automation and reporting workflows.

## **API: Exchange Online**

| Permission | Type | Critical | Purpose | Justification |
|---|---|:---|:--|:--|
| **Mailbox.Migration** | Application | Mandatory | Migrate mailboxes | This is the core migration permission and is scoped to mailbox migration operations. It provides the minimum level of access needed to perform migration actions. |
| **Exchange.ManageAsApp** | Application | Mandatory | Access Exchange as an application | This permission is required to sign in to Exchange Online using an Entra ID service principal. Microsoft documents this requirement [here](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps). |
| PeopleSettings.Read.All | Application | Desirable | Read (but not modify) Exchange user settings | We use this to read mailbox-related user settings used by validation and migration tracking. In previous projects, this access helped resolve data retrieval gaps that affected monitoring accuracy. |
| SMTP.SendAsApp | Application | Desirable | Send email for alerts and logging | Our automation runs frequently (typically every 10 minutes) and generates notifications for issues, warnings, and milestones. This supports faster operational response and creates an audit trail for governance. In some engagements, these notifications also integrate with service management tooling such as ServiceNow for ticketing. Despite the name, this permission does not grant unrestricted sending as any mailbox; modern controls are documented [here](https://learn.microsoft.com/en-us/exchange/client-developer/legacy-protocols/smtp-app-rbac-onboarding). |

## **API: Microsoft Graph**

| Permission | Type | Critical | Purpose | Justification |
|---|---|:---|:--|:--|
| **User.Read.All** | Application | Mandatory | Read (but not modify) user information | Used to retrieve and verify UPNs (User Principal Names) when onboarding mailboxes into migration batches. It also supports readiness checks to confirm account state before migration starts. |
| Application.Read.All | Application | Mandatory | Read (but not modify) application information | Allows the app to read application and service principal metadata. This is useful for diagnostics and troubleshooting authentication or consent issues. |
| Organization.Read.All | Application | Desirable | Read (but not modify) organization settings | Our scripts periodically check organization-level settings that can affect migration behavior (typically every 3 hours). If a relevant configuration changes, the system sends an alert to the project team. |
| Sites.Read.All | Application | No Longer Required | Read (but not modify) SharePoint sites | Historically used when SharePoint lists were the central coordination mechanism for migration tracking and parameters. Most of that functionality is now inactive, but can be re-enabled if required by project scope. |
| Group.Read.All<br>GroupMember.Read.All | Application | Desirable | Read (but not modify) groups and membership for migration scoping | We commonly target users through security or Microsoft 365 group membership. These permissions let the automation read the source group and build migration batches from its members. |
| Mail.Send | Application | Desirable | Send email without mailbox read access | This is a modern Graph-based method for sending operational notifications. Depending on tenant controls, it can be more reliable than SMTP-based approaches for automation alerts and audit messaging. |
| Policy.Read.All | Application | Desirable | Read (but not modify) policy configuration | Enables policy-aware diagnostics. By reading policy configuration, automation can identify likely root causes more quickly than manual investigation alone. |

## Analysis

If only the essential permissions are granted, migration can still proceed, but operational visibility is significantly reduced. In practical terms, the project would run with minimal telemetry and limited automated assurance.

Without the desirable read and notification permissions:

- Health checks are less informative.
- Configuration drift is harder to detect early.
- Root-cause analysis takes longer.
- Alerting and audit evidence are weaker.

Based on our experience in large tenant-to-tenant migrations, the broader permission set provides materially better governance, faster issue resolution, and more reliable reporting to stakeholders.

In short, essential permissions enable execution, while the full recommended set enables control, confidence, and auditability.

## Reporting Examples

### Minimal (default Microsoft)

Output is generally produced at the end of migration, with limited ongoing alerting.

Mailbox mapping is often maintained manually in CSV files, which can introduce inconsistencies over time. We prefer Entra ID group-driven targeting for stronger control and repeatability.

The output is primarily mailbox-by-mailbox, so building a whole-project view often requires additional manual consolidation.

```powershell
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

### Comprehensive (our Solution)

Our reporting model combines migration progress, pre-flight checks, and post-run verification into one operational view. It includes batch-level summaries, mailbox-level status, dependency checks, and environment health signals.

This enables near-real-time decision making during execution and improves audit readiness after completion.

```powershell
Migration                      : TenantA to Tenant B
MigrationType                  : ExchangeRemoteMove
Status                         : Completed
SourceTenant                   : 3f2c1c0a-6bfa-4a4a-9c5d-8a6c9c1e1234
DestinationTenant              : ab361e78-0baa-8921-67c2-45212aae78d1
NumberofBatches                : 3
BatchIds                       : MigrationBatch01, MigrationBatch02, MigrationFinal
TotalMailboxes                 : 722
TotalMailboxSize               : 958 GB
TotalItemsSynced               : 1157331
TotalItemsSkipped              : 0

Batch                          : MigrationBatch01
SourceGroup                    : c40d992f-c372-44a4-ac7c-06f40e9c3404
SourceGroupMembers             : 501
LargestMailbox                 : 87 GB
SmallestMailbox                : 0 GB

Batch                          : MigrationBatch02
SourceGroup                    : 54a9a25b-9090-40db-a8d4-efbbffea9e1d
SourceGroupMembers             : 214
LargestMailbox                 : 87 GB
SmallestMailbox                : 0 GB

Batch                          : MigrationFinal
SourceGroup                    : 5d0ef2da-006d-4689-9c6c-51c718af9419
SourceGroupMembers             : 7
LargestMailbox                 : 20 GB
SmallestMailbox                : 0 GB

Mailbox Mapping                : usera@source.com.au -> usera@destination.com.au SYNCED [🔴 API Permissions (Source):User.Read.All, User.Group.All, User.GroupMember.All]
                               : userb@source.com.au -> userb@destination.com.au SYNCED [🔴 API Permissions: Mailbox.Migration]
                               : userc@source.com.au -> userc@destination.com.au SYNCED
                               : userd@source.com.au -> userd@destination.com.au SYNCED
                               : usere@source.com.au -> usere@destination.com.au SYNCED
                               : userf@source.com.au -> userf@destination.com.au SYNCED
                                ...

Mailbox Completion             : usera@source.com.au -> usera@destination.com.au COMPLETED [🔴 API Permissions: Mailbox.Migration]
                               : userb@source.com.au -> userb@destination.com.au COMPLETED
                               : userc@source.com.au -> userc@destination.com.au COMPLETED
                               : userd@source.com.au -> userd@destination.com.au COMPLETED
                               : usere@source.com.au -> usere@destination.com.au COMPLETED
                               : userf@source.com.au -> userf@destination.com.au COMPLETED
                                ...


HealthCheckSource              : 601 [🔴 API Permissions (Source):Application.Read.All, Organization.Read.All, Policy.Read.All]
HealthCheckDestination         : 603 [🔴 API Permissions (Destination):Application.Read.All, Organization.Read.All, Policy.Read.All]

HealthSource                   : No issues found! [🔴 API Permissions (Source):Application.Read.All, Organization.Read.All, Policy.Read.All]
HealthDestination              : No issues found! [🔴 API Permissions (Destination):Application.Read.All, Organization.Read.All, Policy.Read.All]

ConfigurationSource            : No issues found! [🔴 API Permissions (Source):Organization.Read.All]
ConfigurationDestination       : No issues found! [🔴 API Permissions (Destination):Organization.Read.All]

VerificationCheckSource        : No issues found! [🔴 API Permissions (Source):Application.Read.All, Organization.Read.All, Policy.Read.All]
VerificationCheckDestination   : No issues found! [🔴 API Permissions (Destination):Application.Read.All, Organization.Read.All, Policy.Read.All]

```

In addition, detailed per-mailbox migration records are retained for audit purposes, including key timestamps, outcome state, and any policy or permission-related warnings observed during processing.

```powershell
...

IdentityDestination            : desta@destination.com
SourceMailboxId                : 3f2c1c0a-6bfa-4a4a-9c5d-8a6c9c1e1234
DestinationMailboxId           : bef3431a-56a1-be32-843c-7432102cea3c
SourceMailboxUPN               : sourcea@source.com
DestinationMailboxUPN          : desta@destination.com
MigrationStatus                : Completed
MailboxSize                    : 4.45 GB (3,701,234,567 bytes)
ItemsMigrated                  : 23153
ItemsSkipped                   : 0
ItemsErrored                   : 0

SourceNumberofFolders          : 71
DestNumberofFolders            : 71
SourceFolderCheck (SHA-256)    : b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
DestFolderCheck (SHA-256)      : b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
Completed                      : 22/04/2026 10:12:45 AM

Signed Off                     : Project Team 23/04/2026 09:01:00 AM

COMPLETED                      : sourcea@source.com -> desta@destination.com (desta@destination.com)

.... Next Mailbox
```

Final reports are typically provided as secured PDFs (password- or certificate-protected), depending on customer governance requirements.
