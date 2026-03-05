# Error Handling and Logging

This document defines how Managed Solution engineers handle errors, implement logging, and ensure scripts fail gracefully with meaningful diagnostic output. Proper error handling is not optional — it is a compliance requirement under CMMC AU.L2-3.3.1 (System Auditing) and SI.L2-3.14.1 (Flaw Remediation), and it is the difference between a script that silently loses data and one that tells you exactly what went wrong.

## Error Action Preferences

### Script-Level Default

Every script MUST set `$ErrorActionPreference = 'Stop'` at the top of the script body. This converts non-terminating errors into terminating errors, which means they will be caught by `try/catch` blocks. Without this, many cmdlet failures silently continue execution, producing partial or incorrect results.

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
```

### Per-Cmdlet Override

In specific cases where you expect and want to handle a non-terminating error inline (e.g., checking if a user exists), override `-ErrorAction` at the cmdlet level rather than changing the script-level preference.

```powershell
# Override for a specific call where a 404 is expected and handled
$User = Get-MgUser -UserId $UPN -ErrorAction SilentlyContinue
if (-not $User) {
    Write-Output "User $UPN not found — creating new account."
    # ... creation logic ...
}
```

REQUIRED: Never set `$ErrorActionPreference = 'SilentlyContinue'` at the script level. This suppresses all errors globally and makes debugging nearly impossible. If you need to silence a specific call, use `-ErrorAction SilentlyContinue` on that cmdlet only.

## Try/Catch/Finally Structure

### Basic Pattern

Every operation that interacts with an external service (Graph API, Exchange Online, SharePoint, Azure, file system on a remote host) MUST be wrapped in a `try/catch` block. External calls can fail for reasons outside your control — network issues, throttling, permission changes, service outages.

```powershell
try {
    $Users = Get-MgUser -All -Property DisplayName, UserPrincipalName, AssignedLicenses
    Write-Output "Successfully retrieved $($Users.Count) users."
} catch {
    # Log the full error for diagnostics
    Write-Error "Failed to retrieve users from Graph API. Error: $($_.Exception.Message)"
    
    # Optionally inspect the error category for specific handling
    if ($_.CategoryInfo.Category -eq 'ResourceUnavailable') {
        Write-Warning "Graph API may be experiencing an outage. Check https://status.microsoft.com"
    }
    
    # Re-throw if you want the calling scope to handle it
    throw
}
```

### Finally for Cleanup

The `finally` block runs regardless of whether an error occurred. Use it for resource cleanup — disconnecting service sessions, closing file handles, releasing locks. This is REQUIRED for any script that establishes M365 service connections.

```powershell
try {
    Connect-MgGraph @ConnectionParams
    Connect-ExchangeOnline @ExoParams -ShowBanner:$false
    
    # ... main script logic ...
} catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    # Error-specific handling here
} finally {
    # These run even if an error was thrown
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "Cleanup complete — all sessions disconnected."
}
```

### Nested Try/Catch for Granular Handling

For scripts that perform multiple independent operations (e.g., processing a list of users), use nested `try/catch` inside a loop so that a failure on one item doesn't abort the entire batch. Track successes and failures for summary reporting.

```powershell
$Results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($UPN in $UserList) {
    try {
        $License = Get-MgUserLicenseDetail -UserId $UPN -ErrorAction Stop
        $Results.Add([PSCustomObject]@{
            UPN     = $UPN
            Status  = 'Success'
            Licenses = ($License.SkuPartNumber -join ', ')
            Error   = $null
        })
    } catch {
        # Log failure but continue processing remaining users
        Write-Warning "Failed to process $UPN : $($_.Exception.Message)"
        $Results.Add([PSCustomObject]@{
            UPN     = $UPN
            Status  = 'Failed'
            Licenses = $null
            Error   = $_.Exception.Message
        })
    }
}

# Summary report
$SuccessCount = ($Results | Where-Object Status -eq 'Success').Count
$FailCount = ($Results | Where-Object Status -eq 'Failed').Count
Write-Output "Processing complete: $SuccessCount succeeded, $FailCount failed out of $($UserList.Count) total."
```

## Logging Standards

### Structured Log Output

Scripts that run unattended (scheduled tasks, Azure Automation, CI/CD pipelines) MUST produce structured log output that can be parsed by monitoring tools. Use a consistent log format with timestamp, severity, and message.

```powershell
# Logging helper function — include in all automation scripts
function Write-MSLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Severity = 'INFO',

        [string]$LogPath
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $LogEntry = "[$Timestamp] [$Severity] $Message"

    # Always write to the output stream
    switch ($Severity) {
        'ERROR' { Write-Error $LogEntry }
        'WARN'  { Write-Warning $LogEntry }
        'DEBUG' { Write-Verbose $LogEntry }
        default { Write-Output $LogEntry }
    }

    # Optionally write to a log file
    if ($LogPath) {
        $LogEntry | Out-File -FilePath $LogPath -Append -Encoding UTF8
    }
}

