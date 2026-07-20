// ===== 株価取得用プロキシ（Cloudflare Worker）=====
// 公開CORSプロキシが不安定な時の恒久対策。無料・カード不要。
// デプロイ後の URL（https://xxx.workers.dev）をツールの「自前プロキシURL」に貼る。
//
// 【デプロイ手順】
// 1. https://dash.cloudflare.com でアカウント作成（無料）
// 2. 左メニュー「Workers & Pages」→「Create」→「Create Worker」
// 3. 名前は何でもOK（例 kabu-proxy）→「Deploy」
// 4. 「Edit code」を開き、中身を全部消してこのファイルの内容を貼り付け→「Deploy」
// 5. 表示された https://xxx.workers.dev をコピー
// 6. ツールの「⚙️ 接続設定・診断」→「自前プロキシURL」に貼って「保存」
// これで自動取得が安定します。

export default {
  async fetch(request) {
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "*",
    };
    if (request.method === "OPTIONS") return new Response(null, { headers: cors });

    const target = new URL(request.url).searchParams.get("url");
    if (!target) return new Response("missing ?url=", { status: 400, headers: cors });

    // 安全のため取得先を株価サイトに限定
    let host;
    try { host = new URL(target).hostname; } catch { return new Response("bad url", { status: 400, headers: cors }); }
    const allow = ["query1.finance.yahoo.com", "query2.finance.yahoo.com", "stooq.com", "stooq.pl",
                   "finance.yahoo.co.jp"]; // 信用残時系列（発掘タブの信用残リスクチェック用）
    if (!allow.some(h => host === h || host.endsWith("." + h))) {
      return new Response("host not allowed", { status: 403, headers: cors });
    }

    try {
      const r = await fetch(target, {
        headers: { "User-Agent": "Mozilla/5.0", "Accept": "application/json,text/csv,*/*" },
        cf: { cacheTtl: 30, cacheEverything: true },
      });
      const body = await r.text();
      return new Response(body, {
        status: r.status,
        headers: { ...cors, "Content-Type": r.headers.get("content-type") || "text/plain; charset=utf-8" },
      });
    } catch (e) {
      return new Response("fetch error: " + e, { status: 502, headers: cors });
    }
  },
};
