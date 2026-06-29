// climan.dev worker - CLI documentation hub
// all lookups and search via Azure Postgres (Hyperdrive)
// adding a namespace = one line in NS_CONFIG + seed script. nothing else.
import postgres from "postgres";

// ── tuning constants ──────────────────────────────────────────────────────────
const CACHE_TTL        = 86400;   // seconds; public CDN cache on all responses
const SEARCH_LIMIT     = 10;      // max results returned per search query
const LOOKUP_LIMIT     = 1;       // max rows for exact key lookup
const VEC_THRESHOLD    = 0.7;     // cosine distance cutoff for vector pre-filter
const BM25_WEIGHT      = 0.3;     // weight for full-text rank in hybrid score
const VEC_WEIGHT       = 0.7;     // weight for vector rank in hybrid score
const SCORE_DECIMALS   = 4;       // decimal places in ROUND(score)
const PG_POOL_SIZE     = 1;       // postgres connections per Worker invocation
const EMBED_MODEL      = "@cf/baai/bge-base-en-v1.5";
const EMBED_POOLING    = "cls";

// ── namespace registry ────────────────────────────────────────────────────────
// keyPrefix: prepended to path segments to build the DB key
//   az:   /az/vm/create        → "az " + "vm create"      = "az vm create"
//   pwsh: /pwsh/Get-ChildItem  → ""   + "Get-ChildItem"   = "Get-ChildItem"
// aliasCol: true = also match against aliases[] column
const NS_CONFIG = {
  pwsh:  { label: "cmdlets",   keyPrefix: "",    aliasCol: true  },
  kusto: { label: "operators", keyPrefix: "",    aliasCol: false },
  az:    { label: "commands",  keyPrefix: "az ", aliasCol: false },
  mac:   { label: "commands",  keyPrefix: "",    aliasCol: false },
  ansi:  { label: "sequences", keyPrefix: "",    aliasCol: true  },
};

const KNOWN_NS = new Set(Object.keys(NS_CONFIG));

const HEADERS = {
  "content-type": "application/json",
  "access-control-allow-origin": "*",
  "cache-control": `public, max-age=${CACHE_TTL}`
};

const HEADERS_TEXT = {
  "content-type": "text/plain",
  "cache-control": `public, max-age=${CACHE_TTL}`
};

