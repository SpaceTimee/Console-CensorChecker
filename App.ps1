using namespace System.Diagnostics
using namespace System.IO
using namespace System.Net.WebSockets
using namespace System.Text
using namespace System.Threading

Class App {
    hidden [Process] $browserProcess
    hidden [hashtable[]] $cdpSessions = @()

    [void] Main([string] $browser, [int] $port, [scriptblock] $resultHandler) {
        $this.StartBrowserProcess($browser)
        $this.InvokeTargetChecks($port, $resultHandler)
        $this.StopBrowserProcess()
    }

    static [void] Welcome() {
        try { Clear-Host -ErrorAction Stop } catch { Write-Verbose $_ }
        Write-Host "Console CensorChecker 启动!" -ForegroundColor Red
    }

    hidden [void] StartBrowserProcess([string] $browser) {
        if (-not (Get-Command $browser -CommandType Application -ErrorAction Ignore)) {
            while (-not (Test-Path -LiteralPath $browser -PathType Leaf)) { $browser = (Read-Host "输入 Chromium 内核浏览器路径").Trim("""") }
        }

        $this.browserProcess = Start-Process $browser @(
            "--headless"
            "--remote-debugging-port=9222"
            "--user-data-dir=`"$(Join-Path ([Path]::GetTempPath()) "Console-CensorChecker")`""
            "--no-sandbox"
        ) -PassThru -RedirectStandardError ($global:IsWindows ? "NUL" : "/dev/null") -ErrorAction Stop

        for ([int] $tryCount = 0; $tryCount -lt 30; $tryCount++) {
            Start-Sleep 1

            try {
                $null = Invoke-RestMethod "http://localhost:9222" -OperationTimeoutSeconds 1 -ErrorAction Stop
                return
            }
            catch { continue }
        }

        throw "浏览器调试服务启动超时"
    }

    hidden [void] InvokeTargetChecks([int] $port, [scriptblock] $resultHandler) {
        [string] $targetPath = Join-Path $PSScriptRoot "Target.txt"

        while (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { $targetPath = (Read-Host "输入 Target.txt 文件路径").Trim("""") }

        [string[]] $targets = foreach ($targetLine in Get-Content -LiteralPath $targetPath -ErrorAction Stop) {
            if (($target = $targetLine.Trim())) { $target }
        }

        if ($targets.Count -eq 0) { return }

        [string[]] $formattedTargets = foreach ($target in $targets) {
            [string] $normalizedTarget = $target -replace "\s+"

            if ($normalizedTarget -like "[[]*") {
                $normalizedTarget -match "\]:\d+$" ? $normalizedTarget : "${normalizedTarget}:$port"
            }
            elseif ($normalizedTarget -match "/" -or $normalizedTarget -match "^\d{1,3}(?:\.\d{1,3}){3}-" -or $normalizedTarget -match ":.*:") {
                "[${normalizedTarget}]:$port"
            }
            else {
                $normalizedTarget -match ":\d+$" ? $normalizedTarget : "${normalizedTarget}:$port"
            }
        }

        [hashtable] $targetLookup = @{}
        [hashtable] $seenTargets = @{}

        for ([int] $targetIndex = 0; $targetIndex -lt $targets.Count; $targetIndex++) {
            [string] $targetKey = $targets[$targetIndex]
            if ($seenTargets.ContainsKey($targetKey)) { continue }

            $seenTargets[$targetKey] = $true

            [string] $formattedTarget = $formattedTargets[$targetIndex]
            $targetLookup[$formattedTarget] ??= @()
            $targetLookup[$formattedTarget] += $targetKey
        }

        [string[]] $currentBatch = @()
        [int] $batchCharCount = 0

        [string[][]] $targetBatches = @(
            foreach ($formattedTarget in $formattedTargets) {
                [int] $addedCharCount = $formattedTarget.Length + ($currentBatch.Count -gt 0 ? 1 : 0)

                if ($currentBatch.Count -ge 256 -or $batchCharCount + $addedCharCount -gt 10000) {
                    if ($currentBatch.Count -gt 0) { , $currentBatch }
                    $currentBatch = @()
                    $batchCharCount = 0
                    $addedCharCount = $formattedTarget.Length
                }

                $currentBatch += $formattedTarget
                $batchCharCount += $addedCharCount
            }

            if ($currentBatch.Count -gt 0) { , $currentBatch }
        )

        [string] $providerScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot "Provider.js") -Raw -ErrorAction Stop

        $this.cdpSessions = @(
            for ([int] $batchIndex = 0; $batchIndex -lt $targetBatches.Count; $batchIndex++) {
                [ClientWebSocket] $webSocket = [ClientWebSocket]::new()
                [CancellationTokenSource] $cancellationTokenSource = [CancellationTokenSource]::new(10000)

                $null = $webSocket.ConnectAsync([uri](Invoke-RestMethod "http://localhost:9222/json/new" -Method Put -OperationTimeoutSeconds 10 -ErrorAction Stop).webSocketDebuggerUrl, $cancellationTokenSource.Token).GetAwaiter().GetResult()
                $cancellationTokenSource.Dispose()

                [hashtable] $cdpSession = @{ WebSocket = $webSocket; CdpId = 0 }
                $null = $this.SendCdpCommand($cdpSession, "Page.enable", @{})
                $null = $this.SendCdpCommand($cdpSession, "Page.addScriptToEvaluateOnNewDocument", @{ source = $providerScript })
                $null = $this.SendCdpCommand($cdpSession, "Page.navigate", @{ url = $this.InvokeJsExpression($cdpSession, "$providerScript; getPageUrl()") })
                $cdpSession
            }
        )

        foreach ($cdpSession in $this.cdpSessions) {
            for ([int] $tryCount = 0; $tryCount -lt 30; $tryCount++) {
                if ($this.InvokeJsExpression($cdpSession, "isPageReady()")) { break }

                Start-Sleep 1
            }

            if ($tryCount -eq 30) { throw "检测页面加载超时" }
        }

        for ([int] $batchIndex = 0; $batchIndex -lt $targetBatches.Count; $batchIndex++) {
            [hashtable] $cdpSession = $this.cdpSessions[$batchIndex]
            $null = $this.InvokeJsExpression($cdpSession, "focusTargetTextarea()")
            $null = $this.SendCdpCommand($cdpSession, "Input.insertText", @{ text = ($targetBatches[$batchIndex] -join "`n") })
            Start-Sleep 1
            $null = $this.InvokeJsExpression($cdpSession, "clickStartButton()")
        }

        [bool[]] $completedBatches = [bool[]]::new($targetBatches.Count)
        [int] $completedBatchCount = 0
        [datetime] $checkStartTime = Get-Date
        [hashtable] $completedTargets = @{}

        while ($completedBatchCount -lt $targetBatches.Count) {
            Start-Sleep 1

            for ([int] $batchIndex = 0; $batchIndex -lt $targetBatches.Count; $batchIndex++) {
                if ($completedBatches[$batchIndex]) { continue }

                [bool] $batchTimedOut = [int]((Get-Date) - $checkStartTime).TotalSeconds -ge ($targetBatches[$batchIndex].Count + 10)
                [string] $batchResultJson = $this.InvokeJsExpression($this.cdpSessions[$batchIndex], "getResultData($(ConvertTo-Json (-not $batchTimedOut) -Compress))")

                foreach ($batchResult in ([string]::IsNullOrWhiteSpace($batchResultJson) ? @() : @(ConvertFrom-Json $batchResultJson))) {
                    if ($null -eq $batchResult.target -or -not $targetLookup.ContainsKey($batchResult.target) -or $completedTargets.ContainsKey($batchResult.target)) { continue }

                    $completedTargets[$batchResult.target] = $true
                    [int[]] $targetLatencies = @($batchResult.latencies)
                    [int] $targetLatency = [int]::MaxValue

                    if ($targetLatencies.Count -gt 0) {
                        [int] $timeoutCount = 0
                        [int] $totalLatency = 0

                        foreach ($latency in $targetLatencies) {
                            if ($latency -eq -1) { $timeoutCount++ }
                            $totalLatency += ($latency -eq -1 ? 300 : $latency)
                        }

                        $targetLatency = $timeoutCount -ge 3 ? [int]::MaxValue : [int]($totalLatency / $targetLatencies.Count)
                    }

                    foreach ($targetKey in $targetLookup[$batchResult.target]) {
                        $this.InvokeResultHandler($targetKey, $targetLatency, $resultHandler)
                    }
                }

                [bool] $batchCompleted = $true

                foreach ($formattedTarget in $targetBatches[$batchIndex]) {
                    if ($completedTargets.ContainsKey($formattedTarget)) { continue }

                    $batchCompleted = $false
                    break
                }

                if (-not $batchTimedOut -and -not $batchCompleted) { continue }

                if ($batchTimedOut) {
                    foreach ($formattedTarget in $targetBatches[$batchIndex]) {
                        if ($completedTargets.ContainsKey($formattedTarget)) { continue }

                        $completedTargets[$formattedTarget] = $true

                        foreach ($targetKey in $targetLookup[$formattedTarget]) {
                            $this.InvokeResultHandler($targetKey, [int]::MaxValue, $resultHandler)
                        }
                    }
                }

                $completedBatches[$batchIndex] = $true
                $completedBatchCount++
            }
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
            Stop-Process $this.browserProcess -ErrorAction Ignore
            Wait-Process $this.browserProcess -ErrorAction Ignore
        }

        $this.browserProcess.Dispose()
        $this.browserProcess = $null
    }

    static [void] WriteCheckResult([PSCustomObject] $result) {
        Write-Host "$($result.Target): $($result.Latency -eq [int]::MaxValue ? "超时" : "$($result.Latency) ms")"
    }

    static [void] Closing() {
        Write-Host "检测结果仅供参考" -ForegroundColor Red
    }

    hidden [PSCustomObject] SendCdpCommand([hashtable] $cdpSession, [string] $method, [hashtable] $params) {
        if ($cdpSession.WebSocket.State -ne [WebSocketState]::Open) { return $null }

        try { $null = $cdpSession.WebSocket.SendAsync([ArraySegment[byte]]::new([Encoding]::UTF8.GetBytes((ConvertTo-Json @{ id = ++$cdpSession.CdpId; method = $method; params = $params } -Compress))), [WebSocketMessageType]::Text, $true, [CancellationToken]::None).GetAwaiter().GetResult() }
        catch { return $null }

        [byte[]] $receiveBuffer = [byte[]]::new(32KB)
        [CancellationTokenSource] $cancellationTokenSource = [CancellationTokenSource]::new(10000)

        for ([int] $tryCount = 0; $tryCount -lt 30; $tryCount++) {
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
        if ($null -eq $cdpResponse -or $null -ne $cdpResponse.result.exceptionDetails) { return $null }

        return $cdpResponse.result.result.value
    }

    hidden [void] InvokeResultHandler([string] $target, [int] $latency, [scriptblock] $resultHandler) {
        if ($null -eq $resultHandler) { return }

        & $resultHandler ([PSCustomObject] @{ Target = $target; Latency = $latency })
    }
}
