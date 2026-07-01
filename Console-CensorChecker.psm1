. (Join-Path $PSScriptRoot "App.ps1")

function Invoke-Check {
    [CmdletBinding()]
    param ([string[]] $targets, [int] $port = 443)

    [string] $targetPath = Join-Path $PSScriptRoot "Target.txt"
    [string] $externalTargetPath = Join-Path (Get-Location) "Target.txt"

    if ($targets.Count -gt 0) {
        Set-Content -LiteralPath $targetPath $targets
    }
    elseif ((Test-Path -LiteralPath $externalTargetPath -PathType Leaf) -and $externalTargetPath -ne $targetPath) {
        Copy-Item -LiteralPath $externalTargetPath -Destination $targetPath -Force
    }

    [App]::new().Main($port, { param([PSCustomObject] $result) $PSCmdlet.WriteObject($result) })
}

Export-ModuleMember Invoke-Check