export default {
  async fetch(request, env) {
    const url  = new URL(request.url);
    const path = url.pathname;

    // ── robots.txt ────────────────────────────────────────────────────────────
    if (path === "/robots.txt") {
      return new Response("User-agent: *\nAllow: /\n", { headers: HEADERS_TEXT });
    }

    // ── root ──────────────────────────────────────────────────────────────────
    if (path === "/" || path === "") {
      return json({
        service: "climan.dev - CLI documentation hub",
        namespaces: Object.fromEntries(
          Object.entries(NS_CONFIG).map(([ns, c]) => [ns, c.label])
        ),
        routes: [
          "GET /{ns}           manifest",
          "GET /{ns}/{key}     exact lookup",
          "GET /search?q=&ns= hybrid BM25 + vector search",
        ],
        examples: [
          "/pwsh/Get-ChildItem",
          "/kusto/where-operator",
          "/az/vm/create",
          "/az/storage/blob/upload",
          "/search?q=find+files+recursively&ns=pwsh",
          "/search?q=scale+down+kubernetes+nodes&ns=az",
          "/search?q=filter+rows+by+condition&ns=kusto",
        ]
      });
    }

    // ── /search ───────────────────────────────────────────────────────────────
    if (path === "/search") {
      const q   = (url.searchParams.get("q") || "").trim();
      const ns  = (url.searchParams.get("ns") || "all").toLowerCase();
      const cat = url.searchParams.get("cat") || null;
      if (!q) return new Response('{"error":"missing q param"}', { status: 400, headers: HEADERS });
      const qSafe = q.replace(/[|&!():*]/g, " ").replace(/-(?=[a-zA-Z])/g, " ").trim();
      if (!qSafe) return json({ query: q, count: 0, results: [] });
      return searchHybrid(q, qSafe, ns, cat, env);
    }

    // ── /{ns} and /{ns}/{...rest} ─────────────────────────────────────────────
    const parts = path.replace(/^\//, "").split("/");
    const ns    = parts[0].toLowerCase();

    if (!KNOWN_NS.has(ns)) return notFound({ path });

    const cfg = NS_CONFIG[ns];

    // manifest: GET /{ns} or GET /{ns}/
    if (parts.length === 1 || (parts.length === 2 && parts[1] === "")) {
      // az: too many rows for flat list - return service group breakdown
      if (ns === "az") {
        return pgLookup(env, `
          SELECT
            split_part(key, ' ', 2)   AS service,
            count(*)::int             AS count,
            min(synopsis)             AS sample_synopsis
          FROM docs WHERE ns = 'az'
          GROUP BY service ORDER BY service
        `, [], rows => json({
          namespace: "az",
          total: rows.reduce((s, r) => s + r.count, 0),
          services: rows,
          usage: "GET /az/{service}/{command}  e.g. /az/vm/create"
        }));
      }
      return pgLookup(env, `
        SELECT key, synopsis, categories FROM docs
        WHERE ns = $1 ORDER BY key
      `, [ns], rows => json({ namespace: ns, count: rows.length, [cfg.label]: rows }));
    }

    // exact lookup: GET /{ns}/{...rest}
    const segments = parts.slice(1).map(s => decodeURIComponent(s).trim()).filter(Boolean);
    const key = cfg.keyPrefix + segments.join(" ");

    if (cfg.aliasCol) {
      return pgLookup(env, `
        SELECT content FROM docs
        WHERE ns = $1 AND (key ILIKE $2 OR lower($2::text) = ANY(aliases))
        LIMIT ${LOOKUP_LIMIT}
      `, [ns, key], rows => {
        if (!rows.length) return notFound({ ns, key });
        return new Response(JSON.stringify(rows[0].content), { headers: HEADERS });
      });
    }

    return pgLookup(env, `
      SELECT content FROM docs
      WHERE ns = $1 AND key = $2
      LIMIT ${LOOKUP_LIMIT}
    `, [ns, key], rows => {
      if (!rows.length) return notFound({ ns, key });
      return new Response(JSON.stringify(rows[0].content), { headers: HEADERS });
    });
  }
};

// ── hybrid search ─────────────────────────────────────────────────────────────
async function searchHybrid(q, qSafe, ns, cat, env) {
  try {
    const embResult = await env.AI.run(EMBED_MODEL, {
      text: [q], pooling: EMBED_POOLING
    });
    const vecStr = "[" + embResult.data[0].join(",") + "]";
    const sql    = postgres(env.HYPERDRIVE.connectionString, { max: PG_POOL_SIZE });

    const nsFilter  = ns === "all" ? sql`` : sql`AND ns = ${ns}`;
    const catFilter = cat ? sql`AND ${cat} = ANY(categories)` : sql``;

    const rows = await sql`
      SELECT ns, key, synopsis, categories,
        ROUND((
          ts_rank(
            to_tsvector('english',
              coalesce(key,'') || ' ' ||
              coalesce(embed_func,'') || ' ' ||
              coalesce(embed_flags,'')
            ),
            websearch_to_tsquery(${qSafe})
          ) * ${BM25_WEIGHT} +
          GREATEST(
            (1 - (vec_func  <=> ${vecStr}::vector)),
            (1 - (vec_flags <=> ${vecStr}::vector))
          ) * ${VEC_WEIGHT}
        )::numeric, ${SCORE_DECIMALS}) AS score
      FROM docs
      WHERE 1=1
        ${nsFilter}
        ${catFilter}
        AND (
          to_tsvector('english',
            coalesce(key,'') || ' ' ||
            coalesce(embed_func,'') || ' ' ||
            coalesce(embed_flags,'')
          ) @@ websearch_to_tsquery(${qSafe})
          OR (vec_func  <=> ${vecStr}::vector) < ${VEC_THRESHOLD}
          OR (vec_flags <=> ${vecStr}::vector) < ${VEC_THRESHOLD}
        )
      ORDER BY score DESC
      LIMIT ${SEARCH_LIMIT}
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

// ── db helper ─────────────────────────────────────────────────────────────────
async function pgLookup(env, query, params, handler) {
  try {
    const sql  = postgres(env.HYPERDRIVE.connectionString, { max: PG_POOL_SIZE });
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
  return new Response(JSON.stringify({ error: "not found", ...extra }), { status: 404, headers: HEADERS });
}
