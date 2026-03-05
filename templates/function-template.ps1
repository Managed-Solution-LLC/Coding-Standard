function Verb-MSNoun {
    <#
    .SYNOPSIS
        [Brief description — one line.]

    .DESCRIPTION
        [Detailed description of what this function does, including any
        service dependencies, data flow, and compliance relevance.]

        Compliance Controls: [e.g., AC.L2-3.1.1, AU.L2-3.3.1]

    .PARAMETER ParameterName
        [Description, including valid values, defaults, and pipeline behavior.]

    .EXAMPLE
        Verb-MSNoun -ParameterName "value"
        [What this example does.]

    .EXAMPLE
        Get-MgUser -All | Verb-MSNoun
        [Pipeline usage example.]

    .INPUTS
        [Input types accepted, e.g., System.String, Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser]

    .OUTPUTS
        [Output types returned, e.g., PSCustomObject]

    .NOTES
        Author:      Managed Solution Engineering
        Version:     1.0.0
        Module:      ManagedSolution.[Domain]
        Permissions: [Required Graph/M365 permissions]
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$ParameterName,

        [Parameter()]
        [ValidateSet('OptionA', 'OptionB', 'OptionC')]
        [string]$OptionalParameter = 'OptionA',

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$BatchSize = 100
    )

    begin {
        # Runs once before pipeline processing begins
        # Use for: connection validation, initializing collections, loading lookup data

        # Verify service connection (CMMC AC.L2-3.1.1)
        $Context = Get-MgContext
        if (-not $Context) {
            throw "No active Microsoft Graph connection. Call Connect-MgGraph first."
        }

        # Initialize result collection for pipeline processing
        $ResultCollection = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        # Runs once per pipeline input object
        # Use for: processing individual items

        try {
            if ($PSCmdlet.ShouldProcess($ParameterName, "Describe the action being taken")) {
                # --- YOUR FUNCTION LOGIC HERE ---

                $Result = [PSCustomObject]@{
                    InputValue = $ParameterName
                    Status     = 'Success'
                    Timestamp  = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
                    # Add your output properties here
                }

                $ResultCollection.Add($Result)

                # Output to pipeline immediately (for streaming)
                Write-Output $Result
            }
        } catch {
            if ($_.Exception.Message -match 'Request_ResourceNotFound|404') {
                # Expected error — log and continue pipeline
                Write-Warning "Resource not found for input: $ParameterName"
            } else {
                # Unexpected error — re-throw to let the caller decide
                throw
            }
        }
    }

    end {
        # Runs once after all pipeline processing is complete
        # Use for: summary output, cleanup, final reporting

        Write-Verbose "Processed $($ResultCollection.Count) items."
    }
}