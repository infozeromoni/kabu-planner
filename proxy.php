<?php
// ===== 株価・信用残取得用の同一オリジン中継プロキシ（Cloudflare Worker の代替）=====
// app.html と同じディレクトリに置くと、サーバー設置版は自動でこれを最優先で使う。
// 取得先はホワイトリスト方式。30秒キャッシュ付き。
header('Access-Control-Allow-Origin: *');

$allow = ['query1.finance.yahoo.com','query2.finance.yahoo.com','stooq.com','stooq.pl','finance.yahoo.co.jp'];
$url = $_GET['url'] ?? '';
$host = parse_url($url, PHP_URL_HOST);
$scheme = parse_url($url, PHP_URL_SCHEME);
$ok = $scheme === 'https' && $host && array_reduce($allow, fn($c, $h) => $c || $host === $h || str_ends_with($host, '.' . $h), false);
if (!$ok) { http_response_code(403); header('Content-Type: text/plain'); echo 'host not allowed'; exit; }

// 30秒キャッシュ（同一URLの連打対策・スキャン時の負荷軽減）
$cd = sys_get_temp_dir() . '/kabu_proxy_cache';
@mkdir($cd, 0700);
$cf = $cd . '/' . sha1($url);
if (is_file($cf) && filemtime($cf) > time() - 30) {
  $ct = @file_get_contents($cf . '.ct') ?: 'text/plain; charset=utf-8';
  header('Content-Type: ' . $ct);
  readfile($cf);
  exit;
}

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

if ($body === false) { http_response_code(502); header('Content-Type: text/plain'); echo 'fetch error'; exit; }
http_response_code($code);
header('Content-Type: ' . $ct);
if ($code === 200) { @file_put_contents($cf, $body); @file_put_contents($cf . '.ct', $ct); }
echo $body;
