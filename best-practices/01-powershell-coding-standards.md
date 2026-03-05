# PowerShell Coding Standards

This document defines the core PowerShell coding standards for all scripts, functions, and modules authored by Managed Solution engineers. These standards apply to all internal tooling, client-facing automation, and any code committed to version control.

## Naming Conventions

### Functions and Cmdlets

All functions MUST use the `Verb-MSNoun` naming pattern, where `Verb` is an approved PowerShell verb (from `Get-Verb`) and `MSNoun` uses the `MS` prefix to identify Managed Solution–authored functions. This prevents collisions with vendor modules and makes our functions immediately identifiable.

```powershell
# CORRECT — uses approved verb and MS-prefixed noun
function Get-MSClientDevice { }
function Set-MSMailboxPermission { }
function New-MSAzureDeployment { }
function Test-MSComplianceBaseline { }

# INCORRECT — missing MS prefix, non-approved verb, or unclear naming
function GetClientDevice { }          # Missing MS prefix
function Fetch-MSClientDevice { }     # "Fetch" is not an approved verb
function Do-MSStuff { }               # Vague noun
```

### Variables

Variables use PascalCase. Avoid abbreviations unless they are universally understood within the team (e.g., `$UPN` for User Principal Name, `$TenantId`). Boolean variables SHOULD be prefixed with a condition indicator.

```powershell
# CORRECT
$UserPrincipalName = "will@managedsolution.com"
$IsEnabled = $true
$HasLicense = $false
$MaxRetryCount = 3

# INCORRECT
$upn = "will@managedsolution.com"     # Lowercase, abbreviated
$flag = $true                          # Ambiguous name
$x = 3                                 # Meaningless name
```

### Parameters

Parameter names use PascalCase and SHOULD be descriptive enough to understand without reading the function body. Use `[Parameter()]` attribute decorators to define mandatory parameters, pipeline input, and validation.

```powershell
# CORRECT — descriptive, validated, well-decorated parameters
function Get-MSUserLicense {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserPrincipalName,

        [Parameter()]
        [ValidateSet('E3', 'E5', 'F1', 'BusinessPremium')]
        [string]$LicenseType
    )
}
```

### Scripts and Files

Script files use the `Verb-MSNoun.ps1` pattern matching the primary function they contain. Module manifest files use the module name with `.psd1` extension. Supporting files should be descriptive.

```
Get-MSClientReport.ps1
Set-MSBulkMailboxPermission.ps1
ManagedSolution.M365/ManagedSolution.M365.psd1
```

## Code Structure

### Script Header Block

Every script MUST begin with a comment-based help block that includes a synopsis, description, parameter documentation, example usage, and author/version metadata. This is REQUIRED for both standalone scripts and exported module functions.

```powershell
<#
.SYNOPSIS
    Retrieves license assignment details for one or more Microsoft 365 users.

.DESCRIPTION
    Connects to Microsoft Graph using the Microsoft.Graph.Users module and
    retrieves license SKU assignments for the specified users. Supports
    pipeline input for bulk operations. Outputs a custom object with
    UPN, assigned SKUs, and assignment timestamp.

    Supports CMMC AC.L2-3.1.1 by validating caller permissions before
    executing Graph queries.

.PARAMETER UserPrincipalName
    The UPN of the target user. Accepts pipeline input.

.PARAMETER IncludeDisabledPlans
    If specified, includes disabled service plans in the output.

.EXAMPLE
    Get-MSUserLicense -UserPrincipalName "user@contoso.com"

.EXAMPLE
    Get-MgUser -All | Get-MSUserLicense

.NOTES
    Author:  Managed Solution Engineering
    Version: 1.0.0
    Date:    2025-01-15
    Requires: Microsoft.Graph.Users v2.x
#>
```

### Strict Mode and Error Preferences

All scripts MUST enable strict mode and set appropriate error action preferences at the top of the script body (after the help block). This catches common bugs like uninitialized variables and type mismatches early.

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
```

### CmdletBinding and Output Types

All functions intended for reuse MUST use `[CmdletBinding()]` and SHOULD declare `[OutputType()]` to support pipeline discovery and static analysis.

```powershell
function Get-MSUserLicense {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param( ... )
    process { ... }
}
```

### Region Blocks

For longer scripts (50+ lines of logic), use `#region` / `#endregion` blocks to organize code into logical sections. Keep region names descriptive.

```powershell
#region Authentication
# Connect to Graph with certificate-based auth
$Connection = Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
#endregion

#region Data Collection
# Query user license assignments
$Users = Get-MgUser -All -Property DisplayName, UserPrincipalName, AssignedLicenses
#endregion

#region Output
# Format and export results
$Users | Select-Object DisplayName, UserPrincipalName, @{N='Licenses';E={...}} |
    Export-Csv -Path $OutputPath -NoTypeInformation
#endregion
```

## Formatting and Style

### Indentation and Spacing

