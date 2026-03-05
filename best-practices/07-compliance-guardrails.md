# Compliance Guardrails

This document maps coding practices to specific CMMC Level 2 and NIST 800-171 controls. Rather than treating compliance as a separate checklist, this guide shows how each control manifests in the PowerShell code we write daily. Every engineer should understand not just what to do, but which control it satisfies and why an auditor cares.

## How to Use This Document

Each section below maps a family of CMMC/NIST controls to specific coding practices. When the codex agent reviews code or generates scaffolding, it references these mappings to flag compliance gaps or include the right patterns automatically.

In code comments and script headers, reference controls using the format `CMMC XX.L2-3.X.X` so they are searchable and auditable across the codebase.

## Access Control (AC)

### AC.L2-3.1.1 — Authorized Access Control

**What the control requires**: Limit system access to authorized users, processes, and devices.

**How this applies to code**: Every script that authenticates to a service must verify it is running in the intended context and that the identity has been explicitly authorized for the operations being performed. Scripts should validate their own execution context rather than assuming permissions.

```powershell
# Verify the connected identity has the expected permissions before proceeding
$Context = Get-MgContext
if (-not $Context) {
    throw "COMPLIANCE VIOLATION (AC.L2-3.1.1): No authenticated Graph session. Aborting."
}

# Verify the required scopes are present in the session
$RequiredScopes = @('User.Read.All', 'Directory.Read.All')
$MissingScopes = $RequiredScopes | Where-Object { $_ -notin $Context.Scopes }
if ($MissingScopes) {
    throw "COMPLIANCE VIOLATION (AC.L2-3.1.1): Missing required scopes: $($MissingScopes -join ', '). Current scopes: $($Context.Scopes -join ', ')"
}

Write-MSLog -Message "Access validated: AppId=$($Context.ClientId), Scopes=$($Context.Scopes -join ', ')" -Severity INFO
```

### AC.L2-3.1.5 — Least Privilege

**What the control requires**: Employ the principle of least privilege, including for specific security functions and privileged accounts.

**How this applies to code**: App registrations, service principals, and interactive sessions must request only the minimum permissions needed for the task. A script that reads user profiles should not have `Directory.ReadWrite.All` just because it was convenient during development.

Practical checklist for every script and app registration:

- Review every Graph SDK cmdlet and M365 cmdlet used in the script.
- Look up the minimum permission each cmdlet requires in the Microsoft documentation.
- Configure the app registration with exactly those permissions, nothing more.
- Document the required permissions in the script header (see Authentication Patterns document).
- Periodically audit app registrations to remove permissions that are no longer needed.

```powershell
# Example: script only needs to read users — request ONLY User.Read.All
# Do NOT request User.ReadWrite.All, Directory.ReadWrite.All, or other broad permissions
Connect-MgGraph -Scopes 'User.Read.All'  # Least privilege for a read-only operation
```

### AC.L2-3.1.10 / AC.L2-3.1.11 — Session Lock and Termination

**What the control requires**: Terminate user sessions after a defined period of inactivity, and protect session authenticity.

**How this applies to code**: Scripts must not leave M365 service connections open after execution completes. Every connection must be terminated in a `finally` block. For long-running scripts, implement session refresh or reconnection logic rather than relying on a single long-lived session.

This is fully covered in the Authentication Patterns document under session management. The key compliance point is that `Disconnect-MgGraph`, `Disconnect-ExchangeOnline`, and equivalent teardown calls are not optional — they are compliance requirements.

## Audit and Accountability (AU)

### AU.L2-3.3.1 — System Auditing

**What the control requires**: Create and retain system audit logs that contain enough information to establish what events occurred, when, where, the source, and the outcome.

**How this applies to code**: Every automation script must produce log output that captures the five W's of each significant action: what happened, when, who/what initiated it, where (which system/tenant), and the result (success/failure). The logging patterns in the Error Handling and Logging document satisfy this control.

Minimum log events required for compliance:

```powershell
# REQUIRED log events for any script that modifies data or configuration
Write-MSLog -Message "AUDIT: Script $ScriptName initiated by identity $($Context.ClientId)" -Severity INFO
Write-MSLog -Message "AUDIT: Target tenant: $($Context.TenantId)" -Severity INFO
Write-MSLog -Message "AUDIT: Operation: Set-MgUserLicense for user $UPN" -Severity INFO
Write-MSLog -Message "AUDIT: Result: Success — License $SkuName assigned" -Severity INFO
# Or on failure:
Write-MSLog -Message "AUDIT: Result: FAILED — $($_.Exception.Message)" -Severity ERROR
```

### AU.L2-3.3.2 — Audit Correlation

**What the control requires**: Provide the ability to correlate audit records across systems to achieve situational awareness.

