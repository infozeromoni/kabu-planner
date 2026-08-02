<?php
// ===== 株価・信用残取得用の同一オリジン中継プロキシ（Cloudflare Worker の代替）=====
// app.html と同じディレクトリに置くと、サーバー設置版は自動でこれを最優先で使う。
//
// 使い方1: ?url=<https URL>          … ホワイトリスト先を中継（30秒キャッシュ）
// 使い方2: ?margin=7203,8035,...     … 信用残時系列をサーバー側で抽出して軽量JSONで返す
//                                       （最大10銘柄/回・サーバー側24時間キャッシュ＝全端末で共有）
header('Access-Control-Allow-Origin: *');

function fetch_url($url) {
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_MAXREDIRS      => 3,
    CURLOPT_TIMEOUT        => 15,
    CURLOPT_USERAGENT      => 'Mozilla/5.0',
    CURLOPT_HTTPHEADER     => ['Accept: application/json,text/csv,text/html,*/*'],
  ]);
  $body = curl_exec($ch);
  $code = curl_getinfo($ch, CURLINFO_RESPONSE_CODE) ?: 502;
  $ct   = curl_getinfo($ch, CURLINFO_CONTENT_TYPE) ?: 'text/plain; charset=utf-8';
  curl_close($ch);
  return [$body, $code, $ct];
}

// Yahoo!ファイナンスの信用残時系列テーブル(週次)をパースして直近3週分を返す
function parse_margin_html($html) {
  if (!preg_match('/信用残時系列のテーブル.*?<\/table>/su', $html, $m)) return null;
  preg_match_all('/<tr[^>]*>(.*?)<\/tr>/su', $m[0], $trs);
  $out = [];
  foreach ($trs[1] as $tr) {
    preg_match_all('/<t[hd][^>]*>(.*?)<\/t[hd]>/su', $tr, $tds);
    $cells = array_map(fn($c) => trim(str_replace(',', '', strip_tags($c))), $tds[1]);
    if (count($cells) >= 6 && preg_match('#^\d{4}/#', $cells[0])) {
      $out[] = ['dt' => $cells[0], 'sell' => (float)$cells[1], 'buy' => (float)$cells[2],
                'sellChg' => (float)$cells[3], 'buyChg' => (float)$cells[4], 'ratio' => (float)$cells[5]];
    }
    if (count($out) >= 3) break;
  }
  return $out ?: null;
}

// ---- PCのkabuステーション生存信号（スマホの接続マーク用） ----
// set: PC側スクリプトが1分ごとに送信 / get: アプリが読む（180秒以内のokなら起動中と判定）
if (isset($_GET['beat'])) {
  header('Content-Type: application/json; charset=utf-8');
  $bf = sys_get_temp_dir() . '/kabu_beat.json';
  if ($_GET['beat'] === 'set') {
    if (($_GET['k'] ?? '') !== 'zeromoni-beat') { http_response_code(403); echo '{"e":"forbidden"}'; exit; }
    $st = (($_GET['st'] ?? 'ok') === 'ok') ? 'ok' : 'ng';
    @file_put_contents($bf, json_encode(['t' => time(), 'st' => $st]));
    echo '{"r":"ok"}'; exit;
  }
  echo is_file($bf) ? file_get_contents($bf) : '{"t":0,"st":"none"}';
  exit;
}

// ---- 信用残 軽量API ----
if (isset($_GET['margin'])) {
  header('Content-Type: application/json; charset=utf-8');
  $codes = array_slice(
    array_values(array_filter(explode(',', $_GET['margin']), fn($c) => preg_match('/^[0-9][0-9A-Z]{3}$/', $c))),
    0, 10);
  $cd = sys_get_temp_dir() . '/kabu_margin';
  @mkdir($cd, 0700);
  $res = [];
  $fetched = 0;
  foreach ($codes as $c) {
    $cf = $cd . '/' . $c . '.json';
    $nf = $cd . '/' . $c . '.miss';
    if (is_file($cf) && filemtime($cf) > time() - 86400) {           // 週次データなので24時間キャッシュ
      $res[$c] = json_decode(file_get_contents($cf), true);
      continue;
    }
    if (is_file($nf) && filemtime($nf) > time() - 600) {             // 失敗も10分キャッシュ(Yahoo連打防止)
      $res[$c] = null;
      continue;
    }
    if ($fetched > 0) usleep(300000);                                // 取得間隔0.3秒(Yahoo側への配慮)
    [$body, $code2] = fetch_url("https://finance.yahoo.co.jp/quote/{$c}.T/history?styl=margin");
    $fetched++;
    $d = ($body !== false && $code2 === 200) ? parse_margin_html($body) : null;
    if ($d) { @file_put_contents($cf, json_encode($d)); @unlink($nf); }
    else { @touch($nf); }
    $res[$c] = $d;
  }
  echo json_encode($res);
  exit;
}

// ---- 汎用中継（ホワイトリスト方式）----
$allow = ['query1.finance.yahoo.com', 'query2.finance.yahoo.com', 'stooq.com', 'stooq.pl', 'finance.yahoo.co.jp'];
$url = $_GET['url'] ?? '';
$host = parse_url($url, PHP_URL_HOST);
$scheme = parse_url($url, PHP_URL_SCHEME);
$ok = $scheme === 'https' && $host && array_reduce($allow, fn($c, $h) => $c || $host === $h || str_ends_with($host, '.' . $h), false);
if (!$ok) { http_response_code(403); header('Content-Type: text/plain'); echo 'host not allowed'; exit; }

// 30秒キャッシュ（同一URLの連打対策）
$cd = sys_get_temp_dir() . '/kabu_proxy_cache';
@mkdir($cd, 0700);
$cf = $cd . '/' . sha1($url);
if (is_file($cf) && filemtime($cf) > time() - 30) {
  $ct = @file_get_contents($cf . '.ct') ?: 'text/plain; charset=utf-8';
  header('Content-Type: ' . $ct);
  readfile($cf);
  exit;
}

[$body, $code, $ct] = fetch_url($url);
if ($body === false) { http_response_code(502); header('Content-Type: text/plain'); echo 'fetch error'; exit; }
http_response_code($code);
header('Content-Type: ' . $ct);
if ($code === 200) { @file_put_contents($cf, $body); @file_put_contents($cf . '.ct', $ct); }
echo $body;
