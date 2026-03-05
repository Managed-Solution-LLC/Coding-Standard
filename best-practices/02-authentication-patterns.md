# Authentication Patterns

This document defines the approved authentication patterns for PowerShell scripts and modules at Managed Solution. Authentication is a critical compliance surface — improper credential handling is one of the most common paths to CMMC audit findings. Every engineer should internalize these patterns.

## Authentication Hierarchy

Managed Solution uses a tiered preference model for authentication. Always use the highest-tier method available for your scenario. Moving down the tiers requires documented justification.

**Tier 1 — Managed Identity (PREFERRED for Azure-hosted automation)**
Used when scripts run inside Azure infrastructure (Azure Automation, Azure Functions, Azure VMs with system-assigned identity). No credentials to manage or rotate.

**Tier 2 — Certificate-Based App Registration (PREFERRED for on-premises and scheduled tasks)**
Used when scripts run outside Azure but need unattended access. The certificate lives in the local machine certificate store or Azure Key Vault. No client secrets.

**Tier 3 — Client Secret with Key Vault (ACCEPTABLE for specific integration scenarios)**
Used only when certificate-based auth is not feasible (e.g., third-party integrations that require a secret). The secret MUST be stored in Azure Key Vault, never in code or config files.

**Tier 4 — Interactive/Delegated (ACCEPTABLE for ad-hoc and development only)**
Used for one-off tasks, debugging, and development. Never used in production automation or scheduled tasks. Requires MFA and conditional access policies to be enforced.

## Tier 1: Managed Identity

Managed identities eliminate credential management entirely. Azure handles token issuance and rotation. Use system-assigned managed identities for single-purpose resources and user-assigned managed identities when multiple resources need the same identity.

```powershell
# Azure Automation runbook using system-assigned managed identity
# No credentials needed — Azure handles token acquisition
Connect-MgGraph -Identity

# Verify connection context for audit logging (CMMC AU.L2-3.3.1)
$Context = Get-MgContext
Write-Output "Connected as: $($Context.AppName) | TenantId: $($Context.TenantId)"
Write-Output "Scopes: $($Context.Scopes -join ', ')"

# Perform operations
$Users = Get-MgUser -All -Property DisplayName, UserPrincipalName
```

When using managed identity with the Az modules:

```powershell
# Connect to Azure with managed identity
Connect-AzAccount -Identity

# Access Key Vault (the managed identity needs 'Key Vault Secrets User' role)
$Secret = Get-AzKeyVaultSecret -VaultName 'ms-prod-vault' -Name 'ExternalApiKey' -AsPlainText
```

## Tier 2: Certificate-Based App Registration

This is the most common pattern for scheduled automation running on-premises or on domain-joined servers. The app registration in Entra ID is configured with a certificate, and the script authenticates using the certificate thumbprint.

### Setting Up the App Registration

The app registration should follow the principle of least privilege (CMMC AC.L2-3.1.5). Request only the Graph API permissions the script actually needs, and prefer application permissions over delegated permissions for unattended scripts.

```powershell
# Connecting with certificate thumbprint — certificate must be in LocalMachine\My store
# The app registration in Entra ID must have the certificate's public key uploaded
$ConnectionParams = @{
    ClientId              = $env:MS_GRAPH_APP_ID        # From environment variable
    TenantId              = $env:MS_TENANT_ID           # From environment variable
    CertificateThumbprint = $env:MS_GRAPH_CERT_THUMB    # From environment variable
}
Connect-MgGraph @ConnectionParams

# Always verify and log the connection context
$Context = Get-MgContext
if (-not $Context) {
    throw "Failed to establish Graph connection. Verify certificate and app registration."
}

Write-Output "Authenticated to tenant $($Context.TenantId) as app $($Context.ClientId)"
```

### Certificate Storage and Rotation

Certificates MUST be stored in the Windows certificate store (LocalMachine\My for services, CurrentUser\My for user-context scripts). Private keys MUST be marked as non-exportable in production environments. Certificate rotation SHOULD occur at least 90 days before expiry, and monitoring should alert at 30 days before expiry.

```powershell
# Check certificate expiration — useful in health-check scripts
$Cert = Get-ChildItem -Path Cert:\LocalMachine\My | 
    Where-Object { $_.Thumbprint -eq $env:MS_GRAPH_CERT_THUMB }

$DaysUntilExpiry = ($Cert.NotAfter - (Get-Date)).Days
if ($DaysUntilExpiry -le 30) {
    # Trigger alert — supports CMMC MA.L2-3.7.5 (Maintenance — Nonlocal Maintenance)
    Write-Warning "CERTIFICATE EXPIRY ALERT: Graph auth certificate expires in $DaysUntilExpiry days."
    # Send alert via your preferred channel (email, Teams webhook, etc.)
}
```

