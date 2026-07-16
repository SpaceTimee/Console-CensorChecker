param ([string] $trans, [switch] $loop, [string[]] $targets, [string] $browser = "google-chrome", [int] $port = 443)

do {
    if (Test-Path -LiteralPath $trans -PathType Container) {
        $null = Start-Transcript -LiteralPath (Join-Path $trans "Trans.log") -UseMinimalHeader
    }

    if (-not $IsCoreCLR) {
        Write-Host "该脚本需要在 PowerShell 7.x 环境运行"
    }
    else {
        foreach ($ps1File in Get-ChildItem -LiteralPath $PSScriptRoot "*.ps1") {
            if ($ps1File.FullName -ne $PSCommandPath) { . $ps1File.FullName }
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

        [App]::Welcome()

        [App]::new().Main($browser, $port, {
                param([PSCustomObject] $result)

                [App]::WriteCheckResult($result)
            })

        [App]::Closing()
    }

    if (Test-Path -LiteralPath $trans -PathType Container) { Stop-Transcript }
    if ($loop) { Start-Sleep 60 }
}
while ($loop)

Read-Host "按回车键结束"
