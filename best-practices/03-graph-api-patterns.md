# Microsoft Graph API Patterns

This document defines the approved patterns for interacting with Microsoft Graph at Managed Solution. Our primary interface is the Microsoft.Graph PowerShell SDK v2. Direct REST calls via `Invoke-RestMethod` are acceptable in specific scenarios documented below, but the SDK is the default choice.

## When to Use the SDK vs REST

### Use the Microsoft.Graph SDK (Default)

The SDK handles authentication token management, pagination, retry logic, and type safety. It is the correct choice for the vast majority of Graph interactions.

```powershell
# SDK handles token refresh, pagination, and deserialization automatically
$Users = Get-MgUser -All -Property DisplayName, UserPrincipalName, AssignedLicenses
```

### Use Direct REST (Exception Cases Only)

Direct REST calls via `Invoke-MgGraphRequest` (preferred) or `Invoke-RestMethod` are acceptable when the SDK cmdlet does not yet support a Graph API endpoint, when you need fine-grained control over request headers or batching, or when working with beta endpoints not covered by the SDK.

```powershell
# PREFERRED REST approach — uses the existing Graph session for auth
# Invoke-MgGraphRequest inherits the Connect-MgGraph session token
$Response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/reports/getMailboxUsageDetail(period='D30')"

# ACCEPTABLE when Invoke-MgGraphRequest is insufficient
# (e.g., custom headers, binary responses, beta endpoints)
$Token = (Get-MgContext).AccessToken  # Only if token access is available in your context
$Headers = @{
    Authorization  = "Bearer $Token"
    'Content-Type' = 'application/json'
}
$Response = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/some/endpoint" -Headers $Headers -Method GET
```

REQUIRED: When using direct REST calls, always use `Invoke-MgGraphRequest` over raw `Invoke-RestMethod` unless you have a documented reason. `Invoke-MgGraphRequest` inherits the SDK session and handles token refresh automatically.

## Permission Scoping

Every Graph interaction requires appropriate permissions. Following the principle of least privilege (CMMC AC.L2-3.1.5), scripts MUST request only the permissions they actually need.

### Documenting Required Permissions

Every function or script that calls Graph MUST document its required permissions in the help block. This serves as both operational documentation and audit evidence.

```powershell
<#
.SYNOPSIS
    Retrieves user license assignments from Microsoft Graph.

.NOTES
    Required Graph Permissions (Application):
        - User.Read.All (Read all users' full profiles)
        - Directory.Read.All (Read directory data)

    Required Graph Permissions (Delegated):
        - User.Read.All (if running in delegated context)

    App Registration: MS-LicenseAudit (AppId in Key Vault)
    Compliance: Supports AC.L2-3.1.1, AC.L2-3.1.5
#>
```

### Application vs Delegated Permissions

For unattended automation (the majority of our scripts), use application permissions. For scripts that act on behalf of a specific user or need user-context access, use delegated permissions with interactive auth.

A common mistake is requesting `Mail.ReadWrite` (application) when the script only needs to read a specific user's mailbox — in that case, delegated `Mail.Read` with the user's consent is more appropriate and more compliant.

## Pagination and Large Result Sets

Graph API endpoints return paginated results by default (typically 100 items per page). Failing to handle pagination is one of the most common bugs in Graph scripts and can cause silent data loss.

### SDK Pagination

The SDK handles pagination automatically when you use the `-All` parameter. Always use it when you intend to retrieve every item.

```powershell
# CORRECT — retrieves all pages automatically
$AllUsers = Get-MgUser -All -Property DisplayName, UserPrincipalName, AccountEnabled

# CORRECT — with count for progress tracking on large tenants
$AllUsers = Get-MgUser -All -ConsistencyLevel eventual -Count userCount -Property DisplayName, UserPrincipalName
Write-Output "Retrieved $userCount users"

# DANGEROUS — returns only the first page (default ~100 items)
# This WILL silently miss users in any tenant with more than 100 accounts
$Users = Get-MgUser -Property DisplayName, UserPrincipalName
```

### Manual Pagination (REST Calls)

When using direct REST calls, you MUST implement pagination by following `@odata.nextLink` until it is absent from the response.

```powershell
# Manual pagination pattern for REST calls
$Uri = "https://graph.microsoft.com/v1.0/users?`$select=displayName,userPrincipalName&`$top=100"
$AllResults = [System.Collections.Generic.List[object]]::new()

do {
    $Response = Invoke-MgGraphRequest -Method GET -Uri $Uri
    $AllResults.AddRange($Response.value)
    $Uri = $Response.'@odata.nextLink'  # Will be $null when no more pages
    
    # Progress feedback for large datasets
    Write-Verbose "Retrieved $($AllResults.Count) items so far..."
} while ($Uri)

Write-Output "Total items retrieved: $($AllResults.Count)"
```

## Batching

Graph supports JSON batching, allowing up to 20 requests in a single HTTP call. Use batching when you need to make many independent calls (e.g., updating 500 users) to reduce total execution time and avoid throttling.