**How this applies to code**: Scripts that span multiple services (e.g., Graph + Exchange + SharePoint) should use a shared correlation identifier so that log entries from the same execution run can be linked.

```powershell
# Generate a correlation ID at script start, include it in all log entries
$CorrelationId = [guid]::NewGuid().ToString()

function Write-MSCorrelatedLog {
    param(
        [string]$Message,
        [string]$Severity = 'INFO'
    )
    Write-MSLog -Message "[$CorrelationId] $Message" -Severity $Severity -LogPath $LogFile
}

# All log entries for this execution are now linkable via the correlation ID
Write-MSCorrelatedLog -Message "Script started — processing 500 users across Graph and EXO"
Write-MSCorrelatedLog -Message "Graph phase complete: 500 users retrieved"
Write-MSCorrelatedLog -Message "EXO phase complete: 487 mailboxes updated, 13 skipped"
```

## Configuration Management (CM)

### CM.L2-3.4.1 — Baseline Configuration

**What the control requires**: Establish and maintain baseline configurations and inventories of organizational systems.

**How this applies to code**: Scripts that deploy or configure M365 settings should be idempotent (safe to run repeatedly) and should check the current state before making changes. This allows them to serve as both a configuration tool and a compliance baseline validator.

```powershell
# Idempotent pattern — check current state before modifying
$CurrentPolicy = Get-MgPolicyConditionalAccessPolicy -Filter "displayName eq 'Block Legacy Auth'"

if ($CurrentPolicy) {
    Write-MSLog -Message "Policy 'Block Legacy Auth' already exists (Id: $($CurrentPolicy.Id)). Verifying configuration..." -Severity INFO
    
    # Validate configuration matches baseline
    if ($CurrentPolicy.State -ne 'enabled') {
        Write-MSLog -Message "DRIFT DETECTED (CM.L2-3.4.1): Policy exists but is not enabled. Remediating..." -Severity WARN
        Update-MgPolicyConditionalAccessPolicy -ConditionalAccessPolicyId $CurrentPolicy.Id -State 'enabled'
    }
} else {
    Write-MSLog -Message "Policy 'Block Legacy Auth' not found. Creating from baseline..." -Severity INFO
    # ... create policy ...
}
```

### CM.L2-3.4.2 — Security Configuration Enforcement

**What the control requires**: Establish and enforce security configuration settings for IT products.

**How this applies to code**: Configuration scripts should have a "report-only" mode that checks compliance without making changes, and an "enforce" mode that remediates drift. This dual-mode approach supports both auditing and remediation workflows.

```powershell
function Set-MSSecurityBaseline {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$ReportOnly  # Compliance check mode — no changes made
    )

    # Check each baseline setting
    $MfaPolicy = Get-MgPolicyAuthenticationMethodPolicy
    
    if ($ReportOnly) {
        # Report current state without changing anything
        [PSCustomObject]@{
            Control      = 'CM.L2-3.4.2'
            Setting      = 'MFA Policy'
            Expected     = 'Enabled for all users'
            Actual       = $MfaPolicy.RegistrationEnforcement.State
            Compliant    = ($MfaPolicy.RegistrationEnforcement.State -eq 'enabled')
        }
    } else {
        if ($PSCmdlet.ShouldProcess('MFA Policy', 'Enable for all users')) {
            # Apply the baseline configuration
            # ... remediation logic ...
        }
    }
}
```

## Identification and Authentication (IA)

### IA.L2-3.5.3 — Multifactor Authentication

**What the control requires**: Use multifactor authentication for local and network access to privileged accounts and for network access to non-privileged accounts.

**How this applies to code**: Interactive authentication flows (Tier 4) MUST use MFA-capable methods (browser-based auth, device code flow). Scripts MUST NOT use `Get-Credential` with username/password to bypass MFA. For unattended automation, certificate-based auth (Tier 2) and managed identities (Tier 1) are inherently MFA-equivalent because they don't use passwords.

```powershell
# CORRECT — browser-based interactive auth triggers MFA via Conditional Access
Connect-MgGraph -Scopes 'User.Read.All'  # Opens browser for MFA-capable auth

# VIOLATION (IA.L2-3.5.3) — bypasses MFA
$Cred = Get-Credential
Connect-MgGraph -Credential $Cred  # Password-only auth, no MFA
```

## System and Communications Protection (SC)

### SC.L2-3.13.8 — Data in Transit

**What the control requires**: Implement cryptographic mechanisms to prevent unauthorized disclosure of CUI during transmission.

**How this applies to code**: All API calls must use HTTPS (TLS 1.2 or higher). PowerShell's `Invoke-RestMethod` and `Invoke-WebRequest` use HTTPS by default when the URL specifies it, but scripts should explicitly enforce TLS 1.2 as the minimum version.

