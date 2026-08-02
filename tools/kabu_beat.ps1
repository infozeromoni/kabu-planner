# ===== kabuステーション生存信号ビーコン =====
# 1分ごとに「このPCでkabuステーションが起動しているか」をさくらサーバーへ送信します。
# スマホでkabu-plannerを開いたとき、接続マークに「PC:API●」と表示できるようになります。
# 使い方: kabu_beat.bat をダブルクリック（最小化ウィンドウで常駐。閉じれば停止）

while ($true) {
  $st = 'ng'
  try {
    $c = New-Object Net.Sockets.TcpClient
    $iar = $c.BeginConnect('127.0.0.1', 18080, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(2000) -and $c.Connected) { $st = 'ok' }
    $c.Close()
  } catch {}
  try {
    Invoke-RestMethod -Uri "https://problem.sakura.ne.jp/kabu/proxy.php?beat=set&k=zeromoni-beat&st=$st" -TimeoutSec 10 | Out-Null
    Write-Host "$(Get-Date -Format 'HH:mm:ss') 送信: $st"
  } catch {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') 送信失敗（ネットワーク一時障害の可能性）"
  }
  Start-Sleep -Seconds 60
}