Use 4-space indentation. Never use tabs. Place opening braces on the same line as the statement. Include a blank line between logical sections.

```powershell
# CORRECT
if ($User.IsEnabled) {
    Set-MSUserCompliance -UserPrincipalName $User.UPN -Status 'Active'
} else {
    Write-Warning "User $($User.UPN) is disabled, skipping."
}

# INCORRECT — brace on new line (Allman style is not our convention)
if ($User.IsEnabled)
{
    Set-MSUserCompliance -UserPrincipalName $User.UPN -Status 'Active'
}
```

### Line Length

Lines SHOULD NOT exceed 120 characters. Use splatting for cmdlet calls with many parameters to keep lines readable.

```powershell
# CORRECT — splatted parameters for readability
$SplatParams = @{
    UserId             = $UserPrincipalName
    Property           = @('DisplayName', 'Mail', 'AssignedLicenses')
    ErrorAction        = 'Stop'
}
$User = Get-MgUser @SplatParams

# AVOID — long single-line calls
$User = Get-MgUser -UserId $UserPrincipalName -Property DisplayName,Mail,AssignedLicenses -ErrorAction Stop
```

### String Formatting

Use string interpolation with subexpressions for simple cases. Use `-f` format operator or `[string]::Format()` for complex formatting. Avoid concatenation with `+`.

```powershell
# CORRECT — subexpression interpolation
Write-Output "Processing user: $($User.DisplayName) ($($User.UPN))"

# CORRECT — format operator for complex strings
$LogMessage = "Completed {0} of {1} users ({2:P0} complete)" -f $Processed, $Total, ($Processed / $Total)

# INCORRECT — string concatenation
$LogMessage = "Processing user: " + $User.DisplayName + " (" + $User.UPN + ")"
```

## Pipeline and Performance

### Pipeline Usage

PREFERRED: Use the pipeline for sequential transformations and filtering. Design functions with `process` blocks to support pipeline input. Avoid collecting entire datasets into variables when pipeline streaming is sufficient.

```powershell
# CORRECT — streaming pipeline processing
Get-MgUser -All |
    Where-Object { $_.AssignedLicenses.Count -gt 0 } |
    Select-Object DisplayName, UserPrincipalName |
    Export-Csv -Path $OutputPath -NoTypeInformation

# AVOID when dataset is large — collecting everything into memory first
$AllUsers = Get-MgUser -All
$Licensed = $AllUsers | Where-Object { $_.AssignedLicenses.Count -gt 0 }
```

### Pagination

When working with Graph API calls that return paginated results, ALWAYS use the `-All` parameter when available, or implement manual pagination. Never assume a single call returns all results.

```powershell
# CORRECT — explicit pagination awareness
$Users = Get-MgUser -All -Property DisplayName, UserPrincipalName, AssignedLicenses

# DANGEROUS — may silently return only the first page (default 100)
$Users = Get-MgUser -Property DisplayName, UserPrincipalName, AssignedLicenses
```

## Comment Standards

### When to Comment

Comments explain WHY, not WHAT. If the code is clear enough to read, a comment restating the obvious adds noise. Comment on business logic, compliance rationale, workarounds, and non-obvious decisions.

```powershell
# GOOD — explains why
# Graph API returns disabled plans as GUIDs — we resolve to friendly names
# using the published Microsoft SKU reference table
$FriendlyNames = $DisabledPlans | ForEach-Object { $SkuLookup[$_] }

# BAD — restates the code
# Get all users
$Users = Get-MgUser -All
```

### Inline vs Block Comments

Use inline comments sparingly and only for brief clarifications. Use block comments for multi-line explanations. Never leave commented-out code in committed scripts — use version control history instead.

## Script Security

### No Hardcoded Secrets

REQUIRED (CMMC SC.L2-3.13.10): Never hardcode credentials, API keys, tokens, or secrets in scripts. Use Azure Key Vault, certificate stores, or environment variables managed through secure deployment pipelines.

```powershell
# CORRECT — retrieve secret from Key Vault
$Secret = Get-AzKeyVaultSecret -VaultName 'ms-prod-vault' -Name 'GraphAppSecret' -AsPlainText

# CORRECT — use certificate thumbprint (no secret in code)
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# NEVER DO THIS
$ClientSecret = "abc123-super-secret-value"  # VIOLATION — hardcoded secret
```

### Input Validation

All user-supplied or external input MUST be validated before use. Use `[ValidatePattern()]`, `[ValidateSet()]`, `[ValidateScript()]`, and `[ValidateNotNullOrEmpty()]` parameter attributes. This supports CMMC SI.L2-3.14.1 (System Integrity — Flaw Remediation) by preventing injection and unexpected input.

```powershell
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')]
    [string]$EmailAddress,

    [ValidateRange(1, 100)]
    [int]$BatchSize = 50
)
```

### Execution Policy Awareness

Scripts SHOULD NOT attempt to modify execution policy. Document the required execution policy in the script header and let deployment pipelines or administrators manage policy settings.
