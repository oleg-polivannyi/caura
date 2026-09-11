# Local customizations vs upstream

## Upstream identity (verified, not assumed)

- Repo: **https://github.com/caura-ai/caura-memclaw**
- Deployed image build revision: **`9e222a1dba31b33b0e95560ee3ee09620809b119`** (= tag `backend-v2.19.0`)
- Evidence — the still-present upstream image's OCI labels:

  ```bash
  docker inspect ghcr.io/caura-ai/caura-memclaw-core-api:latest \
    --format '{{json .Config.Labels}}'
  # org.opencontainers.image.source = https://github.com/caura-ai/caura-memclaw
  # org.opencontainers.image.revision = 9e222a1dba31b33b0e95560ee3ee09620809b119
  # org.opencontainers.image.title  = caura-memclaw-core-api
  ```

- `caura-ai/caura-memclaw` @ `9e222a1` is byte-identical to `caura-ai/caura` @ tag
  `backend-v2.19.0` (both release tarballs compared file-by-file). They are mirrors.

> **Do not diff against `caura-ai/caura` `main`.** Upstream later renamed the MCP
> tools `memclaw_*` → `caura_*`; our deployed image (and this archive) uses
> `memclaw_*`. The real upstream at the build commit is `caura-memclaw`, whose
> `tools/` are also `memclaw_*` at that revision.

## Genuinely local edits

These are present in the archived `app/` and absent from **both** the upstream
build tag (`9e222a1`) **and** upstream `main` — i.e. they are our edits, not
upstream code.

| Patch | File | Change | Why |
| --- | --- | --- | --- |
| `local-edits/0001-…` | `common/llm/constants.py` | `OPENAI_CHAT_BASE_URL = os.environ.get("OPENAI_CHAT_BASE_URL", "https://api.openai.com/v1")` | Allows pointing the chat/LLM client at a custom OpenAI-compatible host (Polza) via env var, without rebuilding. |
| `local-edits/0002-…` | `common/embedding/_registry.py` | The `if base_url and send_dimensions: raise ValueError(...)` guard is commented out. | A custom embedding host (TEI/vLLM-style) rejects the `dimensions=` kwarg; the upstream guard made that combination a hard startup failure. |
| `local-edits/0003-…` | `common/llm/providers/openai.py` | `OpenAILLMProvider.complete_json` catches `openai.BadRequestError` and retries **once** with `response_format={"type": "json_object"}` when the first attempt used `json_schema`. | Polza's DeepSeek route rejects `json_schema` with HTTP 400 (`does not support 'json_schema' response format`). |

The first two are the "custom API host was unsupported" fixes; the third is the
model-generation fix.

## Upstream evolution that also lives in the archived `app/` (NOT local edits)

The archived runtime contains upstream features that the `backend-v2.19.0` tag
does not — so the image content corresponds to a commit **between** the tag and
`main` (the OCI `revision` label nonetheless says `9e222a1`). These merely show
up as diffs when comparing against the tag; all are present in upstream
`caura-memclaw` `main`, so they are upstream, not custom:

- **CAURA-701** — `semantic` classifier-deprecated, demoted to `fact`
  (`common/enrichment/constants.py`, `_prompts.py`, `service.py`,
  `merge_enrichment_fields.py`, `crystallizer_service.py`, plus message text in
  `routes/memories.py` and `mcp_server.py`).
- **A47** — tenant-wide `search.default_profile`
  (`services/organization_settings.py`, `pipeline/steps/search/resolve_search_profile.py`).
- **reports** — `include_scope_agent` in aggregate/trend/quality queries
  (`routes/reports.py`).
- `services/version_compat.py` — `MIN_RECOMMENDED_PLUGIN_VERSION = "2.13.0"`
  (upstream later moved it to `2.16.0`).
- `services/memory_service.py` — redundant inner `from fastapi import HTTPException`
  removed.

## Where it all lives

Single branch: **`main`** of `https://github.com/oleg-polivannyi/caura`.

- `app/` — the deployed runtime source (all edits below already applied).
- `local-edits/` — the same edits as three standalone patches against upstream
  commit `9e222a1`, each verified to apply cleanly (see `local-edits/README.md`).
- `build/`, `manifests/`, `README.md` — rebuild/deploy tooling and the live
  (secret-redacted) k8s objects.

The fork is an **archive only** — no upstream PR is intended.
