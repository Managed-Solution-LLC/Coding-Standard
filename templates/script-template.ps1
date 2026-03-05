<#
.SYNOPSIS
    [Brief description of what this script does — one line.]

.DESCRIPTION
    [Detailed description of the script's purpose, behavior, and any
    important operational notes. Include the services it connects to,
    the data it processes, and any side effects.]

    Compliance Controls: [List relevant CMMC controls, e.g., AC.L2-3.1.1, AU.L2-3.3.1]

.PARAMETER [ParameterName]
    [Description of the parameter, including valid values and defaults.]

.EXAMPLE
    .\Verb-MSNoun.ps1 -ParameterName "value"
    [Description of what this example does.]

.EXAMPLE
    .\Verb-MSNoun.ps1 -ParameterName "value" -Verbose
    [Description of what this example does.]

.NOTES
    Author:      Managed Solution Engineering
    Version:     1.0.0
    Date:        [YYYY-MM-DD]
    Requires:    PowerShell 7.2+
    Modules:     [List required modules, e.g., Microsoft.Graph.Users v2.x]
    Auth Method: [Tier 1/2/3/4 — describe which auth method is used]
    Permissions: [List required Graph/M365 permissions]
#>

#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Users'; ModuleVersion = '2.0.0' }

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExampleParameter,

    [Parameter()]
    [ValidateSet('Option1', 'Option2', 'Option3')]
    [string]$ExampleChoice = 'Option1',

    [Parameter()]
    [string]$LogPath = (Join-Path $PSScriptRoot "logs\$(Get-Date -Format 'yyyyMMdd_HHmmss').log")
)

# ============================================================================
# INITIALIZATION
# ============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Enforce TLS 1.2 minimum (CMMC SC.L2-3.13.8)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Script metadata
$ScriptName = $MyInvocation.MyCommand.Name
$ScriptStart = Get-Date
$CorrelationId = [guid]::NewGuid().ToString()

# Ensure log directory exists
$LogDir = Split-Path -Path $LogPath -Parent
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

#region Helper Functions
function Write-MSLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Severity = 'INFO'
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $LogEntry = "[$Timestamp] [$Severity] [$CorrelationId] $Message"

    switch ($Severity) {
        'ERROR' { Write-Error $LogEntry }
        'WARN'  { Write-Warning $LogEntry }
        'DEBUG' { Write-Verbose $LogEntry }
        default { Write-Output $LogEntry }
    }

    $LogEntry | Out-File -FilePath $LogPath -Append -Encoding UTF8
}
#endregion

# ============================================================================
# AUTHENTICATION
# ============================================================================
#region Authentication
Write-MSLog -Message "=== $ScriptName started ==="
Write-MSLog -Message "Parameters: ExampleParameter=$ExampleParameter, ExampleChoice=$ExampleChoice"

# --- CHOOSE ONE AUTH PATTERN AND DELETE THE OTHERS ---

# Tier 1 — Managed Identity (Azure-hosted automation)
# Connect-MgGraph -Identity

# Tier 2 — Certificate-based (on-premises / scheduled tasks)
$GraphParams = @{
    ClientId              = $env:MS_GRAPH_APP_ID
    TenantId              = $env:MS_TENANT_ID
    CertificateThumbprint = $env:MS_GRAPH_CERT_THUMB
}
Connect-MgGraph @GraphParams

# Tier 4 — Interactive (ad-hoc / development only)
# Connect-MgGraph -Scopes 'User.Read.All'

# Validate connection (CMMC AC.L2-3.1.1)
$Context = Get-MgContext
if (-not $Context) {
    throw "Failed to establish Graph connection. Verify authentication configuration."
}
Write-MSLog -Message "Authenticated: AppId=$($Context.ClientId), TenantId=$($Context.TenantId)"
#endregion

# ============================================================================
# MAIN LOGIC
# ============================================================================
try {
    #region Main Logic
    
    # --- YOUR SCRIPT LOGIC HERE ---
    
    # Example: Retrieve users
    $SplatParams = @{
        All      = $true
        Property = @('DisplayName', 'UserPrincipalName', 'AccountEnabled')
    }
    $Users = Get-MgUser @SplatParams
    Write-MSLog -Message "Retrieved $($Users.Count) users from Graph API"

    # Example: Process with error tracking
    $SuccessCount = 0
    $FailCount = 0

    foreach ($User in $Users) {
        try {
            # Process individual user
            if ($PSCmdlet.ShouldProcess($User.UserPrincipalName, "Process user")) {
                # ... processing logic ...
                $SuccessCount++
            }
        } catch {
            $FailCount++
            Write-MSLog -Message "Failed to process $($User.UserPrincipalName): $($_.Exception.Message)" -Severity WARN
        }
    }

    Write-MSLog -Message "Processing complete: $SuccessCount succeeded, $FailCount failed"
    
    #endregion
} catch {
    Write-MSLog -Message "SCRIPT FAILED: $($_.Exception.Message)" -Severity ERROR
    Write-MSLog -Message "Stack trace: $($_.ScriptStackTrace)" -Severity ERROR
    throw
} finally {
    # ============================================================================
    # CLEANUP
    # ============================================================================
    #region Cleanup
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    
    $Duration = (Get-Date) - $ScriptStart
    Write-MSLog -Message "Total execution time: $($Duration.ToString('hh\:mm\:ss'))"
    Write-MSLog -Message "=== $ScriptName finished ==="
    #endregion
}