// climan.dev worker — CLI documentation hub
// all lookups and search via Azure Postgres (Hyperdrive)
// no KV bindings
import postgres from "postgres";

const HEADERS = {
  "content-type": "application/json",
  "access-control-allow-origin": "*",
  "cache-control": "public, max-age=86400"
};

export default {
  async fetch(request, env) {
    const url  = new URL(request.url);
    const path = url.pathname;

    if (path === "/robots.txt") {
      return new Response("User-agent: *\nAllow: /\n", {
        headers: { "content-type": "text/plain", "cache-control": "public, max-age=86400" }
      });
    }

    if (path === "/" || path === "") {
      return json({
        service: "climan.dev — CLI documentation hub",
        namespaces: {
          pwsh: "PowerShell 7.4 cmdlets (302 commands, hybrid search)",
          mac:  "macOS man pages (coming soon)",
          ansi: "ANSI escape sequences (coming soon)",
          aws:  "AWS CLI (coming soon)"
        },
        routes: [
          "GET /pwsh/{cmdlet}",
          "GET /pwsh (manifest)",
          "GET /ps/{cmdlet|alias} (alias for /pwsh)",
          "GET /mac/{cmd}",
          "GET /ansi/{alias}",
          "GET /search?q=term&ns=pwsh|mac|ansi|all"
        ],
        search: "hybrid BM25 + dual vector (bge-base-en-v1.5 func+flags)",
        examples: [
          "/pwsh/Get-ChildItem",
          "/pwsh/gci",
          "/search?q=find+files+recursively&ns=pwsh",
          "/search?q=download+file+from+url&ns=pwsh",
          "/search?q=stop+process+by+name&ns=pwsh"
        ]
      });
    }

    // /pwsh manifest
    if (path === "/pwsh" || path === "/pwsh/" || path === "/ps" || path === "/ps/") {
      return pgLookup(env, `
        SELECT key, synopsis, categories, aliases, module
        FROM docs WHERE ns = 'pwsh'
        ORDER BY key
      `, [], rows => json({ namespace: "pwsh", count: rows.length, cmdlets: rows }));
    }

    // /pwsh/{cmdlet} and /ps/{cmdlet}
    const pwshMatch = path.match(/^\/(?:pwsh|ps)\/([A-Za-z0-9%_.:-]+)$/);
    if (pwshMatch) {
      const input = decodeURIComponent(pwshMatch[1]);
      return pgLookup(env, `
        SELECT content FROM docs
        WHERE ns = 'pwsh'
          AND (key ILIKE $1 OR lower($1::text) = ANY(aliases))
        LIMIT 1
      `, [input], rows => {
        if (!rows.length) return notFound({ cmdlet: input });
        return new Response(JSON.stringify(rows[0].content), { headers: HEADERS });
      });
    }

    // /mac manifest
    if (path === "/mac" || path === "/mac/") {
      return pgLookup(env, `
        SELECT key, synopsis FROM docs WHERE ns = 'mac' ORDER BY key
      `, [], rows => json({ namespace: "mac", count: rows.length, commands: rows }));
    }

    // /mac/{cmd} and /man/{cmd} legacy
    const macMatch = path.match(/^\/(?:mac|man)\/([a-zA-Z0-9_.:-]+)$/);
    if (macMatch) {
      const input = macMatch[1].toLowerCase();
      return pgLookup(env, `
        SELECT content FROM docs
        WHERE ns = 'mac' AND key ILIKE $1
        LIMIT 1
      `, [input], rows => {
        if (!rows.length) return notFound({ cmd: input });
        return new Response(JSON.stringify(rows[0].content), { headers: HEADERS });
      });
    }

    // /ansi manifest
    if (path === "/ansi" || path === "/ansi/") {
      return pgLookup(env, `
        SELECT key, synopsis, categories FROM docs WHERE ns = 'ansi' ORDER BY key
      `, [], rows => json({ namespace: "ansi", count: rows.length, sequences: rows }));
    }

    // /ansi/{alias}
    const ansiMatch = path.match(/^\/ansi\/(.+)$/);
    if (ansiMatch) {
      const input = decodeURIComponent(ansiMatch[1]);
      return pgLookup(env, `
        SELECT content FROM docs
        WHERE ns = 'ansi' AND (key = $1 OR $1 = ANY(aliases))
        LIMIT 1
      `, [input], rows => {
        if (!rows.length) return notFound({ alias: input });
        return new Response(JSON.stringify(rows[0].content), { headers: HEADERS });
      });
    }

    // /search
    if (path === "/search") {
      const q   = (url.searchParams.get("q") || "").trim();
      const ns  = (url.searchParams.get("ns") || "pwsh").toLowerCase();
      const cat = url.searchParams.get("cat") || null;
      if (!q) return new Response('{"error":"missing q param"}', { status: 400, headers: HEADERS });
      const qSafe = q.replace(/[|&!():*]/g, " ").trim();
      if (!qSafe) return json({ query: q, count: 0, results: [] });
      return searchHybrid(q, qSafe, ns, cat, env);
    }

    return notFound({});
  }
};

async function searchHybrid(q, qSafe, ns, cat, env) {
  try {
    const embResult = await env.AI.run("@cf/baai/bge-base-en-v1.5", {
      text: [q],
      pooling: "cls"
    });
    const vecStr = "[" + embResult.data[0].join(",") + "]";

    const sql = postgres(env.HYPERDRIVE.connectionString, { max: 1 });

    const nsFilter  = ns === "all" ? sql`` : sql`AND ns = ${ns}`;
    const catFilter = cat ? sql`AND ${cat} = ANY(categories)` : sql``;

    const rows = await sql`
      SELECT ns, key, synopsis, categories, module,
        ROUND((
          ts_rank(
            to_tsvector('english',
              coalesce(key,'') || ' ' ||
              coalesce(embed_func,'') || ' ' ||
              coalesce(embed_flags,'')
            ),
            plainto_tsquery(${qSafe})
          ) * 0.3 +
          GREATEST(
            (1 - (vec_func  <=> ${vecStr}::vector)),
            (1 - (vec_flags <=> ${vecStr}::vector))
          ) * 0.7
        )::numeric, 4) AS score
      FROM docs
      WHERE 1=1
        ${nsFilter}
        ${catFilter}
        AND (
          to_tsvector('english',
            coalesce(key,'') || ' ' ||
            coalesce(embed_func,'') || ' ' ||
            coalesce(embed_flags,'')
          ) @@ plainto_tsquery(${qSafe})
          OR (vec_func  <=> ${vecStr}::vector) < 0.5
          OR (vec_flags <=> ${vecStr}::vector) < 0.5
        )
      ORDER BY score DESC
      LIMIT 10
    `;

    await sql.end();
    return json({ query: q, namespace: ns, count: rows.length, results: rows });

  } catch (err) {
    return new Response(
      JSON.stringify({ error: "search failed", detail: err.message }),
      { status: 500, headers: HEADERS }
    );
  }
}

async function pgLookup(env, query, params, handler) {
  try {
    const sql  = postgres(env.HYPERDRIVE.connectionString, { max: 1 });
    const rows = await sql.unsafe(query, params);
    await sql.end();
    return handler(rows);
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "db error", detail: err.message }),
      { status: 500, headers: HEADERS }
    );
  }
}

function json(obj) {
  return new Response(JSON.stringify(obj), { headers: HEADERS });
}

function notFound(extra) {
  return new Response(
    JSON.stringify({ error: "not found", ...extra }),
    { status: 404, headers: HEADERS }
  );
}