# Usage throughout the script
Write-MSLog -Message "Script started. Target tenant: $TenantId" -Severity INFO -LogPath $LogFile
Write-MSLog -Message "Retrieved $($Users.Count) users from Graph API" -Severity INFO -LogPath $LogFile
Write-MSLog -Message "User $UPN has no assigned licenses — skipping" -Severity WARN -LogPath $LogFile
Write-MSLog -Message "Graph API call failed: $($_.Exception.Message)" -Severity ERROR -LogPath $LogFile
```

### What to Log

Every script MUST log the following events to support audit and compliance requirements (CMMC AU.L2-3.3.1, AU.L2-3.3.2):

**Script lifecycle**: Start time, end time, execution duration, and exit status (success/failure/partial). This is the bare minimum for any script.

**Authentication events**: Which service principal or user identity was used, which tenant was targeted, and whether authentication succeeded. Never log credentials, tokens, or secrets — log identifiers only (app ID, thumbprint prefix, UPN).

**Data operations**: How many records were read, created, modified, or deleted. For sensitive operations (permission changes, mailbox access, compliance policy changes), log the specific objects affected.

**Errors and warnings**: Full exception messages, stack traces for unexpected errors, and any degraded-mode operation.

```powershell
# Script lifecycle logging example
$ScriptStart = Get-Date
$ScriptName = $MyInvocation.MyCommand.Name
Write-MSLog -Message "=== $ScriptName started ===" -Severity INFO -LogPath $LogFile

try {
    # ... main logic ...
    Write-MSLog -Message "=== $ScriptName completed successfully ===" -Severity INFO -LogPath $LogFile
} catch {
    Write-MSLog -Message "=== $ScriptName FAILED: $($_.Exception.Message) ===" -Severity ERROR -LogPath $LogFile
    throw
} finally {
    $Duration = (Get-Date) - $ScriptStart
    Write-MSLog -Message "Total execution time: $($Duration.ToString('hh\:mm\:ss'))" -Severity INFO -LogPath $LogFile
}
```

### What NOT to Log

REQUIRED (CMMC SC.L2-3.13.10, SC.L2-3.13.16): Never log any of the following to any log file, console output, or telemetry system. This is a compliance violation.

- Passwords, client secrets, API keys, or bearer tokens
- Full certificate thumbprints (log only the first 8 characters if needed for identification)
- Personally identifiable information beyond what is operationally necessary (e.g., do not log full SSNs, full credit card numbers, or medical record identifiers)
- The content of emails, documents, or messages (log metadata like subject lines and timestamps, not body content)

```powershell
# CORRECT — log identifiers, not secrets
Write-MSLog -Message "Authenticated as AppId: $AppId to tenant $TenantId using cert $($Thumbprint.Substring(0,8))..." -Severity INFO

# NEVER DO THIS
Write-MSLog -Message "Using client secret: $ClientSecret" -Severity INFO  # VIOLATION
Write-MSLog -Message "Email body: $($Email.Body.Content)" -Severity DEBUG  # VIOLATION
```

## Error Classification and Response

Not all errors are equal. Engineers should classify errors by recoverability and respond accordingly.

### Transient Errors (Retry)

These are temporary failures caused by network blips, service throttling, or brief outages. The correct response is to retry with backoff. Common indicators include HTTP 429, 503, 504 status codes, and "timeout" or "throttle" in the error message.

```powershell
# Use the Invoke-MSGraphWithRetry function from the Graph API patterns document
# for all Graph calls in production automation
```

### Permanent Errors (Log and Skip/Abort)

These are errors caused by invalid input, missing permissions, or resources that genuinely don't exist. Retrying will not help. The correct response is to log the error with enough detail to diagnose the root cause, then either skip the item (in batch operations) or abort the script.

```powershell
catch {
    if ($_.Exception.Message -match 'Request_ResourceNotFound|404') {
        # Permanent — the user doesn't exist, log and skip
        Write-MSLog -Message "User $UPN not found in tenant — skipping" -Severity WARN -LogPath $LogFile
    } elseif ($_.Exception.Message -match 'Authorization_RequestDenied|403') {
        # Permanent — permission issue, abort script (don't silently continue with partial data)
        Write-MSLog -Message "Insufficient permissions for operation. Verify app registration scopes." -Severity ERROR -LogPath $LogFile
        throw
    } else {
        # Unknown — treat as transient and retry (or abort if retries exhausted)
        throw
    }
}
```

### Configuration Errors (Abort Immediately)

These are errors that occur before the main logic even starts — failed authentication, missing required modules, invalid parameters. The script should abort immediately with a clear error message explaining what needs to be fixed.

```powershell
# Pre-flight checks at script start
#Requires -Modules Microsoft.Graph.Users, ExchangeOnlineManagement
#Requires -Version 7.2

# Verify required environment variables
$RequiredEnvVars = @('MS_GRAPH_APP_ID', 'MS_TENANT_ID', 'MS_GRAPH_CERT_THUMB')
foreach ($Var in $RequiredEnvVars) {
    if (-not (Get-Item -Path "env:$Var" -ErrorAction SilentlyContinue)) {
        throw "CONFIGURATION ERROR: Required environment variable '$Var' is not set. See script header for setup instructions."
    }
}
```

## Progress Reporting

For long-running scripts that process many items, provide progress feedback so operators can estimate completion time and identify stalls.

```powershell
$Total = $UserList.Count
$Current = 0

foreach ($UPN in $UserList) {
    $Current++
    $PercentComplete = [math]::Round(($Current / $Total) * 100, 1)
    
    Write-Progress -Activity "Processing user licenses" `
        -Status "$Current of $Total ($PercentComplete%)" `
        -PercentComplete $PercentComplete `
        -CurrentOperation $UPN

    # ... process user ...
}

Write-Progress -Activity "Processing user licenses" -Completed
```

For scripts running in non-interactive contexts (Azure Automation, CI/CD) where `Write-Progress` output is lost, use periodic log messages instead.

```powershell
if ($Current % 100 -eq 0) {
    Write-MSLog -Message "Progress: $Current of $Total processed ($PercentComplete%)" -Severity INFO -LogPath $LogFile
}
```
