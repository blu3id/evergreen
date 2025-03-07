Function Get-EvergreenApp {
    <#
        .EXTERNALHELP Evergreen-help.xml
    #>
    [OutputType([System.Management.Automation.PSObject])]
    [CmdletBinding(SupportsShouldProcess = $True, HelpURI = "https://stealthpuppy.com/evergreen/use/")]
    [Alias("gea")]
    param (
        [Parameter(
            Mandatory = $True,
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            HelpMessage = "Specify an application name. Use Find-EvergreenApp to list supported applications.")]
        [ValidateNotNull()]
        [System.String] $Name,

        [Parameter(
            Mandatory = $False,
            Position = 1,
            HelpMessage = "Specify a hashtable of parameters to pass to the internal application function.")]
        [System.Collections.Hashtable] $AppParams,

        [Parameter(Mandatory = $False, Position = 2)]
        [System.String] $Proxy,

        [Parameter(Mandatory = $False, Position = 3)]
        [System.Management.Automation.PSCredential]
        $ProxyCredential = [System.Management.Automation.PSCredential]::Empty,

        [Parameter()]
        [System.Management.Automation.SwitchParameter] $SkipCertificateCheck
    )

    begin {
        if ($PSBoundParameters.ContainsKey("Proxy")) {
            Set-ProxyEnv -Proxy $Proxy

            if ($PSBoundParameters.ContainsKey("ProxyCredential")) {
                Set-ProxyEnv -ProxyCredential $ProxyCredential
            }
        }

        # Force Invoke-RestMethodWrapper and Invoke-WebRequestWrapper to ignore certificate errors
        if ($PSBoundParameters.ContainsKey("SkipCertificateCheck")) {
            $script:SkipCertificateCheck = $true
        }
    }

    process {
        # Build a path to the application function
        # This will build a path like: Evergreen/Apps/Get-TeamViewer.ps1
        $Function = [System.IO.Path]::Combine($MyInvocation.MyCommand.Module.ModuleBase, "Apps", "Get-$Name.ps1")
        Write-Verbose -Message "Function path: $Function"

        #region Test that the function exists and run it to return output
        if (Test-Path -Path $Function -PathType "Leaf" -ErrorAction "SilentlyContinue") {
            Write-Verbose -Message "Function exists: $Function."

            # Dot source the function so that we can use it
            # Import function here rather than at module import to reduce IO and memory footprint as the module grows
            # This also allows us to add an application manifest and function without having to re-load the module
            Write-Verbose -Message "Dot sourcing: $Function."
            . $Function

            try {
                # Run the function to grab the application details; pass the per-app manifest to the app function
                # Application manifests are located under Evergreen/Manifests
                $params = @{
                    res = (Get-FunctionResource -AppName $Name)
                }
                if ($PSBoundParameters.ContainsKey("AppParams")) {
                    Write-Verbose -Message "Adding AppParams."
                    $params += $AppParams
                }
                Write-Verbose -Message "Calling: Get-$Name."
                $Output = & Get-$Name @params
            }
            catch {
                Write-Error -Message "Internal application function: $Function, failed with error: $($_.Exception.Message)"
            }
            finally {
                if ($PSBoundParameters.ContainsKey("Proxy")) {
                    Remove-ProxyEnv
                }
            }

            # if we get an object, return it to the pipeline
            # Sort object on the Version property
            if ($PSCmdlet.ShouldProcess($Function, "Return output")) {
                if ($Output) {
                    Write-Verbose -Message "Output result from: $Function."
                    Write-Output -InputObject ($Output | Sort-Object -Property "Ring", "Channel", "Track", @{ Expression = { [System.Version]$_.Version }; Descending = $true } -ErrorAction "SilentlyContinue")
                }
                else {
                    $Msg = "Application function Get-$Name ran, but we failed to capture any output.`nRun 'Get-EvergreenApp -Name $Name -Verbose' to review additional details."
                    throw [System.NullReferenceException]::New($Msg)
                }
            }
        }
        else {
            Write-Information -MessageData "`nPlease list supported application names with Find-EvergreenApp." -InformationAction "Continue"
            Write-Information -MessageData "Find out how to contribute a new application to the Evergreen project at: $($script:resourceStrings.Uri.Docs)." -InformationAction "Continue"
            try {
                $List = Find-EvergreenApp -Name $Name -ErrorAction "SilentlyContinue" -WarningAction "SilentlyContinue"
                $AppList = ($List | Select-Object -ExpandProperty "Name") -join "`n"
            }
            catch {
                $AppList = "No applications match '$Name'"
            }
            Write-Information -MessageData "`n'$Name' not found. Evergreen supports these similar applications:" -InformationAction "Continue"
            Write-Information -MessageData $AppList -InformationAction "Continue"
            Write-Information -MessageData "" -InformationAction "Continue"
            $Msg = "Failed to retrieve manifest for application: $Name."
            throw [System.IO.FileNotFoundException]::New($Msg)
        }
        #endregion
    }

    end {
        # Remove these variables for next run
        Remove-Variable -Name "Output", "Function" -ErrorAction "SilentlyContinue"
        if ($PSBoundParameters.ContainsKey("SkipCertificateCheck")) {
            $script:SkipCertificateCheck = $false
        }
    }
}
