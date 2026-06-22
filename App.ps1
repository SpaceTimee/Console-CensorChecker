using namespace System.Collections
using namespace System.Collections.Specialized
using namespace System.Diagnostics
using namespace System.IO
using namespace System.Net.WebSockets
using namespace System.Text
using namespace System.Threading

Class App {
    hidden [Process] $browserProcess
    hidden [hashtable[]] $cdpSessions = @()

    [OrderedDictionary] Main([string] $order, [int] $port) {
        $this.Welcome()
        $this.StartBrowserProcess()

        [OrderedDictionary] $targetResults = $this.InvokeTargetChecks($port)

        $this.WriteCheckResult($targetResults, $order)
        $this.StopBrowserProcess()
        $this.Closing()

        return $targetResults
    }

    hidden [void] Welcome() {
        try { Clear-Host -ErrorAction Stop } catch { Write-Verbose $_ }
        Write-Host "Console CensorChecker 启动!" -ForegroundColor Red
    }

    hidden [void] StartBrowserProcess() {
        [string] $browserPath = "google-chrome"

        if (-not (Get-Command $browserPath -CommandType Application -ErrorAction Ignore)) {
            while (-not (Test-Path -LiteralPath $browserPath -PathType Leaf)) { $browserPath = (Read-Host "输入 Chromium 内核浏览器路径").Trim("""") }
        }

        $this.browserProcess = Start-Process $browserPath "--headless --remote-debugging-port=9222 --user-data-dir=""$(Join-Path ([Path]::GetTempPath()) "Console-CensorChecker")""" -PassThru -RedirectStandardError ($global:IsWindows ? "NUL" : "/dev/null") -ErrorAction Stop

        for ([int] $tryCount = 0; $tryCount -lt 10; $tryCount++) {
            Start-Sleep 1

            try {
                $null = Invoke-RestMethod "http://localhost:9222" -OperationTimeoutSeconds 1 -ErrorAction Stop
                return
            }
            catch { continue }
        }

        throw "浏览器调试服务启动超时"
    }

    hidden [OrderedDictionary] InvokeTargetChecks([int] $port) {
        [string] $targetPath = Join-Path $PSScriptRoot "Target.txt"

        while (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { $targetPath = (Read-Host "输入 Target.txt 文件路径").Trim("""") }

        [string[]] $targets = foreach ($targetLine in Get-Content -LiteralPath $targetPath -ErrorAction Stop) {
            [string] $target = $targetLine.Trim()
            if (-not [string]::IsNullOrEmpty($target)) { $target }
        }

        if ($targets.Count -eq 0) { return [ordered]@{} }

        [string[]] $formattedTargets = foreach ($target in $targets) {
            [string] $normalizedTarget = $target -replace "\s+"

            if ($normalizedTarget -like "[[]*") {
                $normalizedTarget -match "\]:\d+$" ? $normalizedTarget : "$($normalizedTarget):$port"
            }
            elseif ($normalizedTarget -match "/" -or $normalizedTarget -match "^\d{1,3}(?:\.\d{1,3}){3}-" -or $normalizedTarget -match ":.*:") {
                "[$($normalizedTarget)]:$port"
            }
            else {
                $normalizedTarget -match ":\d+$" ? $normalizedTarget : "$($normalizedTarget):$port"
            }
        }

        [string[]] $currentTargetBatch = @()
        [int] $batchCharCount = 0

        [string[][]] $targetBatches = @(
            foreach ($formattedTarget in $formattedTargets) {
                [int] $addedCharCount = $formattedTarget.Length + ($currentTargetBatch.Count -gt 0 ? 1 : 0)

                if ($currentTargetBatch.Count -ge 256 -or $batchCharCount + $addedCharCount -gt 10000) {
                    if ($currentTargetBatch.Count -gt 0) { , $currentTargetBatch }
                    $currentTargetBatch = @()
                    $batchCharCount = 0
                    $addedCharCount = $formattedTarget.Length
                }

                $currentTargetBatch += $formattedTarget
                $batchCharCount += $addedCharCount
            }

            if ($currentTargetBatch.Count -gt 0) { , $currentTargetBatch }
        )

        [string] $jsScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot "Provider.js") -Raw -ErrorAction Stop

        $this.cdpSessions = @(
            for ([int] $batchIndex = 0; $batchIndex -lt $targetBatches.Count; $batchIndex++) {
                [ClientWebSocket] $webSocket = [ClientWebSocket]::new()
                [CancellationTokenSource] $cancellationTokenSource = [CancellationTokenSource]::new(10000)

                $null = $webSocket.ConnectAsync([uri](Invoke-RestMethod "http://localhost:9222/json/new" -Method Put -OperationTimeoutSeconds 10 -ErrorAction Stop).webSocketDebuggerUrl, $cancellationTokenSource.Token).GetAwaiter().GetResult()
                $cancellationTokenSource.Dispose()

                [hashtable] $cdpSession = @{ WebSocket = $webSocket; CdpId = 0 }
                $null = $this.SendCdpCommand($cdpSession, "Page.enable", @{})
                $null = $this.SendCdpCommand($cdpSession, "Page.addScriptToEvaluateOnNewDocument", @{ source = $jsScript })
                $null = $this.SendCdpCommand($cdpSession, "Page.navigate", @{ url = $this.InvokeJsExpression($cdpSession, "$jsScript; getPageUrl()") })
                $cdpSession
            }
        )

        foreach ($cdpSession in $this.cdpSessions) {
            for ([int] $tryCount = 0; $tryCount -lt 10; $tryCount++) {
                if ($this.InvokeJsExpression($cdpSession, "isPageReady()")) { break }

                Start-Sleep 1
            }

            if ($tryCount -eq 10) { throw "检测页面加载超时" }
        }

        for ([int] $batchIndex = 0; $batchIndex -lt $targetBatches.Count; $batchIndex++) {
            $null = $this.InvokeJsExpression($this.cdpSessions[$batchIndex], "fillTargetTextarea($(ConvertTo-Json ($targetBatches[$batchIndex] -join "`n") -Compress))")
            $null = $this.InvokeJsExpression($this.cdpSessions[$batchIndex], "clickStartButton()")
        }


        [bool[]] $completedBatches = [bool[]]::new($targetBatches.Count)
        [int] $completedBatchCount = 0
        [datetime] $checkStartTime = Get-Date

        [PSCustomObject[]] $allBatchResults = @(
            while ($completedBatchCount -lt $targetBatches.Count) {
                Start-Sleep 1

                for ([int] $batchIndex = 0; $batchIndex -lt $targetBatches.Count; $batchIndex++) {
                    if ($completedBatches[$batchIndex]) { continue }
                    if ([int]((Get-Date) - $checkStartTime).TotalSeconds -lt ($targetBatches[$batchIndex].Count + 10) -and $this.InvokeJsExpression($this.cdpSessions[$batchIndex], "getResultCount()") -lt $targetBatches[$batchIndex].Count) { continue }

                    $completedBatches[$batchIndex] = $true
                    $completedBatchCount++
                    $this.GetBatchResults($this.cdpSessions[$batchIndex])
                }
            }
        )

        [hashtable] $latencyLookup = @{}

        foreach ($batchResult in $allBatchResults) {
            if ($null -ne $batchResult.target) { $latencyLookup[$batchResult.target] = $batchResult.latencies }
        }

        [OrderedDictionary] $targetResults = [ordered]@{}

        for ([int] $targetIndex = 0; $targetIndex -lt $targets.Count; $targetIndex++) {
            [string] $targetKey = $targets[$targetIndex]
            if ($targetResults.Contains($targetKey)) { continue }

            [string] $formattedTargetKey = $formattedTargets[$targetIndex]

            if (-not $latencyLookup.ContainsKey($formattedTargetKey)) {
                $targetResults[$targetKey] = [int]::MaxValue
                continue
            }

            [int[]] $targetLatencies = @($latencyLookup[$formattedTargetKey])

            if ($targetLatencies.Count -eq 0) {
                $targetResults[$targetKey] = [int]::MaxValue
                continue
            }

            [int] $timeoutCount = 0
            [int] $latencyTotal = 0

            foreach ($targetLatency in $targetLatencies) {
                if ($targetLatency -eq -1) {
                    $timeoutCount++
                    $latencyTotal += 300
                }
                else {
                    $latencyTotal += $targetLatency
                }
            }

            $targetResults[$targetKey] = $timeoutCount -ge 3 ? [int]::MaxValue : [int]($latencyTotal / $targetLatencies.Count)
        }

        return $targetResults
    }

    hidden [PSCustomObject[]] GetBatchResults([hashtable] $cdpSession) {
        [string] $batchResultJson = $this.InvokeJsExpression($cdpSession, "getResultData()")

        return ([string]::IsNullOrWhiteSpace($batchResultJson) ? @() : @(ConvertFrom-Json $batchResultJson -ErrorAction Stop))
    }

    hidden [void] WriteCheckResult([OrderedDictionary] $targetResults, [string] $order) {
        [DictionaryEntry[]] $resultEntries = @($targetResults.GetEnumerator())

        switch ($order) {
            "Asc" { $resultEntries = @($resultEntries | Sort-Object Value -Stable) }
            "Desc" { $resultEntries = @($resultEntries | Sort-Object Value -Descending -Stable) }
        }

        foreach ($resultEntry in $resultEntries) {
            Write-Host "$($resultEntry.Key): $($resultEntry.Value -eq [int]::MaxValue ? "超时" : "$($resultEntry.Value) ms")"
        }
    }

    hidden [void] StopBrowserProcess() {
        foreach ($cdpSession in $this.cdpSessions) {
            try {
                if ($cdpSession.WebSocket.State -eq [WebSocketState]::Open) { $null = $cdpSession.WebSocket.CloseAsync([WebSocketCloseStatus]::NormalClosure, [string]::Empty, [CancellationToken]::None).GetAwaiter().GetResult() }
            }
            catch { continue }
            finally { $cdpSession.WebSocket.Dispose() }
        }

        $this.cdpSessions = @()

        if ($null -eq $this.browserProcess) { return }

        if (-not $this.browserProcess.HasExited) {
            Stop-Process $this.browserProcess -ErrorAction Stop
            $this.browserProcess.WaitForExit()
        }

        $this.browserProcess.Dispose()
        $this.browserProcess = $null
    }

    hidden [void] Closing() {
        Write-Host "检测结果仅供参考" -ForegroundColor Red
    }

    hidden [PSCustomObject] SendCdpCommand([hashtable] $cdpSession, [string] $method, [hashtable] $params) {
        if ($cdpSession.WebSocket.State -ne [WebSocketState]::Open) { return $null }

        try { $null = $cdpSession.WebSocket.SendAsync([ArraySegment[byte]]::new([Encoding]::UTF8.GetBytes((ConvertTo-Json @{ id = ++$cdpSession.CdpId; method = $method; params = $params } -Compress))), [WebSocketMessageType]::Text, $true, [CancellationToken]::None).GetAwaiter().GetResult() }
        catch { return $null }

        [byte[]] $receiveBuffer = [byte[]]::new(32KB)
        [CancellationTokenSource] $cancellationTokenSource = [CancellationTokenSource]::new(10000)

        for ([int] $readAttempt = 0; $readAttempt -lt 30; $readAttempt++) {
            if ($cdpSession.WebSocket.State -ne [WebSocketState]::Open) { return $null }

            [PSCustomObject] $cdpResponse = $null

            try {
                [byte[]] $responseBytes = @()

                do {
                    [WebSocketReceiveResult] $receiveResult = $cdpSession.WebSocket.ReceiveAsync([ArraySegment[byte]]::new($receiveBuffer), $cancellationTokenSource.Token).GetAwaiter().GetResult()

                    if ($receiveResult.MessageType -eq [WebSocketMessageType]::Close) { return $null }
                    if ($receiveResult.Count -gt 0) { $responseBytes += $receiveBuffer[0..($receiveResult.Count - 1)] }
                }
                while (-not $receiveResult.EndOfMessage)

                if ($responseBytes.Count -eq 0) { continue }

                $cdpResponse = ConvertFrom-Json ([Encoding]::UTF8.GetString($responseBytes))
            }
            catch {
                if ($cancellationTokenSource.IsCancellationRequested) { return $null }
                continue
            }

            if ($cdpResponse.id -eq $cdpSession.CdpId) {
                $cancellationTokenSource.Dispose()
                return $cdpResponse
            }
        }

        $cancellationTokenSource.Dispose()
        return $null
    }

    hidden [object] InvokeJsExpression([hashtable] $cdpSession, [string] $jsExpression) {
        [PSCustomObject] $cdpResponse = $this.SendCdpCommand($cdpSession, "Runtime.evaluate", @{ expression = $jsExpression; returnByValue = $true })

        return $null -eq $cdpResponse ? $null : $cdpResponse.result.result.value
    }
}
