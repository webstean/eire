# Microsoft 365 Tenant Snapshot Script — Deep Technical Breakdown

## Overview

This document provides a **detailed, engineering-grade explanation** of a PowerShell-based Microsoft 365 tenant snapshot script.

The script is designed to extract configuration across multiple Microsoft 365 workloads and persist the results as structured JSON for inspection, auditing, and potential version control.

---

## Architecture Summary

The script follows a **fan-out collection model**:

1. Authenticate to each workload independently
2. Execute scoped collectors per workload
3. Persist results to structured JSON
4. Record execution outcomes and failures

---

## Permissions

This script will request the following permissions, which the administrator will need to explicity consent to

- Organization.Read.All
- Directory.Read.All
- Domain.Read.All
- Policy.Read.All
- User.Read.All
- Group.Read.All
- Application.Read.All
- RoleManagement.Read.Directory
- AuditLog.Read.All

Note: All permissions are READ-ONLY. This script does not make any changes.

It is recommended, this script by run by the Global Administrator, so the consents can be authorised.
Running via Global Reader, will only work if the consent have been already authorised by the Global Administrator.

---

## Output Layout

```
m365-tenant-snapshot-<timestamp>/
├── graph/
├── exchange/
├── teams/
├── sharepoint/
└── meta/
```

### Graph (Identity + Policy Plane)

Contains identity, access, and policy data.

### Exchange

Contains messaging configuration and policies.

### Teams

Contains tenant-wide Teams configuration.

### SharePoint

Contains tenant settings and site summaries.

### Meta

Execution diagnostics and tracking.

---

## Execution Flow

### 1. Initialization

- Enforces strict execution:
  - `Set-StrictMode -Version Latest`
  - `$ErrorActionPreference = 'Stop'`
- Creates output structure
- Initializes tracking collections:
  - manifest (success/failure)
  - errors (exception details)

---

### 2. Connection Layer

Each workload is connected independently.

#### Microsoft Graph

Supports:

- Delegated auth (interactive)
- App-only auth (certificate-based)

Used for:

- Identity
- Policy
- Core tenant objects

---

#### Exchange Online

Provides:

- Organization configuration
- Mail flow
- Retention

---

#### Microsoft Teams

Provides:

- Tenant configuration
- Federation
- Licensing state

---

#### SharePoint Online

Admin endpoint derived dynamically:

```
https://<tenant>-admin.sharepoint.com
```

---

## Graph Collection Details

### Core Directory Objects

Collected via Graph SDK:

- Organization
- Domains
- Users
- Groups
- Applications
- Service Principals
- Directory Roles
- Administrative Units

These represent the **identity backbone** of the tenant.

---

## Conditional Access Export Strategy

### Files Generated

```
conditionalAccessPolicies.json
conditionalAccessPolicies.index.json
conditional-access-policies/
```

### Design

- Full export → complete dataset
- Index → quick lookup + metadata
- Per-object files → diff-friendly

### Index Fields

- id
- displayName
- state
- createdDateTime
- modifiedDateTime
- fileName

### Rationale

This design enables:

- Git-based change tracking
- Human-readable diffs
- Policy-level inspection

---

## Named Locations

Captured using identical pattern:

- Collection
- Index
- Per-object export

Includes:

- IP ranges
- Country mappings
- Trust flags

---

## Authentication Strength Policies

Also follows same pattern.

Captures:

- MFA requirements
- phishing-resistant constraints

---

## Additional Graph Policies

- Authorization policy
- Security defaults enforcement
- Authentication methods policy

---

## Role Management

- Role definitions
- Role assignments

Used for:

- RBAC analysis
- Privileged access review

---

## Exchange Online Coverage

Exports:

- OrganizationConfig
- AcceptedDomains
- RemoteDomains
- TransportConfig
- MailboxPlans
- RetentionPolicies
- SharingPolicies
- OwaMailboxPolicies
- OrganizationRelationships

---

## Teams Coverage

Exports:

- Tenant configuration
- Federation configuration
- Licensing configuration
- Multi-tenant org config (optional)

---

## SharePoint Coverage

Exports:

- Tenant configuration
- Site summary list

Includes:

- URL
- Template
- Owner
- Storage
- Sharing state

---

## Meta Output

### manifest.json

Tracks execution success/failure per step.

### errors.json

Captures exception details.

### run.json

Captures:

- timestamp
- parameters
- environment

---

## Key Engineering Patterns

### Pagination Handling

Graph API pagination handled via:

- `@odata.nextLink`

Ensures full dataset retrieval.

---

### Per-object Export Pattern

Applied to:

- Conditional Access
- Named Locations
- Authentication Strength Policies

Benefits:

- Fine-grained diffs
- Reduced noise
- Easier debugging

---

### Filename Sanitization

Ensures:

- Cross-platform compatibility
- Stable filenames
- Safe Git usage

---

### Fault Isolation

Each collector runs independently.

Result:

- Partial success is preserved
- Failures do not stop execution

---

## Limitations

### Missing Workloads

Not covered:

- Intune
- Defender
- Purview
- Power Platform

---

### Depth Gaps

- Teams policies not deeply exported
- Exchange rules/connectors not included
- SharePoint configuration limited

---

### Data Noise

Graph responses include:

- timestamps
- metadata
- non-deterministic ordering

Not ideal for diffing without normalization.

---

## Recommended Enhancements

### 1. Normalization Layer

Strip:

- timestamps
- volatile IDs
- reorder arrays

---

### 2. Retry Logic

Handle:

- 429 (throttling)
- 5xx (transient errors)

---

### 3. CI/CD Integration

Use:

- OIDC federation
- GitHub Actions

---

### 4. Coverage Expansion

Add:

- Teams policies
- Exchange transport rules
- SharePoint sharing config
- App role assignments

---

## Practical Use Cases

### Documentation

Create tenant baseline.

### Migration Planning

Understand configuration scope.

### Security Review

Inspect CA policies, roles, auth.

### Drift Detection (with normalization)

Track changes over time.

---

## Conclusion

This script provides a **strong, extensible foundation** for Microsoft 365 tenant configuration extraction.

It becomes a **serious engineering asset** when extended with:

- normalization
- diffing
- automation

Without those, it remains a snapshot tool.

With them, it becomes a **governance and control mechanism**.
