. (Join-Path $PSScriptRoot "App.ps1")

function Invoke-Check {
    <#
    .Synopsis
        Check host targets for tcping latency and censorship. Returns a JSON result with Target and Latency (timeout: 2147483647)
    .Component
        Network
    .Role
        Probe
    .Functionality
        Batch tcping probe & Censor checker
    #>
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage = "Host targets or a target file path to check")]
        [string[]] $targets = $script:targets ?? @(),
        [Parameter(HelpMessage = "Chromium browser path")]
        [string] $browser = $script:browser ?? "google-chrome",
        [Parameter(HelpMessage = "Default port for targets")]
        [int] $port = $script:port ?? 443,
        [switch] $mcp
    )

    if ($mcp) {
        if (-not (Get-Module "pwsh.mcp" -ListAvailable)) {
            Install-PSResource "pwsh.mcp" -TrustRepository -ErrorAction Stop
        }

        Import-Module "pwsh.mcp" -ErrorAction Stop

        $script:targets = $targets
        $script:browser = $browser
        $script:port = $port

        New-MCPServer (Get-Command "Invoke-Check")

        return
    }

    [string] $targetPath = Join-Path $PSScriptRoot "Target.txt"
    [string] $externalTargetPath = Join-Path (Get-Location) "Target.txt"

    if ($targets.Count -eq 1 -and (Test-Path -LiteralPath $targets[0] -PathType Leaf)) {
        Copy-Item -LiteralPath $targets[0] $targetPath -Force
    }
    elseif ($targets.Count -gt 0) {
        Set-Content -LiteralPath $targetPath $targets
    }
    elseif ((Test-Path -LiteralPath $externalTargetPath -PathType Leaf) -and $externalTargetPath -ne $targetPath) {
        Copy-Item -LiteralPath $externalTargetPath $targetPath -Force
    }

    [App]::new().Main($browser, $port, { param([PSCustomObject] $result) $PSCmdlet.WriteObject($result) })
}

Export-ModuleMember "Invoke-Check"
