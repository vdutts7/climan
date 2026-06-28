-- climan schema
-- run: psql "host=climan-db.postgres.database.azure.com port=5432 dbname=postgres user=climanadmin sslmode=require" -f schema.sql

-- extensions (already installed, safe to re-run)
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- wipe and recreate
DROP TABLE IF EXISTS docs CASCADE;
DROP TABLE IF EXISTS modules CASCADE;

-- ── docs — one row per CLI command/cmdlet/sequence ──────────────────────────
CREATE TABLE docs (
  -- identity
  ns            TEXT NOT NULL,
  key           TEXT NOT NULL,

  -- full content (returned on exact lookup)
  content       JSONB NOT NULL,

  -- semantic vectors
  embed_func    TEXT,
  embed_flags   TEXT,
  vec_func      vector(768),
  vec_flags     vector(768),

  -- display
  synopsis      TEXT,
  signature     TEXT,
  description   TEXT,

  -- structured / filterable
  categories    TEXT[],
  aliases       TEXT[],
  flags         JSONB,
  examples      JSONB,
  module        TEXT,
  platform      TEXT,
  version       TEXT,
  source        TEXT,

  -- behavioral contract
  exit_codes    JSONB,
  common_errors JSONB,
  env_vars      JSONB,
  output_type   TEXT,

  -- pipe / composition
  stdin_accepts TEXT,
  stdout_shape  TEXT,
  pipe_into     TEXT[],
  pipe_from     TEXT[],
  compose_with  JSONB,

  -- side effects
  requires_sudo BOOLEAN DEFAULT false,
  modifies_sys  BOOLEAN DEFAULT false,
  writes_files  BOOLEAN DEFAULT false,
  side_effects  TEXT[],
  requires      TEXT[],

  -- graph
  see_also      TEXT[],
  cross_ns      JSONB,

  -- provenance
  scraped_at    TIMESTAMPTZ DEFAULT now(),

  PRIMARY KEY (ns, key)
);

-- ── indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX docs_vec_func_idx    ON docs USING hnsw (vec_func vector_cosine_ops);
CREATE INDEX docs_vec_flags_idx   ON docs USING hnsw (vec_flags vector_cosine_ops);
CREATE INDEX docs_fts_idx         ON docs USING GIN (
  to_tsvector('english',
    coalesce(key,'') || ' ' ||
    coalesce(embed_func,'') || ' ' ||
    coalesce(embed_flags,'')
  )
);
CREATE INDEX docs_categories_idx  ON docs USING GIN (categories);
CREATE INDEX docs_aliases_idx     ON docs USING GIN (aliases);
CREATE INDEX docs_pipe_into_idx   ON docs USING GIN (pipe_into);
CREATE INDEX docs_see_also_idx    ON docs USING GIN (see_also);
CREATE INDEX docs_ns_idx          ON docs (ns);
CREATE INDEX docs_module_idx      ON docs (module);
CREATE INDEX docs_platform_idx    ON docs (platform);

-- ── modules — PSGallery metadata ─────────────────────────────────────────────
CREATE TABLE modules (
  id              TEXT PRIMARY KEY,
  version         TEXT,
  owners          TEXT,
  description     TEXT,
  tags            TEXT[],
  downloads       BIGINT,
  direct_deps     INTEGER,
  transitive_deps INTEGER,
  dl_exposure     BIGINT,
  top_dependents  TEXT[],
  deps            TEXT[],
  ecosystem       TEXT,
  gallery_url     TEXT,
  ps_version      TEXT,
  published       TIMESTAMPTZ,
  scraped_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX modules_ecosystem_idx ON modules (ecosystem);
CREATE INDEX modules_downloads_idx ON modules (downloads DESC);

SELECT 'schema created' AS status;