```powershell
# Set TLS 1.2 as the minimum at script start
# This is especially important on older Windows systems where TLS 1.0/1.1 may be the default
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# All Graph and M365 endpoints use HTTPS, but if you're calling other APIs, verify
if ($ApiUrl -notmatch '^https://') {
    throw "COMPLIANCE VIOLATION (SC.L2-3.13.8): API URL does not use HTTPS: $ApiUrl"
}
```

### SC.L2-3.13.10 — Key Management

**What the control requires**: Establish and manage cryptographic keys when cryptography is employed.

**How this applies to code**: This control covers certificate lifecycle management for the certificates used in Tier 2 authentication. Certificate expiration monitoring, rotation procedures, and secure storage are all part of satisfying this control. See the Authentication Patterns document for certificate rotation guidance.

### SC.L2-3.13.16 — Data at Rest

**What the control requires**: Protect the confidentiality of CUI at rest.

**How this applies to code**: Scripts that write output files containing sensitive data (user lists, license reports, compliance findings) must write to protected locations and should not leave temporary files with sensitive content on disk. Clean up temp files in the `finally` block.

```powershell
$TempFile = Join-Path $env:TEMP "ms_export_$(Get-Date -Format 'yyyyMMddHHmmss').csv"

try {
    # Write sensitive data to temp location
    $Results | Export-Csv -Path $TempFile -NoTypeInformation
    
    # Move to the final secure location (network share with restricted ACL)
    Move-Item -Path $TempFile -Destination $SecureOutputPath -Force
    Write-MSLog -Message "Report written to secured location: $SecureOutputPath" -Severity INFO
} finally {
    # Ensure temp file is removed even if the move failed
    if (Test-Path $TempFile) {
        Remove-Item -Path $TempFile -Force
        Write-MSLog -Message "Temporary file cleaned up: $TempFile" -Severity DEBUG
    }
}
```

## System and Information Integrity (SI)

### SI.L2-3.14.1 — Flaw Remediation

**What the control requires**: Identify, report, and correct system flaws in a timely manner.

**How this applies to code**: This control is satisfied through input validation (preventing flaws from entering the system), error handling (detecting and reporting flaws), and version management (ensuring modules are current with security patches). All of these are covered in their respective documents.

### SI.L2-3.14.6 / SI.L2-3.14.7 — Monitoring and Alerting

**What the control requires**: Monitor organizational systems and identify unauthorized use.

**How this applies to code**: Automation scripts that run on a schedule should have health checks that detect abnormal conditions and alert. For example, a script that processes 500 users every day should alert if it suddenly processes only 50 (possible data issue) or 5000 (possible scope creep).

```powershell
# Anomaly detection pattern for scheduled automation
$ExpectedRange = @{ Min = 400; Max = 600 }  # Expected user count range based on historical data

$ProcessedCount = $Results.Count

if ($ProcessedCount -lt $ExpectedRange.Min -or $ProcessedCount -gt $ExpectedRange.Max) {
    $AlertMessage = "ANOMALY DETECTED (SI.L2-3.14.6): Expected $($ExpectedRange.Min)-$($ExpectedRange.Max) users, processed $ProcessedCount. Investigate immediately."
    Write-MSLog -Message $AlertMessage -Severity WARN -LogPath $LogFile
    # Send alert via Teams webhook, email, or monitoring platform
    Send-MSTeamsAlert -WebhookUrl $AlertWebhookUrl -Message $AlertMessage
}
```

## Quick Reference Table

This table maps common coding actions to their controlling CMMC/NIST requirements for fast lookup during code review.

| Coding Action | Primary Control | Document Reference |
|---|---|---|
| Authenticate to a service | AC.L2-3.1.1, IA.L2-3.5.3 | Authentication Patterns |
| Scope API permissions | AC.L2-3.1.5 | Authentication Patterns, Graph API Patterns |
| Disconnect sessions after use | AC.L2-3.1.10, AC.L2-3.1.11 | Authentication Patterns |
| Log script execution and outcomes | AU.L2-3.3.1 | Error Handling and Logging |
| Use correlation IDs across services | AU.L2-3.3.2 | Error Handling and Logging |
| Check config before modifying | CM.L2-3.4.1 | This document |
| Report-only vs enforce mode | CM.L2-3.4.2 | This document |
| Use MFA-capable auth flows | IA.L2-3.5.3 | Authentication Patterns |
| Enforce TLS 1.2+ for all API calls | SC.L2-3.13.8 | This document |
| Manage certificate lifecycle | SC.L2-3.13.10 | Authentication Patterns |
| Protect sensitive output files | SC.L2-3.13.16 | This document |
| Validate all input | SI.L2-3.14.1 | PowerShell Coding Standards |
| Monitor for anomalies in automation | SI.L2-3.14.6 | This document |
| No hardcoded secrets in code | SC.L2-3.13.10 | PowerShell Coding Standards |
