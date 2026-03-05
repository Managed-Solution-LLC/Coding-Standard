# Module Structure

This document defines how Managed Solution engineers structure PowerShell modules for internal tooling and reusable automation. Modules are the primary packaging mechanism for code that is shared across scripts, teams, or clients. A well-structured module is easy to discover, test, version, and maintain.

## When to Build a Module vs a Script

A standalone script (`.ps1`) is appropriate when the code performs a single, self-contained task that is unlikely to be reused by other scripts. A module (`.psm1` + `.psd1`) is appropriate when the code contains functions that multiple scripts or engineers will call, when you want to version and distribute the code as a unit, or when the functionality is complex enough to benefit from organized file separation.

The practical test is simple: if you find yourself copying a function from one script into another, that function belongs in a module.

## Directory Layout

Every module MUST follow this standard directory structure. The module name uses the `ManagedSolution.<Domain>` naming convention to namespace our modules and prevent collisions.

```
ManagedSolution.M365/
├── ManagedSolution.M365.psd1          # Module manifest (metadata, exports, dependencies)
├── ManagedSolution.M365.psm1          # Root module file (dot-sources function files)
├── Public/                             # Exported functions (visible to module consumers)
│   ├── Get-MSUserLicense.ps1
│   ├── Set-MSMailboxPermission.ps1
│   └── New-MSComplianceReport.ps1
├── Private/                            # Internal helper functions (not exported)
│   ├── Write-MSLog.ps1
│   ├── Test-MSGraphConnection.ps1
│   └── ConvertTo-MSFriendlyLicense.ps1
├── Data/                               # Static data files (lookup tables, config defaults)
│   └── LicenseSkuMap.json
├── Tests/                              # Pester tests
│   ├── Get-MSUserLicense.Tests.ps1
│   └── ManagedSolution.M365.Tests.ps1
└── README.md                           # Module documentation
```

### Public vs Private Functions

The `Public/` folder contains functions that are exported by the module and available to consumers. Every function in `Public/` should be a fully documented, `[CmdletBinding()]`-decorated advanced function that follows all standards from the PowerShell Coding Standards document.

The `Private/` folder contains helper functions used internally by the module. These are dot-sourced by the root module file but NOT exported. They don't need to meet the same documentation bar as public functions, but they should still follow naming conventions and include basic error handling.

## Root Module File (.psm1)

The root module file is responsible for dot-sourcing all function files and performing any module-level initialization. Keep it simple — it should not contain function definitions directly.

```powershell
# ManagedSolution.M365.psm1

# Dot-source all public and private function files
$PublicFunctions = @(Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1" -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue)

foreach ($Function in @($PublicFunctions + $PrivateFunctions)) {
    try {
        . $Function.FullName
    } catch {
        Write-Error "Failed to import function: $($Function.FullName). Error: $_"
    }
}

# Export only the public functions
Export-ModuleMember -Function $PublicFunctions.BaseName

# Module-level initialization (optional)
# Load static data files
$script:LicenseSkuMap = Get-Content -Path "$PSScriptRoot/Data/LicenseSkuMap.json" -Raw | ConvertFrom-Json
```

## Module Manifest (.psd1)

The manifest file defines module metadata, version, dependencies, and exported members. It is REQUIRED for every module and MUST be kept accurate as functions are added or removed.

```powershell
# ManagedSolution.M365.psd1
@{
    # Module identity
    RootModule        = 'ManagedSolution.M365.psm1'
    ModuleVersion     = '1.2.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'  # Generate with [guid]::NewGuid()
    Author            = 'Managed Solution Engineering'
    CompanyName       = 'Managed Solution'
    Description       = 'PowerShell module for Microsoft 365 administration tasks at Managed Solution. Provides standardized functions for user management, licensing, mailbox operations, and compliance reporting.'

    # Compatibility
    PowerShellVersion = '7.2'
    
    # Dependencies — list all required modules with minimum versions
    RequiredModules   = @(
        @{ ModuleName = 'Microsoft.Graph.Users'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.0.0' }
    )

    # Exported members — only Public functions are exported
    FunctionsToExport = @(
        'Get-MSUserLicense'
        'Set-MSMailboxPermission'
        'New-MSComplianceReport'
    )

    # Do not wildcard-export anything else
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    # Private data for module metadata
    PrivateData = @{
        PSData = @{
            Tags       = @('M365', 'ManagedSolution', 'Compliance', 'Graph')
            ProjectUri = 'https://github.com/managed-solution/ManagedSolution.M365'
        }
    }
}
```

### Version Numbering

Use semantic versioning (`Major.Minor.Patch`). Increment the major version when you make breaking changes to existing function signatures. Increment the minor version when you add new functions or non-breaking features. Increment the patch version for bug fixes and documentation updates.

