# Exchange Online Tenant Discovery and Configuration Export Runbook (Manual Collection)

## Purpose

This document provides a comprehensive procedure for manually collecting Exchange Online configuration information when PowerShell access is unavailable.

The goal is to produce a complete tenant configuration record suitable for:

* Tenant-to-tenant migrations
* Disaster recovery documentation
* Operational handover
* Security reviews
* Configuration audits

---

# Evidence Collection Standards

For every configuration area:

* Capture screenshots of configuration pages.
* Export CSV files where available.
* Record notes for settings that cannot be exported.
* Save evidence using a structured folder hierarchy.

Recommended structure:

```text
Exchange-Discovery
├── 01-Tenant
├── 02-Organization
├── 03-MailFlow
├── 04-Recipients
├── 05-Policies
├── 06-Defender
├── 07-Purview
├── 08-Permissions
├── 09-Hybrid
├── 10-PublicFolders
└── Notes.md
```

---

# 1. Tenant Information

## Microsoft 365 Admin Center

Navigate to:

```text
Admin Center
└── Settings
    └── Domains
```

Capture:

* Tenant name
* Primary domain
* Accepted domains
* Default domain
* Domain verification status

Navigate to:

```text
Billing
└── Licenses
```

Capture:

* Exchange Online licensing
* Microsoft 365 licensing
* Add-on licenses

Evidence:

* Domain screenshots
* License screenshots

---

# 2. Exchange Organization Settings

## Exchange Admin Center

Navigate to:

```text
Settings
```

Capture:

### Mail Flow Settings

Document:

* SMTP AUTH configuration
* External sender controls
* MailTips configuration

### Sharing Settings

Document:

* Organization sharing settings
* Calendar sharing defaults

### Mobile Device Settings

Document:

* Mobile device access rules
* Device management configuration

### Modern Authentication

Document:

* Modern authentication status
* Basic authentication restrictions

Evidence:

* Screenshot each settings page

---

# 3. Mail Flow Configuration

## Exchange Admin Center

Navigate to:

```text
Mail Flow
```

---

## Rules

Navigate:

```text
Mail Flow
└── Rules
```

Capture for every rule:

* Name
* Priority
* Enabled status
* Conditions
* Exceptions
* Actions

Evidence:

* Rule list screenshot
* Individual rule screenshots

---

## Connectors

Navigate:

```text
Mail Flow
└── Connectors
```

Capture:

### Inbound Connectors

* Name
* Source
* TLS requirements
* Restrictions

### Outbound Connectors

* Name
* Destination
* Smart hosts
* TLS requirements

Evidence:

* Connector screenshots

---

## Accepted Domains

Navigate:

```text
Mail Flow
└── Accepted Domains
```

Capture:

* Domain name
* Domain type

  * Authoritative
  * Internal Relay

---

## Remote Domains

Navigate:

```text
Mail Flow
└── Remote Domains
```

Capture:

* Domain
* Mail flow settings
* Auto-reply settings

---

# 4. Recipients

Navigate:

```text
Recipients
```

---

## User Mailboxes

Capture:

* Display Name
* Primary SMTP Address
* Aliases
* Archive Enabled
* Retention Policy
* Mailbox Size Limits

---

## Shared Mailboxes

Capture:

* Mailbox Name
* Email Addresses
* Delegates
* Full Access Permissions
* Send As Permissions
* Send On Behalf Permissions

---

## Room Mailboxes

Capture:

* Name
* Capacity
* Booking Settings

---

## Equipment Mailboxes

Capture:

* Name
* Booking Settings

---

## Distribution Groups

Capture:

* Group Name
* Email Address
* Owners
* Members

---

## Dynamic Distribution Groups

Capture:

* Group Name
* Recipient Filters

---

## Mail-Enabled Security Groups

Capture:

* Group Name
* Membership

---

## Microsoft 365 Groups

Capture:

* Name
* Email Address
* Owners
* Members

---

# 5. Mailbox and Client Policies

Navigate:

```text
Recipients
Policies
Roles
```

---

## Outlook on the Web Policies

Capture:

* Policy name
* Attachments settings
* Offline access settings
* Feature restrictions

---

## ActiveSync Policies

Capture:

* PIN requirements
* Device encryption requirements
* Device wipe settings

---

## Authentication Policies

Capture:

* Legacy authentication restrictions
* Authentication protocol controls

---

## Address Book Policies

Capture:

* Policy definitions
* Assigned users

---

## Email Address Policies

Capture:

* Address templates
* Recipient filters

---

## Sharing Policies

Capture:

