# Approved PowerShell Modules

This document lists the PowerShell modules approved for use in Managed Solution engineering work. Only modules on this list should be used in production automation and client-facing scripts. If you need a module not on this list, propose its addition through the CONTRIBUTING.md process with a justification for its inclusion and a review of its security posture.

## Microsoft Graph SDK

The Microsoft.Graph SDK v2 is our primary interface for Microsoft 365 and Entra ID operations. Import only the sub-modules your script actually needs rather than the entire SDK — this significantly reduces import time and memory footprint.

| Module | Minimum Version | Use Case |
|---|---|---|
| Microsoft.Graph.Authentication | 2.0.0 | All Graph connections (Connect-MgGraph, Get-MgContext) |
| Microsoft.Graph.Users | 2.0.0 | User management, license queries, profile updates |
| Microsoft.Graph.Groups | 2.0.0 | Group management, membership, dynamic groups |
| Microsoft.Graph.Mail | 2.0.0 | Mailbox operations via Graph (alternative to EXO for read operations) |
| Microsoft.Graph.Calendar | 2.0.0 | Calendar operations, meeting management |
| Microsoft.Graph.Teams | 2.0.0 | Teams data operations (membership, channels, messages) |
| Microsoft.Graph.Identity.DirectoryManagement | 2.0.0 | Directory roles, administrative units, org settings |
| Microsoft.Graph.Identity.SignIns | 2.0.0 | Conditional access policies, authentication methods |
| Microsoft.Graph.Security | 2.0.0 | Security alerts, incidents, secure score |
| Microsoft.Graph.Reports | 2.0.0 | Usage reports, audit logs via Graph |
| Microsoft.Graph.Sites | 2.0.0 | SharePoint site operations via Graph |
| Microsoft.Graph.Applications | 2.0.0 | App registration management, service principal queries |

When importing Graph sub-modules, note that `Microsoft.Graph.Authentication` is always required and is typically auto-imported when you import any other sub-module. Explicitly importing it in your `#Requires` statement makes the dependency clear.

## Microsoft 365 Service Modules

These modules provide service-specific cmdlets that either supplement or are preferred over the Graph SDK for certain operations.

| Module | Minimum Version | Use Case |
|---|---|---|
| ExchangeOnlineManagement | 3.0.0 | Mailbox administration, transport rules, compliance. Prefer Get-EXO* REST cmdlets. |
| PnP.PowerShell | 2.2.0 | SharePoint site content operations, list management, page management. |
| MicrosoftTeams | 5.0.0 | Teams policy management, team/channel lifecycle. |
| Microsoft.Online.SharePoint.PowerShell | 16.0.0 | SPO tenant admin operations (site creation, quotas, sharing policies). |

## Azure Modules

Used when scripts need to interact with Azure infrastructure, Key Vault, or Azure-hosted resources.

| Module | Minimum Version | Use Case |
|---|---|---|
| Az.Accounts | 2.12.0 | Azure authentication (Connect-AzAccount), subscription context. |
| Az.KeyVault | 5.0.0 | Secret retrieval for Tier 3 auth patterns, certificate management. |
| Az.Automation | 1.9.0 | Managing Azure Automation runbooks, schedules, and variables. |
| Az.Resources | 6.0.0 | Resource group management, RBAC role assignments, deployments. |

## Utility Modules

These modules support common utility functions in automation scripts.

| Module | Minimum Version | Use Case |
|---|---|---|
| ImportExcel | 7.8.0 | Reading and writing Excel files (.xlsx) without requiring Excel. Preferred over COM automation. |
| PSWriteHTML | 0.0.180 | Generating HTML reports from PowerShell data. Used for client-facing report deliverables. |
| Pester | 5.4.0 | Unit testing framework for module and function testing. |

## Modules NOT Approved for Use

The following modules are explicitly not approved. They are either deprecated, insecure, or superseded by approved alternatives.

| Module | Reason | Use Instead |
|---|---|---|
| AzureAD | Deprecated by Microsoft (retirement Nov 2024). Uses legacy Azure AD Graph. | Microsoft.Graph SDK |
| AzureADPreview | Same as AzureAD — deprecated. | Microsoft.Graph SDK |
| MSOnline (MSOL) | Deprecated. Uses legacy auth patterns incompatible with modern security. | Microsoft.Graph SDK |
| CredentialManager | Stores credentials in Windows Credential Manager which is not suitable for service accounts. | Azure Key Vault (Az.KeyVault) |
| PSCredentialManager | Same concerns as CredentialManager. | Azure Key Vault (Az.KeyVault) |

If you encounter any of these modules in existing scripts, flag them for migration during your next code review cycle. The Graph SDK provides equivalent (and often superior) functionality for all scenarios previously handled by AzureAD and MSOnline.

## Version Pinning and Updates

Production automation hosts should use the `#Requires` statement to declare minimum module versions. Module updates on automation hosts should follow a test-then-deploy process — update in a non-production environment first, verify all dependent scripts still function correctly, then deploy to production. Never run `Update-Module` directly on a production automation host without testing.

The `Test-MSModuleVersions` function in the M365 Module Patterns document provides a health check that validates installed module versions against these minimum requirements.