Update the manifest's `FunctionsToExport` list every time you add or remove a public function. A wildcard (`'*'`) in `FunctionsToExport` is NEVER acceptable — it bypasses the public/private boundary.

## Individual Function Files

Each function lives in its own `.ps1` file, named identically to the function it contains. One function per file, no exceptions. This makes functions individually discoverable, testable, and reviewable in pull requests.

```powershell
# Public/Get-MSUserLicense.ps1

function Get-MSUserLicense {
    <#
    .SYNOPSIS
        Retrieves license assignment details for a Microsoft 365 user.
    
    .DESCRIPTION
        Queries Microsoft Graph to retrieve the license SKU assignments
        for the specified user. Returns a custom object with UPN,
        assigned SKUs resolved to friendly names, and assignment details.
    
    .PARAMETER UserPrincipalName
        The UPN of the target user. Accepts pipeline input.
    
    .EXAMPLE
        Get-MSUserLicense -UserPrincipalName "will@managedsolution.com"
    
    .EXAMPLE
        Get-MgUser -All | Get-MSUserLicense
    
    .NOTES
        Author:  Managed Solution Engineering
        Version: 1.2.0
        Required Permissions: User.Read.All (Application)
        Compliance: AC.L2-3.1.1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$UserPrincipalName
    )

    begin {
        # Verify Graph connection exists
        $Context = Get-MgContext
        if (-not $Context) {
            throw "No active Microsoft Graph connection. Call Connect-MgGraph first."
        }
    }

    process {
        try {
            $User = Get-MgUser -UserId $UserPrincipalName -Property DisplayName, UserPrincipalName, AssignedLicenses -ErrorAction Stop
            
            # Resolve license SKU GUIDs to friendly names using module-level lookup
            $FriendlyLicenses = foreach ($License in $User.AssignedLicenses) {
                $FriendlyName = $script:LicenseSkuMap.PSObject.Properties | 
                    Where-Object { $_.Value -eq $License.SkuId } | 
                    Select-Object -ExpandProperty Name
                if ($FriendlyName) { $FriendlyName } else { $License.SkuId }
            }

            [PSCustomObject]@{
                DisplayName       = $User.DisplayName
                UserPrincipalName = $User.UserPrincipalName
                Licenses          = $FriendlyLicenses
                LicenseCount      = $FriendlyLicenses.Count
                RawSkuIds         = $User.AssignedLicenses.SkuId
            }
        } catch {
            if ($_.Exception.Message -match 'Request_ResourceNotFound') {
                Write-Warning "User not found: $UserPrincipalName"
            } else {
                throw
            }
        }
    }
}
```

## Testing with Pester

Every module SHOULD include Pester tests. At minimum, every public function should have tests that verify parameter validation works correctly, expected output structure is returned for valid input, and error handling behaves as designed for invalid input or simulated failures.

```powershell
# Tests/Get-MSUserLicense.Tests.ps1

Describe 'Get-MSUserLicense' {
    BeforeAll {
        # Mock the Graph connection and API calls
        Mock Get-MgContext { return @{ TenantId = 'test-tenant'; ClientId = 'test-app' } }
        Mock Get-MgUser {
            [PSCustomObject]@{
                DisplayName       = 'Test User'
                UserPrincipalName = 'test@managedsolution.com'
                AssignedLicenses  = @(@{ SkuId = '06ebc4ee-1bb5-47dd-8120-11324bc54e06' })
            }
        }
    }

    It 'Returns a PSCustomObject with expected properties' {
        $Result = Get-MSUserLicense -UserPrincipalName 'test@managedsolution.com'
        $Result | Should -BeOfType [PSCustomObject]
        $Result.PSObject.Properties.Name | Should -Contain 'DisplayName'
        $Result.PSObject.Properties.Name | Should -Contain 'UserPrincipalName'
        $Result.PSObject.Properties.Name | Should -Contain 'Licenses'
    }

    It 'Throws when no Graph connection exists' {
        Mock Get-MgContext { return $null }
        { Get-MSUserLicense -UserPrincipalName 'test@managedsolution.com' } | Should -Throw "*No active Microsoft Graph connection*"
    }

    It 'Writes a warning for non-existent users instead of throwing' {
        Mock Get-MgUser { throw "Request_ResourceNotFound" }
        Get-MSUserLicense -UserPrincipalName 'ghost@managedsolution.com' 3>&1 | Should -BeLike "*User not found*"
    }
}
```

## Module Distribution

For internal distribution, modules should be stored in a shared PowerShell repository (e.g., an Azure Artifacts feed or a file share configured as a PSRepository). Avoid distributing modules by copying folders manually — use `Install-Module` or `Save-Module` from the registered repository.

If you do not yet have an internal PSRepository set up, storing the module in a Git repository and cloning it to the `$env:PSModulePath` on target systems is an acceptable interim approach.