* Policy definitions
* External sharing permissions

---

# 6. Microsoft Defender for Office 365

Navigate to:

```text
Microsoft Defender Portal
```

Email & Collaboration → Policies & Rules

---

## Anti-Spam Policies

Capture:

* Policy names
* Thresholds
* Actions
* Scope

---

## Anti-Phishing Policies

Capture:

* User impersonation settings
* Domain impersonation settings
* Mailbox intelligence

---

## Safe Links Policies

Capture:

* Enabled status
* Scope
* Tracking settings

---

## Safe Attachments Policies

Capture:

* Scan action
* Scope
* Detonation settings

---

## Tenant Allow / Block List

Capture:

### Allowed

* Senders
* Domains
* URLs

### Blocked

* Senders
* Domains
* URLs

---

# 7. Microsoft Purview Compliance Configuration

Navigate to:

```text
Microsoft Purview Portal
```

---

## Retention Policies

Capture:

* Policy name
* Locations
* Retention duration
* Retention actions

---

## Retention Labels

Capture:

* Label name
* Retention period
* Disposition settings

---

## DLP Policies

Capture:

* Policy names
* Locations
* Conditions
* Actions

---

## Records Management

Capture:

* Record labels
* File plans
* Disposition review settings

---

## eDiscovery

Capture:

* Existing cases
* Custodians
* Hold settings

---

# 8. Permissions and Administration

Navigate:

```text
Exchange Admin Center
└── Roles
```

---

## Administrative Role Groups

Capture:

### Organization Management

* Members

### Recipient Management

* Members

### Compliance Management

* Members

### Custom Role Groups

* Members
* Assigned Roles

---

## Administrative Assignments

Document:

* Delegated administration
* Third-party administration

---

# 9. Mailbox Delegation Review

Review:

* Executive mailboxes
* Shared mailboxes
* Service accounts

Capture:

### Full Access

| Mailbox | User |
| ------- | ---- |
|         |      |

### Send As

| Mailbox | User |
| ------- | ---- |
|         |      |

### Send On Behalf

| Mailbox | User |
| ------- | ---- |
|         |      |

---

# 10. Hybrid Configuration

If Hybrid Exchange is present:

Capture:

* Exchange Server versions
* Hybrid configuration
* Mail routing
* Connectors
* Federation settings

Review:

```text
Exchange Admin Center
└── Hybrid
```

Capture screenshots of all Hybrid settings.

---

# 11. Journaling and Archiving

Capture:

## Journal Rules

* Rule names
* Targets
* Conditions

## Third-Party Services

Document:

* Mimecast
* Proofpoint
* Barracuda
* Symantec
* Other gateways

Capture:

* Routing configuration
* Connectors
* Journal destinations

---

# 12. Public Folders

If Public Folders are enabled:

Navigate:

```text
Public Folders
```

Capture:

* Folder hierarchy
* Mail-enabled folders
* Permissions

---

# Migration-Critical Configuration Checklist

The following items must be documented for any migration or tenant rebuild.

## Core Exchange

* [ ] Accepted Domains
* [ ] Remote Domains
* [ ] Connectors
* [ ] Transport Rules

## Recipients

* [ ] User Mailboxes
* [ ] Shared Mailboxes
* [ ] Room Mailboxes
* [ ] Equipment Mailboxes
* [ ] Distribution Groups
* [ ] Dynamic Distribution Groups
* [ ] Mail-Enabled Security Groups
* [ ] Microsoft 365 Groups

## Mailbox Permissions

* [ ] Full Access
* [ ] Send As
* [ ] Send On Behalf

## Security

* [ ] Anti-Spam Policies
* [ ] Anti-Phishing Policies
* [ ] Safe Links Policies
* [ ] Safe Attachments Policies
* [ ] Tenant Allow/Block List

## Compliance

* [ ] Retention Policies
* [ ] Retention Labels
* [ ] DLP Policies
* [ ] Records Management

## Administration

* [ ] Role Groups
* [ ] Administrative Assignments

## Hybrid

* [ ] Hybrid Configuration
* [ ] Exchange Servers
* [ ] Federation

## Legacy Features

* [ ] Public Folders
* [ ] Journal Rules

---

# Deliverables

The final package should contain:

```text
Exchange-Discovery
├── Screenshots
├── CSV Exports
├── Configuration Notes
├── Delegation Matrix
├── Migration Checklist
└── Final Discovery Report
```

Completion of this runbook provides a comprehensive manual inventory of Exchange Online tenant configuration suitable for migration planning, operational support, disaster recovery documentation, and security review.
