# ===== kabuステーションAPI 発注ツール（現物・確認画面つき） =====
# 使い方: kabuステーションを起動した状態で kabu_order.bat をダブルクリック
# 安全設計:
#   - 上限金額チェック（下の $MAX_ORDER_YEN。超える注文は出せない）
#   - 発注前に現在値と概算金額を表示して最終確認
#   - 取引パスワードは毎回手入力（このツールはどこにも保存しない）
#   - 1回の操作で1注文のみ。自動売買はしない

$MAX_ORDER_YEN = 500000   # ★1注文の上限金額（円）。必要に応じて書き換えてください

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$pwFile = 'C:\Users\takaa\kabu_api_pw.txt'
$apiPw = (Get-Content $pwFile | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1).Trim()

function Get-Token {
  (Invoke-RestMethod -Method Post -Uri 'http://localhost:18080/kabusapi/token' `
    -ContentType 'application/json' -Body (@{APIPassword=$apiPw}|ConvertTo-Json) -TimeoutSec 10).Token
}
function Get-Board($tok, $code) {
  Invoke-RestMethod -Method Get -Uri "http://localhost:18080/kabusapi/board/$code@1" `
    -Headers @{ 'X-API-KEY' = $tok } -TimeoutSec 15
}

# ---------- 画面 ----------
$form = New-Object Windows.Forms.Form
$form.Text = 'kabu 発注ツール（現物）'
$form.Size = '420,360'; $form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false

function Add-Label($t,$x,$y){ $l=New-Object Windows.Forms.Label; $l.Text=$t; $l.Location="$x,$y"; $l.AutoSize=$true; $form.Controls.Add($l); $l }
function Add-Text($x,$y,$w){ $t=New-Object Windows.Forms.TextBox; $t.Location="$x,$y"; $t.Width=$w; $form.Controls.Add($t); $t }
function Add-Combo($x,$y,$w,$items){ $c=New-Object Windows.Forms.ComboBox; $c.Location="$x,$y"; $c.Width=$w; $c.DropDownStyle='DropDownList'; $items|%{[void]$c.Items.Add($_)}; $c.SelectedIndex=0; $form.Controls.Add($c); $c }

Add-Label '銘柄コード' 20 20 | Out-Null
$tbCode = Add-Text 120 18 80
$btnQuote = New-Object Windows.Forms.Button; $btnQuote.Text='現在値'; $btnQuote.Location='210,16'; $btnQuote.Width=70; $form.Controls.Add($btnQuote)
$lbName = Add-Label '—' 20 50

Add-Label '売買' 20 85 | Out-Null
$cbSide = Add-Combo 120 82 100 @('買い','売り')
Add-Label '口座' 240 85 | Out-Null
$cbAcct = Add-Combo 290 82 90 @('特定','一般')

Add-Label '数量(株)' 20 120 | Out-Null
$tbQty = Add-Text 120 118 80
Add-Label '通常は100株単位' 210 120 | Out-Null

Add-Label '注文種別' 20 155 | Out-Null
$cbType = Add-Combo 120 152 100 @('指値','成行')
Add-Label '指値価格(円)' 20 190 | Out-Null
$tbPrice = Add-Text 120 188 80
Add-Label '有効期間: 当日' 240 190 | Out-Null

$lbInfo = Add-Label '銘柄コードを入れて「現在値」を押してください' 20 225
$lbInfo.MaximumSize = '380,0'

$btnOrder = New-Object Windows.Forms.Button
$btnOrder.Text = '💰 買い注文を確認して発注'; $btnOrder.Location = '20,265'; $btnOrder.Size = '360,40'
$btnOrder.BackColor = [Drawing.Color]::FromArgb(220,245,225)
$form.Controls.Add($btnOrder)
$cbSide.Add_SelectedIndexChanged({
  if ($cbSide.SelectedItem -eq '買い') { $btnOrder.Text = '💰 買い注文を確認して発注'; $btnOrder.BackColor = [Drawing.Color]::FromArgb(220,245,225) }
  else { $btnOrder.Text = '📉 売り注文を確認して発注'; $btnOrder.BackColor = [Drawing.Color]::FromArgb(250,225,225) }
})

$btnQuote.Add_Click({
  try {
    $tok = Get-Token
    $b = Get-Board $tok $tbCode.Text.Trim()
    $script:lastPx = $b.CurrentPrice
    $lbName.Text = "$($b.SymbolName)　現在値 $($b.CurrentPrice)円"
    if (-not $tbPrice.Text) { $tbPrice.Text = "$($b.CurrentPrice)" }
  } catch { $lbName.Text = "取得失敗: kabuステーション起動とコードを確認 ($($_.Exception.Message))" }
})

$btnOrder.Add_Click({
  try {
    $code = $tbCode.Text.Trim()
    $qty = [int]$tbQty.Text
    $isBuy = ($cbSide.SelectedItem -eq '買い')
    $isLimit = ($cbType.SelectedItem -eq '指値')
    $price = if ($isLimit) { [double]$tbPrice.Text } else { 0 }
    if (-not ($code -match '^[0-9][0-9A-Z]{3}$')) { throw '銘柄コードが不正です' }
    if ($qty -le 0) { throw '数量を入れてください' }
    if ($isLimit -and $price -le 0) { throw '指値価格を入れてください' }

    $tok = Get-Token
    $b = Get-Board $tok $code
    $ref = if ($isLimit) { $price } else { [double]$b.CurrentPrice }
    $est = [math]::Round($ref * $qty)
    if ($est -gt $MAX_ORDER_YEN) { throw "概算${est}円が上限${MAX_ORDER_YEN}円を超えています（上限はスクリプト冒頭で変更可）" }

    $msg = "以下の内容で発注します。よろしいですか？`n`n" +
           "銘柄: $($b.SymbolName)（$code）`n" +
           "売買: $($cbSide.SelectedItem)（現物・$($cbAcct.SelectedItem)口座）`n" +
           "数量: ${qty}株`n" +
           "種別: $($cbType.SelectedItem)" + $(if($isLimit){" ${price}円"}else{"（現在値 $($b.CurrentPrice)円 付近で約定見込み）"}) + "`n" +
           "概算金額: 約$($est.ToString('N0'))円`n有効期間: 当日"
    $ok = [Windows.Forms.MessageBox]::Show($msg, '発注確認', 'YesNo', 'Warning', 'Button2')
    if ($ok -ne 'Yes') { $lbInfo.Text = 'キャンセルしました'; return }

    # 取引パスワード入力（毎回・保存しない）
    $pf = New-Object Windows.Forms.Form; $pf.Text='取引パスワード'; $pf.Size='300,130'; $pf.StartPosition='CenterParent'; $pf.FormBorderStyle='FixedDialog'
    $pl = New-Object Windows.Forms.Label; $pl.Text='取引パスワードを入力:'; $pl.Location='15,15'; $pl.AutoSize=$true; $pf.Controls.Add($pl)
    $pt = New-Object Windows.Forms.TextBox; $pt.Location='15,40'; $pt.Width=250; $pt.UseSystemPasswordChar=$true; $pf.Controls.Add($pt)
    $pb = New-Object Windows.Forms.Button; $pb.Text='OK'; $pb.Location='105,68'; $pb.DialogResult='OK'; $pf.Controls.Add($pb); $pf.AcceptButton=$pb
    if ($pf.ShowDialog($form) -ne 'OK' -or -not $pt.Text) { $lbInfo.Text='キャンセルしました'; return }

    $body = [ordered]@{
      Password       = $pt.Text
      Symbol         = $code
      Exchange       = 1                                   # 東証
      SecurityType   = 1                                   # 株式
      Side           = if ($isBuy) { '2' } else { '1' }    # 2=買 1=売
      CashMargin     = 1                                   # 現物
      DelivType      = if ($isBuy) { 2 } else { 0 }        # 買=お預り金
      AccountType    = if ($cbAcct.SelectedItem -eq '特定') { 4 } else { 2 }
      Qty            = $qty
      FrontOrderType = if ($isLimit) { 20 } else { 10 }    # 20=指値 10=成行
      Price          = $price
      ExpireDay      = 0                                   # 当日
    }
    if ($isBuy) { $body['FundType'] = 'AA' }               # 買付余力(信用代用)
    $pt.Text = ''

    $r = Invoke-RestMethod -Method Post -Uri 'http://localhost:18080/kabusapi/sendorder' `
      -Headers @{ 'X-API-KEY' = $tok } -ContentType 'application/json' `
      -Body ($body | ConvertTo-Json) -TimeoutSec 20
    if ($r.Result -eq 0) {
      $lbInfo.Text = "発注しました（受付ID: $($r.OrderId)）。約定状況はkabuステーションで確認してください"
      [Windows.Forms.MessageBox]::Show("発注を受け付けました`n受付ID: $($r.OrderId)", '発注完了', 'OK', 'Information') | Out-Null
    } else {
      $lbInfo.Text = "応答: $($r | ConvertTo-Json -Compress)"
    }
  } catch {
    $detail = $_.ErrorDetails.Message
    $lbInfo.Text = "エラー: $($_.Exception.Message)" + $(if($detail){"`n$detail"})
  }
})

[void]$form.ShowDialog()