```powershell
# Batch pattern for multiple independent operations
# Split work into chunks of 20 (Graph batch limit)
$UserUpdates = @(
    @{ id = "1"; method = "PATCH"; url = "/users/user1@contoso.com"; body = @{ department = "IT" } }
    @{ id = "2"; method = "PATCH"; url = "/users/user2@contoso.com"; body = @{ department = "IT" } }
    # ... up to 20 per batch
)

$BatchBody = @{ requests = $UserUpdates } | ConvertTo-Json -Depth 10

$BatchResponse = Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/`$batch" `
    -Body $BatchBody `
    -ContentType "application/json"

# Check individual response status codes
foreach ($Response in $BatchResponse.responses) {
    if ($Response.status -ge 400) {
        Write-Warning "Request $($Response.id) failed with status $($Response.status): $($Response.body.error.message)"
    }
}
```

## Throttling and Retry Logic

Graph API enforces rate limits. When you receive a 429 (Too Many Requests) response, the SDK handles basic retry automatically. However, for high-volume operations, implement explicit retry logic with exponential backoff.

```powershell
# Retry wrapper function for Graph operations
function Invoke-MSGraphWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [int]$MaxRetries = 3,

        [int]$BaseDelaySeconds = 2
    )

    $Attempt = 0
    while ($Attempt -lt $MaxRetries) {
        try {
            return & $ScriptBlock
        } catch {
            $Attempt++
            if ($Attempt -ge $MaxRetries) {
                throw "Graph operation failed after $MaxRetries attempts. Last error: $_"
            }

            # Check for Retry-After header in throttling responses
            $RetryAfter = $_.Exception.Response.Headers['Retry-After']
            $Delay = if ($RetryAfter) { 
                [int]$RetryAfter 
            } else { 
                [math]::Pow($BaseDelaySeconds, $Attempt)  # Exponential backoff
            }

            Write-Warning "Graph call throttled or failed (attempt $Attempt/$MaxRetries). Retrying in $Delay seconds..."
            Start-Sleep -Seconds $Delay
        }
    }
}

# Usage
$Users = Invoke-MSGraphWithRetry -ScriptBlock {
    Get-MgUser -All -Property DisplayName, UserPrincipalName, AssignedLicenses
}
```

## Common Patterns

### User Lookup with Error Handling

```powershell
function Get-MSGraphUser {
    [CmdletBinding()]
    [OutputType([Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$UserPrincipalName
    )

    process {
        try {
            $User = Get-MgUser -UserId $UserPrincipalName -Property DisplayName, UserPrincipalName, AccountEnabled, AssignedLicenses -ErrorAction Stop
            return $User
        } catch {
            if ($_.Exception.Message -match '404|Request_ResourceNotFound') {
                Write-Warning "User not found in Entra ID: $UserPrincipalName"
                return $null
            }
            # Re-throw unexpected errors
            throw
        }
    }
}
```

### Group Membership Retrieval

```powershell
# Get all members of a group, handling nested groups
function Get-MSGroupMemberRecursive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [int]$Depth = 0,

        [int]$MaxDepth = 5  # Prevent infinite recursion on circular nesting
    )

    if ($Depth -ge $MaxDepth) {
        Write-Warning "Max nesting depth ($MaxDepth) reached for group $GroupId"
        return
    }

    $Members = Get-MgGroupMember -GroupId $GroupId -All

    foreach ($Member in $Members) {
        if ($Member.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group') {
            # Recurse into nested group
            Get-MSGroupMemberRecursive -GroupId $Member.Id -Depth ($Depth + 1) -MaxDepth $MaxDepth
        } else {
            # Return the member object
            [PSCustomObject]@{
                Id                = $Member.Id
                DisplayName       = $Member.AdditionalProperties.displayName
                UserPrincipalName = $Member.AdditionalProperties.userPrincipalName
                MemberType        = $Member.AdditionalProperties.'@odata.type'.Split('.')[-1]
                SourceGroupId     = $GroupId
                NestingDepth      = $Depth
            }
        }
    }
}
```

### Selecting Properties Efficiently

Always use the `-Property` parameter (which maps to `$select` in OData) to request only the fields you need. Fetching full user/group objects when you only need two fields wastes bandwidth, increases latency, and can trigger additional permission requirements.

```powershell
# CORRECT — request only what you need
$Users = Get-MgUser -All -Property DisplayName, UserPrincipalName, AccountEnabled

# INCORRECT — fetches the full default property set (wasteful and potentially over-permissioned)
$Users = Get-MgUser -All
```

## Beta vs v1.0 Endpoints

REQUIRED: Production scripts MUST use v1.0 endpoints. Beta endpoints can change without notice and have no stability guarantees. If you need a beta-only feature for production use, document it as a known risk in the script header and plan for migration to v1.0 when available.

```powershell
# Use the v1.0 profile (default)
Select-MgProfile -Name "v1.0"

# Beta profile — development and testing ONLY
# Document the beta dependency prominently
Select-MgProfile -Name "beta"  # WARNING: Beta endpoints — not for production
```
