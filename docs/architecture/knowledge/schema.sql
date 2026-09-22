-- Draft for a NEW public knowledge database, not a CRM migration.
-- Requires PostgreSQL and pgvector. No private case files or tenant ACLs here.
-- Run only in an empty development database after selecting the embedding profile.
BEGIN;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE SCHEMA knowledge;

CREATE TABLE knowledge.sources (
    id text PRIMARY KEY,
    publisher text NOT NULL,
    documentation_url text NOT NULL,
    integration_kind text NOT NULL CHECK (integration_kind IN ('api', 'website', 'manual')),
    terms_url text,
    terms_reviewed_at timestamptz,
    last_success_at timestamptz,
    checkpoint jsonb NOT NULL DEFAULT '{}'
);

CREATE TABLE knowledge.documents (
    id uuid PRIMARY KEY,
    source_id text NOT NULL REFERENCES knowledge.sources,
    external_id text NOT NULL,
    canonical_url text NOT NULL,
    title text NOT NULL,
    kind text NOT NULL CHECK (kind IN ('legislation', 'judgment', 'official_guidance')),
    jurisdiction text NOT NULL,
    language text NOT NULL,
    court text,
    case_number text,
    decision_date date,
    UNIQUE (source_id, external_id, language)
);

-- Revisions are immutable evidence snapshots. A correction creates a new row.
-- Publication and legal applicability are distinct from import timestamps.
CREATE TABLE knowledge.revisions (
    id uuid PRIMARY KEY,
    document_id uuid NOT NULL REFERENCES knowledge.documents,
    source_version text NOT NULL,
    source_url text NOT NULL,
    raw_object_key text NOT NULL,
    raw_sha256 text NOT NULL CHECK (raw_sha256 ~ '^[0-9a-f]{64}$'),
    published_on date,
    fetched_at timestamptz NOT NULL,
    parser_version text NOT NULL,
    verified_at timestamptz,
    status text NOT NULL DEFAULT 'quarantined'
        CHECK (status IN ('quarantined', 'published', 'withdrawn')),
    withdrawal_reason text,
    CHECK (status <> 'published' OR verified_at IS NOT NULL),
    CHECK (status <> 'withdrawn' OR withdrawal_reason IS NOT NULL),
    UNIQUE (document_id, source_version, raw_sha256, parser_version)
);

CREATE TABLE knowledge.revision_relations (
    from_revision_id uuid NOT NULL REFERENCES knowledge.revisions,
    to_revision_id uuid NOT NULL REFERENCES knowledge.revisions,
    relation text NOT NULL CHECK (relation IN ('amends', 'repeals', 'consolidates', 'corrects', 'cites')),
    locator text NOT NULL DEFAULT '',
    PRIMARY KEY (from_revision_id, to_revision_id, relation, locator),
    CHECK (from_revision_id <> to_revision_id)
);

CREATE TABLE knowledge.passages (
    id uuid PRIMARY KEY,
    revision_id uuid NOT NULL REFERENCES knowledge.revisions,
    locator text NOT NULL, -- article/paragraph/section, stable within this revision
    ordinal integer NOT NULL CHECK (ordinal >= 0),
    page_start integer CHECK (page_start > 0),
    page_end integer CHECK (page_end >= page_start),
    text_content text NOT NULL CHECK (length(text_content) > 0),
    text_sha256 text NOT NULL CHECK (text_sha256 ~ '^[0-9a-f]{64}$'),
    valid_from date,
    valid_to date, -- exclusive; NULL = no verified end, not proof of current validity
    temporal_status text NOT NULL DEFAULT 'unknown'
        CHECK (temporal_status IN ('verified', 'unknown', 'not_applicable')),
    temporal_evidence_revision_id uuid REFERENCES knowledge.revisions,
    CHECK (valid_to IS NULL OR (valid_from IS NOT NULL AND valid_to > valid_from)),
    CHECK (temporal_status <> 'verified' OR
        (valid_from IS NOT NULL AND temporal_evidence_revision_id IS NOT NULL)),
    search_text tsvector GENERATED ALWAYS AS
        (to_tsvector('simple'::regconfig, text_content)) STORED,
    UNIQUE (revision_id, locator, ordinal)
);
CREATE INDEX passages_revision ON knowledge.passages (revision_id);
CREATE INDEX passages_lexical ON knowledge.passages USING gin (search_text);
CREATE INDEX documents_scope ON knowledge.documents (jurisdiction, kind, language);
CREATE INDEX documents_case_number ON knowledge.documents (case_number);
CREATE INDEX passages_legal_date ON knowledge.passages (valid_from, valid_to)
    WHERE temporal_status = 'verified';

CREATE TABLE knowledge.embedding_profiles (
    id text PRIMARY KEY,
    model text NOT NULL,
    dimensions integer NOT NULL CHECK (dimensions > 0),
    preprocessing_version text NOT NULL,
    UNIQUE (id, dimensions)
);
CREATE TABLE knowledge.embeddings (
    passage_id uuid NOT NULL REFERENCES knowledge.passages,
    profile_id text NOT NULL,
    dimensions integer NOT NULL,
    embedding vector NOT NULL,
    created_at timestamptz NOT NULL,
    PRIMARY KEY (passage_id, profile_id),
    FOREIGN KEY (profile_id, dimensions)
        REFERENCES knowledge.embedding_profiles (id, dimensions),
    CHECK (vector_dims(embedding) = dimensions)
);
-- Add a per-profile partial expression HNSW index only after choosing a model
-- and dimension. Never mix profiles in the similarity query. Initially exact
-- search over filtered candidates provides the benchmark for ANN recall.

CREATE TABLE knowledge.import_runs (
    id uuid PRIMARY KEY,
    source_id text NOT NULL REFERENCES knowledge.sources,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    status text NOT NULL CHECK (status IN ('running', 'succeeded', 'failed')),
    imported_count integer NOT NULL DEFAULT 0 CHECK (imported_count >= 0),
    error_code text, -- no raw source text or secrets
    CHECK ((status = 'running') = (finished_at IS NULL))
);
COMMIT;

-- Retrieval must filter published revisions and temporal applicability before
-- returning evidence. For legislation: temporal_status = 'verified' AND
-- valid_from <= :as_of AND (valid_to IS NULL OR :as_of < valid_to).
-- Do not apply this filter to judgments as if they were legislative enactments.
-- Match document kind explicitly. Unknown applicability yields a warning or
-- clarification, never an assertion that the provision is currently in force.
-- The API role receives SELECT only; an importer role publishes validated data.
