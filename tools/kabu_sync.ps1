# ===== kabuステーションAPI → kabu-planner 保有タブ同期スクリプト =====
# 使い方: kabuステーションを起動した状態で kabu_sync.bat をダブルクリック
# 出力: C:\Users\takaa\kabu-holds-sync.json
#   → kabu-planner の「バックアップ/復元」からこのファイルを復元すると保有タブに反映
# 発注は一切行いません（照会のみ）

$ErrorActionPreference = 'Stop'
$pwFile = 'C:\Users\takaa\kabu_api_pw.txt'
$outFile = 'C:\Users\takaa\kabu-holds-sync.json'

# APIパスワード読込（空行はスキップ）
$apiPw = (Get-Content $pwFile | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1).Trim()
if (-not $apiPw) { Write-Host 'APIパスワードファイルが空です'; exit 1 }

# トークン発行
$tok = (Invoke-RestMethod -Method Post -Uri 'http://localhost:18080/kabusapi/token' `
  -ContentType 'application/json' -Body (@{APIPassword=$apiPw}|ConvertTo-Json) -TimeoutSec 10).Token
if (-not $tok) { Write-Host 'トークン発行に失敗しました。kabuステーションが起動しているか確認してください'; exit 1 }

# 建玉・保有取得
$positions = Invoke-RestMethod -Method Get -Uri 'http://localhost:18080/kabusapi/positions?product=0' `
  -Headers @{ 'X-API-KEY' = $tok } -TimeoutSec 20
if ($null -eq $positions) { $positions = @() }
$positions = @($positions)

# コード×区分ごとに集約（同一銘柄の複数建玉は数量合算・建値は加重平均）
$groups = @{}
foreach ($p in $positions) {
  if (-not $p.Symbol -or -not ($p.LeavesQty -gt 0)) { continue }
  $isMargin = $p.MarginTradeType -in 1,2,3
  $pos = if ($isMargin) { if ("$($p.Side)" -eq '1') { 'msell' } else { 'mbuy' } } else { 'cash' }
  $key = "$($p.Symbol)|$pos"
  if (-not $groups.ContainsKey($key)) {
    $groups[$key] = [pscustomobject]@{ code=$p.Symbol; pos=$pos; qty=0.0; cost=0.0; day=$p.ExecutionDay }
  }
  $g = $groups[$key]
  $g.qty  += [double]$p.LeavesQty
  $g.cost += [double]$p.Price * [double]$p.LeavesQty
  if ($p.ExecutionDay -and (-not $g.day -or $p.ExecutionDay -lt $g.day)) { $g.day = $p.ExecutionDay }
}

# 同一銘柄に複数区分がある場合は数量の多い方を採用（kabu-plannerは1銘柄1行のため）
$byCode = @{}
foreach ($g in $groups.Values) {
  if (-not $byCode.ContainsKey($g.code) -or $byCode[$g.code].qty -lt $g.qty) { $byCode[$g.code] = $g }
}

$holds = @()
foreach ($g in $byCode.Values) {
  $entry = if ($g.qty -gt 0) { [Math]::Round($g.cost / $g.qty, 1) } else { 0 }
  $buyDate = if ($g.day) {
    $d = "$($g.day)"  # YYYYMMDD
    [long](([datetime]::ParseExact($d,'yyyyMMdd',$null).AddHours(15) - [datetime]'1970-01-01').TotalMilliseconds)
  } else { [long](([datetime]::UtcNow - [datetime]'1970-01-01').TotalMilliseconds) }
  $holds += [ordered]@{ code="$($g.code)"; entry=$entry; qty=$g.qty; tp=$null; sl=$null; pos=$g.pos; on=$true; buyDate=$buyDate }
}

# kabu-planner のバックアップ形式（toushi_holdsのみ）で出力 → 復元すると保有タブだけ置き換わる
$payload = @{ toushi_holds = (ConvertTo-Json -Depth 5 @($holds) -Compress) }
$payload | ConvertTo-Json -Depth 5 | Out-File $outFile -Encoding utf8

Write-Host "取得建玉: $($positions.Count)件 → 保有 $($holds.Count)銘柄 を $outFile に出力しました"
foreach ($h in $holds) {
  $lbl = switch ($h.pos) { 'msell' {'信用売り'} 'mbuy' {'信用買い'} default {'現物'} }
  Write-Host ("  {0} {1} {2}株 建値{3}円" -f $h.code, $lbl, $h.qty, $h.entry)
}
Write-Host ''
Write-Host '→ kabu-planner の「バックアップ/復元」からこのファイルを読み込むと保有タブに反映されます'
