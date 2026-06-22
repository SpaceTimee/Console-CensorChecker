. (Join-Path $PSScriptRoot "App.ps1")

function Invoke-Check {
    param ([int] $port = 443)

    function Clear-Host {}

    [App]::new().Main("None", $port) 6>$null
}

Export-ModuleMember Invoke-Check