## Tier 3: Client Secret with Key Vault

When certificate-based auth is not feasible, client secrets are acceptable ONLY if stored in Azure Key Vault. The script retrieves the secret at runtime — it is never stored in code, config files, environment variables on shared systems, or script parameters.

```powershell
# First authenticate to Azure (using managed identity or certificate)
Connect-AzAccount -Identity

# Retrieve the client secret from Key Vault at runtime
$ClientSecret = Get-AzKeyVaultSecret -VaultName 'ms-prod-vault' -Name 'GraphClientSecret' -AsPlainText

# Build the credential object
$SecureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($AppId, $SecureSecret)

# Connect to Graph with client secret credential
Connect-MgGraph -ClientSecretCredential $Credential -TenantId $TenantId

# Clear the plaintext secret from memory immediately after use
$ClientSecret = $null
[System.GC]::Collect()
```

Key Vault access policies MUST follow least privilege — only the specific service principal or managed identity running the script should have `Get` permission on secrets. Human engineers should NOT have routine access to production Key Vault secrets.

## Tier 4: Interactive / Delegated Authentication

Interactive auth is appropriate for ad-hoc tasks, development, testing, and scenarios where user-context permissions are required (e.g., accessing a specific user's mailbox with delegated permissions).

```powershell
# Interactive connection — will prompt for MFA
# Specify only the scopes you need for this session
Connect-MgGraph -Scopes 'User.Read.All', 'Group.Read.All'

# For Exchange Online
Connect-ExchangeOnline -UserPrincipalName "admin@managedsolution.com"

# For SharePoint Online
Connect-PnPOnline -Url "https://managedsolution.sharepoint.com" -Interactive
```

### Guardrails for Interactive Auth

Even in interactive mode, follow these rules:

REQUIRED: Never use `-Credential` with plaintext passwords in interactive scripts. Always use MFA-capable flows (browser-based, device code).

REQUIRED: Disconnect sessions when finished. Leaving active sessions open violates CMMC AC.L2-3.1.10 (Session Lock) and AC.L2-3.1.11 (Session Termination).

```powershell
# Always disconnect when done — wrap in try/finally to ensure cleanup
try {
    Connect-MgGraph -Scopes 'User.Read.All'
    # ... do work ...
} finally {
    Disconnect-MgGraph
    Write-Output "Graph session disconnected."
}
```

## Multi-Service Authentication

Many scripts need to connect to multiple services (Graph, Exchange Online, SharePoint, Azure). Each service connection should use the same auth tier where possible, and all connections should be established at the beginning of the script and torn down in a `finally` block.

```powershell
#region Authentication
# Establish all service connections upfront
$GraphParams = @{
    ClientId              = $env:MS_GRAPH_APP_ID
    TenantId              = $env:MS_TENANT_ID
    CertificateThumbprint = $env:MS_GRAPH_CERT_THUMB
}
Connect-MgGraph @GraphParams

Connect-ExchangeOnline -CertificateThumbprint $env:MS_EXO_CERT_THUMB `
    -AppId $env:MS_EXO_APP_ID `
    -Organization "managedsolution.onmicrosoft.com"
#endregion

try {
    #region Main Logic
    # ... script operations across both services ...
    #endregion
} finally {
    #region Cleanup
    Disconnect-MgGraph
    Disconnect-ExchangeOnline -Confirm:$false
    Write-Output "All service sessions disconnected."
    #endregion
}
```

## Credential Hygiene Checklist

Every script that handles authentication should satisfy all of the following before being committed to version control:

- No hardcoded credentials, secrets, tokens, or API keys anywhere in the script.
- Authentication tier is appropriate for the execution context (see hierarchy above).
- Service connections are established in a dedicated region/block at script start.
- All connections are torn down in a `finally` block.
- Connection context is logged for audit purposes (app ID, tenant ID, timestamp).
- Certificate expiration is monitored if using Tier 2.
- Key Vault access policies follow least privilege if using Tier 3.
- Scopes/permissions requested follow principle of least privilege.
- No use of `-Credential` with plaintext `PSCredential` objects outside of Key Vault retrieval patterns.

## Migrating from Interactive to Certificate-Based Auth

If you have existing scripts that use interactive auth in production (a known gap we are closing), follow this migration path:

1. Identify the exact Graph/M365 permissions the script requires by reviewing all cmdlet calls.
2. Create an app registration in Entra ID with only those permissions.
3. Generate a self-signed certificate or request one from internal PKI, upload the public key to the app registration.
4. Install the certificate in the appropriate store on the execution host.
5. Replace `Connect-MgGraph -Scopes ...` with the certificate-based connection pattern from Tier 2.
6. Test thoroughly in a non-production tenant.
7. Update the script header to reflect the new auth method and required app registration.
8. Remove any legacy credential references.
