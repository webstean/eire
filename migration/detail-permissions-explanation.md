


**API: Office 365 Exchange Online**<br>
| Permission | Type | Critical | Purpose | Justification
|---|---|:---|:--|:--|
| Mailbox.Migration | Application | Essential | Migrate mailboxes, minimal permision to enable migration. | xx
| Exchange.ManageAsApp | Application | Essential | Access Exchange as an application. | This permission is needed to logon to Exchange, as a Service Principal and is a Microsoft requirement as per (this)[https://cnn.com]
| Organization.Read.All | Application | Recommended |  Read (but not change) the Exchange orgnanization settings. | We hacve scripting design to check if configuration changes are made that will impact the migration. We do configuration check, typically aorund once every 3 hours. And if the configuration changes, we provide alterting (via email) to imform the project team.
| PeopleSettings.Read.All | Application | Essential | Read (but not change) Exchage user settings. |  xx
| SMTP.SendAsApp | Application | Recommended | Purpose | Our scripts, allow periodical (typically every 10 minutes) the creation of status and any error emails to the project teams. This is allow immediate response, but to also serve as an audit trail. We have previously used this, with service management systems, such as Service Now to generate tickets for relevant team, when necessary. Despite its name this permission does not allow the sending of email from any mailbox, this capability was removed many years ago and is this access is now further controlled via ()this}[]this tihg

**API: Microsoft Graph**<br>
| Permission | Type | Critical | Purpose | Justification
|---|---|:---|:--|
| User.Read.All | Application | Essential | Read (but not change) user information. |
| Application.Read.All | Application | Essential | Read (but not change) application information. |
| Organization.Read.All | Application | Essential | Read (but not change) organisation information. |
| Group.Read.All | Application | Essential | Read (but not change) group information (for permission mapping). |
| GroupMember.Read.All | Application | Essential | Read (but not change) group membership (for permission mapping). |  
| Mail.Send | Application | Recommended | Send email for status tracking throughout migration (cannot read emails). |

