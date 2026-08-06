# ===== kabuステーション生存信号ビーコン＋公式信用ランキング送信 =====
# 1分ごと: 「このPCでkabuステーションが起動しているか」をさくらサーバーへ送信
# 1時間ごと: kabuステーションAPIの信用ランキング6種を取得してさくらサーバーへ送信
#   → スマホのkabu-plannerでも接続マーク・公式ランキングが見られるようになります
# 使い方: kabu_beat.bat をダブルクリック（ウィンドウを閉じれば停止）

$apiPwFile = 'C:\Users\takaa\kabu_api_pw.txt'
$server = 'https://problem.sakura.ne.jp/kabu/proxy.php'
$key = 'zeromoni-beat'

function Send-Rankings {
  try {
    $apiPw = (Get-Content $script:apiPwFile | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1).Trim()
    $tok = (Invoke-RestMethod -Method Post -Uri 'http://localhost:18080/kabusapi/token' `
      -ContentType 'application/json' -Body (@{APIPassword=$apiPw}|ConvertTo-Json) -TimeoutSec 10).Token
    if (-not $tok) { return $false }
    $out = @{}
    foreach ($t in 8,9,10,11,12,13) {   # 売残増/売残減/買残増/買残減/高倍率/低倍率
      $r = Invoke-RestMethod -Method Get -Uri "http://localhost:18080/kabusapi/ranking?Type=$t&ExchangeDivision=ALL" `
        -Headers @{ 'X-API-KEY' = $tok } -TimeoutSec 15
      $out["$t"] = @($r.Ranking | Select-Object -First 30 | ForEach-Object {
        @{ n=$_.No; c=$_.Symbol; nm=$_.SymbolName; rt=$_.Ratio; b=$_.BuyLastWeekRatio; s=$_.SellLastWeekRatio; ex=$_.ExchangeName; cg=$_.CategoryName } })
      Start-Sleep -Milliseconds 300
    }
    $payload = @{ t = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); r = $out } | ConvertTo-Json -Depth 5 -Compress
    Invoke-RestMethod -Method Post -Uri "$script:server`?rank=set&k=$script:key" `
      -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 20 | Out-Null
    return $true
  } catch { return $false }
}

$lastRank = [datetime]::MinValue
while ($true) {
  $st = 'ng'
  try {
    $c = New-Object Net.Sockets.TcpClient
    $iar = $c.BeginConnect('127.0.0.1', 18080, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(2000) -and $c.Connected) { $st = 'ok' }
    $c.Close()
  } catch {}
  try {
    Invoke-RestMethod -Uri "$server`?beat=set&k=$key&st=$st" -TimeoutSec 25 | Out-Null
    Write-Host "$(Get-Date -Format 'HH:mm:ss') beat: $st"
  } catch {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') beat送信失敗（ネットワーク一時障害の可能性）"
  }
  if ($st -eq 'ok' -and ((Get-Date) - $lastRank).TotalMinutes -ge 60) {
    if (Send-Rankings) { $lastRank = Get-Date; Write-Host "$(Get-Date -Format 'HH:mm:ss') 公式ランキング送信OK" }
    else { Write-Host "$(Get-Date -Format 'HH:mm:ss') 公式ランキング送信失敗（次の周期で再試行）" }
  }
  Start-Sleep -Seconds 60
}
