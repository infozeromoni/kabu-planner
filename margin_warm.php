<?php
// ===== さくらのcron用（任意）: 信用残キャッシュの夜間まとめ補充 =====
// proxy.php の「ついで温め」だけでも回りますが、PCを止めている日もキャッシュを
// 完成させたい場合にcron登録してください。1回の実行で最大20銘柄・3秒間隔の低負荷。
//
// さくらコントロールパネル → スクリプト設定 → cron設定 で新規登録:
//   実行コマンド: /usr/local/bin/php /home/problem/www/kabu/margin_warm.php
//   スケジュール: 毎日 2時〜4時の15分おき（分: 0,15,30,45 / 時: 2,3,4）
//
// ※proxy.phpと同じキャッシュ(cache/margin)を共有します

define('MARGIN_DIR', __DIR__ . '/cache/margin');
$codesFile = __DIR__ . '/margin_codes.txt';
if (!is_file($codesFile)) { echo "margin_codes.txt がありません\n"; exit(1); }
@mkdir(MARGIN_DIR, 0705, true);

function fetch_url2($url) {
  $ch = curl_init($url);
  curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER=>true, CURLOPT_FOLLOWLOCATION=>true, CURLOPT_MAXREDIRS=>3,
    CURLOPT_TIMEOUT=>15, CURLOPT_USERAGENT=>'Mozilla/5.0']);
  $b = curl_exec($ch); $c = curl_getinfo($ch, CURLINFO_RESPONSE_CODE) ?: 502; curl_close($ch);
  return [$b, $c];
}
function parse_margin2($html) {
  if (!preg_match('/信用残時系列のテーブル.*?<\/table>/su', $html, $m)) return null;
  preg_match_all('/<tr[^>]*>(.*?)<\/tr>/su', $m[0], $trs);
  $out = [];
  foreach ($trs[1] as $tr) {
    preg_match_all('/<t[hd][^>]*>(.*?)<\/t[hd]>/su', $tr, $tds);
    $cells = array_map(fn($c) => trim(str_replace(',', '', strip_tags($c))), $tds[1]);
    if (count($cells) >= 6 && preg_match('#^\d{4}/#', $cells[0]))
      $out[] = ['dt'=>$cells[0],'sell'=>(float)$cells[1],'buy'=>(float)$cells[2],
                'sellChg'=>(float)$cells[3],'buyChg'=>(float)$cells[4],'ratio'=>(float)$cells[5]];
    if (count($out) >= 3) break;
  }
  return $out ?: null;
}

$done = 0; $ok = 0;
foreach (file($codesFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $c) {
  if ($done >= 20) break;
  $c = trim($c);
  if (!preg_match('/^[0-9][0-9A-Z]{3}$/', $c)) continue;
  $cf = MARGIN_DIR . "/$c.json"; $nf = MARGIN_DIR . "/$c.miss";
  if (is_file($cf) && filemtime($cf) > time() - 72000) continue;
  if (is_file($nf) && filemtime($nf) > time() - 600) continue;
  if ($done > 0) sleep(3);
  [$body, $code] = fetch_url2("https://finance.yahoo.co.jp/quote/{$c}.T/history?styl=margin");
  $d = ($body !== false && $code === 200) ? parse_margin2($body) : null;
  if ($d) { file_put_contents($cf, json_encode($d)); @unlink($nf); $ok++; }
  else { touch($nf); }
  $done++;
}
echo date('Y-m-d H:i:s') . " warm: {$ok}/{$done}\n";
