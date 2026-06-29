


**API: Office 365 Exchange Online**<br>
| Permission | Type | Critical | Purpose | Justification
|---|---|:---|:--|:--|
| Mailbox.Migration | Application | Essential | Migrate mailboxes, minimal permision to enable migration. | xx
| Exchange.ManageAsApp | Application | Essential | Access Exchange as an application. | This permission is needed to logon to Exchange, as an Entra ID Service Principal and is a Microsoft requirement as per (this)[https://cnn.com]
| Organization.Read.All | Application | Recommended |  Read (but not change) the Exchange orgnanization settings. | We have scripting design to check if configuration changes are made that will impact the migration. We do configuration check, typically once every 3 hours. And if the configuration changes, we provide alterting (typically via email) to imform the relevant members of the project team.
| PeopleSettings.Read.All | Application | Recommdended | Read (but not change) Exchage user settings. | Allows access 
| SMTP.SendAsApp | Application | Recommended | Purpose | Our scripts, allow periodical (typically every 10 minutes) the creation of status and any error emails to the project teams. This is allow immediate response, but to also serve as an audit trail. We have previously used this, with service management systems, such as Service Now to generate tickets for relevant team, when necessary. Despite its name this permission does not allow the sending of email from any mailbox, this capability was removed many years ago and is this access is now further controlled via ()this}[]this tihg

**API: Microsoft Graph**<br>
| Permission | Type | Critical | Purpose | Justification
|---|---|:---|:--|:--|
| User.Read.All | Application | Essential | Read (but not change) user information. | x
| Application.Read.All | Application | Essential | Read (but not change) application information. | x
| Organization.Read.All | Application | Essential | Read (but not change) organisation information. | x
| Sites.Read.All | Application | No Longer Required | Read (but not change) sites. | Historically, we have used SharePoint sites with dedicated SharePoint lists , to record migration parameters and record migration progression as a method to centrally communciation to multiple stakeholders. Most of this functionality is no longer activately being used (or developed), but can be (re)enabled depending upon the project needs. 
| Group.Read.All | Application | Essential | Read (but not change) group information (for permission mapping). | x
| GroupMember.Read.All | Application | Essential | Read (but not change) group membership (for permission mapping). | x 
| Mail.Send | Application | Recommended | Send but cannot Read email | This is thre more modern way of sendiing emails from scripts, that depending upon the tenant configuration, is sometime more optimal. Send email for status tracking throughout migration (cannot read emails). | x
| Polcy.Read.All | Application | Recommended | Our scripting can provide comppreangive messaging around errors, by being able to retreive policiy to determine the underlying source of tpyically erros, so they can resolved in a timely fashion.

