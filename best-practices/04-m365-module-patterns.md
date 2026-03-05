# Microsoft 365 Module Patterns

This document covers the approved patterns for working with the major Microsoft 365 PowerShell modules beyond the core Graph SDK. Each module has its own authentication quirks, connection patterns, and gotchas — this guide standardizes how we handle them.

## Exchange Online Management

The ExchangeOnlineManagement module (EXO V3) is used for mailbox administration, transport rules, compliance, and mail flow operations. It supports both interactive and certificate-based authentication.

### Connection Patterns

```powershell
# Certificate-based (Tier 2) — preferred for automation
# Requires an Entra ID app registration with Exchange.ManageAsApp permission
# and the Exchange Administrator role assigned to the service principal
Connect-ExchangeOnline `
    -CertificateThumbprint $env:MS_EXO_CERT_THUMB `
    -AppId $env:MS_EXO_APP_ID `
    -Organization "managedsolution.onmicrosoft.com" `
    -ShowBanner:$false  # Suppress the module banner in automation contexts

# Interactive (Tier 4) — for ad-hoc administration
Connect-ExchangeOnline -UserPrincipalName "admin@managedsolution.com" -ShowBanner:$false
```

### EXO V3 Cmdlet Preference

EXO V3 introduced REST-based cmdlets that are faster and more reliable than the legacy implicit remoting cmdlets. REQUIRED: Always use the REST-based cmdlets (prefixed with `Get-EXO*` where available) over their legacy counterparts.

```powershell
# CORRECT — REST-based cmdlet, significantly faster for large mailbox sets
$Mailboxes = Get-EXOMailbox -ResultSize Unlimited -Properties DisplayName, PrimarySmtpAddress, RecipientTypeDetails

# AVOID — legacy implicit remoting cmdlet (slower, serialization overhead)
$Mailboxes = Get-Mailbox -ResultSize Unlimited
```

The REST-based cmdlets also support property filtering at the server side, reducing data transfer. Always specify `-Properties` to retrieve only what you need, following the same principle as Graph SDK's `-Property` parameter.

### Recipient Filtering

Exchange has its own server-side filtering syntax (OPATH) which is much more efficient than client-side `Where-Object` filtering. Use `-Filter` parameters whenever possible.

```powershell
# CORRECT — server-side OPATH filter, only matching mailboxes are returned
$SharedMailboxes = Get-EXOMailbox -Filter "RecipientTypeDetails -eq 'SharedMailbox'" -ResultSize Unlimited

# INCORRECT — retrieves ALL mailboxes then filters client-side (slow, wasteful)
$SharedMailboxes = Get-EXOMailbox -ResultSize Unlimited | Where-Object { $_.RecipientTypeDetails -eq 'SharedMailbox' }
```

### Session Management

Exchange Online sessions are a limited resource. Each connection consumes one of the tenant's concurrent session slots. REQUIRED: Always disconnect when finished, and never open multiple connections to the same tenant in parallel scripts without coordination.

```powershell
try {
    Connect-ExchangeOnline -CertificateThumbprint $Thumbprint -AppId $AppId -Organization $Org -ShowBanner:$false
    # ... mailbox operations ...
} finally {
    Disconnect-ExchangeOnline -Confirm:$false
}
```

## SharePoint Online and PnP PowerShell

For SharePoint administration, we use a combination of the Microsoft.Online.SharePoint.PowerShell module (for tenant-level admin operations) and PnP.PowerShell (for site-level content operations). PnP is the preferred tool for most day-to-day SharePoint automation.

### Connection Patterns

```powershell
# PnP — certificate-based auth to a specific site
# The Entra app registration needs Sites.FullControl.All or appropriate granular permissions
Connect-PnPOnline -Url "https://managedsolution.sharepoint.com/sites/IT" `
    -ClientId $env:MS_PNP_APP_ID `
    -Tenant "managedsolution.onmicrosoft.com" `
    -Thumbprint $env:MS_PNP_CERT_THUMB

# PnP — interactive auth for ad-hoc work
Connect-PnPOnline -Url "https://managedsolution.sharepoint.com/sites/IT" -Interactive

# SPO Admin module — for tenant-level operations (site creation, quotas, etc.)
Connect-SPOService -Url "https://managedsolution-admin.sharepoint.com"
```

### PnP Batching

PnP supports batching for list operations, which dramatically reduces round trips when creating or updating many list items.

```powershell
# Batch pattern for PnP list item creation
$Batch = New-PnPBatch

foreach ($Item in $DataToImport) {
    Add-PnPListItem -List "Inventory" -Values @{
        Title       = $Item.Name
        Department  = $Item.Dept
        AssetTag    = $Item.Tag
    } -Batch $Batch
}

# Execute all operations in a single batch call
Invoke-PnPBatch -Batch $Batch

