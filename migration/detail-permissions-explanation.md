
We have developed numerous automation workflows to ensure the mailbox migration goes as smoothly as possible. This include comprehensive and continuous checking, validation and analysis of isuses. 

Our approach needs the following permissons in both the source and destination tenants via Entra ID multi-tenant app, that is created within the destination tenant and consented to by the source tenant.

**API: Office 365 Exchange Online**<br>
| Permission | Type | Critical | Purpose | Justification
|---|---|:---|:--|:--|
| Mailbox.Migration | Application | Essential | Migrate mailboxes | This is a recent additiona, that provide just enough access for the Mailbox Migration.
| Exchange.ManageAsApp | Application | Essential | Access Exchange as an application. | This permission is needed to logon to Exchange, as an Entra ID Service Principal and is a Microsoft requirement as per [here](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps)
| PeopleSettings.Read.All | Application | Desirable | Read (but not change) Exchage user settings. | Historically, we have had issues retreving mailbox information that is used for tracking the migration. These issues were resolved by user this permission.
| SMTP.SendAsApp | Application | Recommended | Purpose | Our scripts, allow periodical (typically every 10 minutes) the creation of status and any error emails to the project teams. This is allow immediate response, but to also serve as an audit trail. We have previously used this, with service management systems, such as Service Now to generate tickets for relevant team, when necessary. Despite its name this permission does not allow the sending of email from any mailbox, this capability was removed many years ago and is this access is now further controlled via ()this}[]this tihg

**API: Microsoft Graph**<br>
| Permission | Type | Critical | Purpose | Justification
|---|---|:---|:--|:--|
| User.Read.All | Application | Recommended | Read (but not change) user information. | This is used to retrieve and confirm UPN (User Principal Name) as part of onboarding mailboxes into the migration. We also uses this permission to perform a variety of quality checks to ensure the account is ready for migration.
| Application.Read.All | Application | Recommended | Read (but not change) application information. | We uses this so the application, can read its own application registration / service principal information, which we have found to be important in troubleshooting any issues.
| Organization.Read.All | Application | Recommended |  Read (but not change) the Exchange orgnanization settings. | We have scripting design to check if configuration changes are made that will impact the migration. We do configuration check, typically once every 3 hours. And if the configuration changes, we provide alerting (typically via email) to imform the relevant members of the project team.
| Sites.Read.All | Application | No Longer Required | Read (but not change) sites. | Historically, we have used SharePoint sites with dedicated SharePoint lists , to record migration parameters and record migration progression as a method to centrally communciation to multiple stakeholders. Most of this functionality is no longer activately being used (or developed), but can be (re)enabled depending upon the project needs. 
| Group.Read.All<br>GroupMember.Read.All | Application | Recommended | Read (but not change) group information (for permission mapping). | We identity users targeted for migration via membership of a group, this permission allow use to identity that membership. Typically the source tenant will create the group, and we'll need to be read it, obtain its membership to add them to the migration batch (or lsit)
| Mail.Send | Application | Recommended | Send but cannot Read email | This is a more modern way of sendiing emails from scripts, that depending upon the tenant configuration, is sometime more optimal. As per above, we send email for status tracking throughout migration and providing an audit trail
| Polcy.Read.All | Application | Recommended | Read (but not change) policies | Our automation provides comprehensive messaging around errors and by being able to retreive policiy information (via this permission) we can typically determine the 'root cause' far faster than manual methods.

## Analysis

Going with just the 'essential' permissions, will mean the migration will needs to be undertaken 'blind'. We won't be able to use any of our tooling to properly monitoring the migration and we'll lack the ability to provide audit and comprehensive logging. We won't be confident that the migration is successful or otherwise.

Having undertaken numerous such migrations betwen large orgnaisations before, we have found our approach to be robust and can deliver on the desired outcomes.

Without it we cannot technically guarantee the outcome, since we will only have a primitive level of information and no audit trail.

## Reporting Examples

### Minimal