Write-Output "Batch complete: $($DataToImport.Count) items created."
```

### Site-Scoped vs Tenant-Scoped Operations

A common mistake is using the SPO Admin module for operations that PnP handles better at the site level, or vice versa. The general rule is that if you're managing a specific site's content (lists, libraries, pages, permissions within a site), use PnP connected to that site. If you're managing the tenant's site collection inventory (creating sites, setting quotas, managing sharing policies), use the SPO Admin module.

## Microsoft Teams

Teams administration uses the MicrosoftTeams module for team/channel management and policies, while Teams-related data (chat messages, meeting transcripts) is accessed through the Graph SDK.

### Connection Patterns

```powershell
# Certificate-based for automation
Connect-MicrosoftTeams -CertificateThumbprint $env:MS_TEAMS_CERT_THUMB `
    -ApplicationId $env:MS_TEAMS_APP_ID `
    -TenantId $env:MS_TENANT_ID

# Interactive for ad-hoc
Connect-MicrosoftTeams
```

### Teams vs Graph SDK Boundary

The MicrosoftTeams module is primarily for policy management and team/channel lifecycle. For reading team membership, channel messages, or other data operations, prefer the Graph SDK.

```powershell
# Use MicrosoftTeams module for policy operations
$Policy = Get-CsTeamsMessagingPolicy -Identity "RestrictedMessaging"

# Use Graph SDK for data operations
$TeamMembers = Get-MgGroupMember -GroupId $TeamId -All
$Channels = Get-MgTeamChannel -TeamId $TeamId
```

## Security & Compliance Center

The Security & Compliance PowerShell module uses a separate connection from Exchange Online, even though it shares the `Connect-IPPSSession` pattern. This module handles DLP policies, retention labels, eDiscovery, and audit log queries.

### Connection Patterns

```powershell
# Certificate-based — requires Exchange Administrator or Compliance Administrator role
Connect-IPPSSession -CertificateThumbprint $env:MS_COMPLIANCE_CERT_THUMB `
    -AppId $env:MS_COMPLIANCE_APP_ID `
    -Organization "managedsolution.onmicrosoft.com"

# Interactive
Connect-IPPSSession -UserPrincipalName "admin@managedsolution.com"
```

### Audit Log Queries

Unified audit log queries support CMMC AU.L2-3.3.1 (System Auditing) and AU.L2-3.3.2 (Audit Correlation). When querying audit logs, always specify date ranges and operation types to avoid unbounded queries that time out.

```powershell
# CORRECT — scoped query with date range and operation filter
$AuditParams = @{
    StartDate    = (Get-Date).AddDays(-7)
    EndDate      = Get-Date
    Operations   = @('FileAccessed', 'FileDownloaded', 'FileModified')
    ResultSize   = 5000
    RecordType   = 'SharePointFileOperation'
}
$AuditRecords = Search-UnifiedAuditLog @AuditParams

# AVOID — unbounded query (will likely time out or hit result limits)
$AuditRecords = Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-90) -EndDate (Get-Date)
```

## Module Version Management

### Keeping Modules Current

REQUIRED: All production automation hosts MUST run supported versions of M365 modules. Use a standardized update process rather than ad-hoc `Update-Module` calls on individual servers.

```powershell
# Module version check — useful as a health check function
function Test-MSModuleVersions {
    [CmdletBinding()]
    param()

    $RequiredModules = @{
        'Microsoft.Graph'                = '2.0.0'   # Minimum supported version
        'ExchangeOnlineManagement'       = '3.0.0'
        'PnP.PowerShell'                 = '2.2.0'
        'MicrosoftTeams'                 = '5.0.0'
        'Az.Accounts'                    = '2.12.0'
        'Az.KeyVault'                    = '5.0.0'
    }

    foreach ($Module in $RequiredModules.GetEnumerator()) {
        $Installed = Get-Module -ListAvailable -Name $Module.Key | 
            Sort-Object Version -Descending | 
            Select-Object -First 1

        if (-not $Installed) {
            Write-Warning "MISSING: $($Module.Key) is not installed."
        } elseif ($Installed.Version -lt [version]$Module.Value) {
            Write-Warning "OUTDATED: $($Module.Key) is version $($Installed.Version), minimum required is $($Module.Value)."
        } else {
            Write-Output "OK: $($Module.Key) version $($Installed.Version)"
        }
    }
}
```

### Importing Modules Explicitly

REQUIRED: Always import modules with explicit version requirements in scripts that will run unattended. This prevents issues when multiple module versions are installed side by side.

```powershell
# Import a specific minimum version
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Users'; RequiredVersion = '2.11.0' }

# Or use the #Requires statement at the top of the script
#Requires -Modules ExchangeOnlineManagement
#Requires -Version 7.2
```

## Multi-Module Scripts — Connection Order

When a script connects to multiple M365 services, establish connections in this order to avoid module conflict issues:

1. Microsoft.Graph SDK (connect first — it's the most commonly used and least conflict-prone)
2. Exchange Online Management
3. Security & Compliance (IPPSSession)
4. PnP.PowerShell (connect to specific site)
5. MicrosoftTeams
6. Az modules (if needed)

Disconnect in reverse order in the `finally` block.
