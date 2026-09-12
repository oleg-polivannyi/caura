# MemClaw backend v3.8.1 — patched build & live migration record

Status: **DONE (2026-09-12)**. Live memory in k3s namespace `memclaw`
(`root@ne.enpire.ru`) runs on backend **v3.8.1** carrying all three of our local
patches. The Postgres database was upgraded in place `alembic 033 -> 044`.

This file records the upgrade that followed the original `backend-v2.19.0` build
documented in `README.md` / `LOCAL-CUSTOMIZATIONS.md`. The three local edits did
**not** change; only their base moved forward.

## Upstream target

| | |
| --- | --- |
| Upstream repo | `https://github.com/caura-ai/caura-memclaw` |
| Tag | `backend-v3.8.1` |
| core-api image revision | `daa3e63f28104266378f06b74a16a4fbdf465c48` |
| Base images | `ghcr.io/caura-ai/caura-memclaw-core-api:v3.8.1`, `ghcr.io/caura-ai/caura-memclaw-core-storage-api:v3.8.1` |

Notes on API compatibility with our tooling (checked at 3.8.1):

- `memclaw_*` MCP tool names are still accepted upstream as permanent aliases
  (`if name.startswith("memclaw_"): name = "caura_" + ...`).
- `CAURA_*` env vars keep back-compat reads for the old names.
- Single-node topology is still just `core-api` + `core-storage-api`
  (the new `core-worker` / `core-operations` processes are optional).

## The patched image

`build/v3.8.1/` contains a reproducible overlay: the Dockerfile starts from the
upstream `core-api:v3.8.1` image and COPYs our three patched files over `/app`
(the files are in `build/v3.8.1/app/`). `build/v3.8.1/rebuild.sh` builds it,
verifies all three markers, and imports it into the k3s containerd store.

| Patch | File | v3.8.1 status |
| --- | --- | --- |
| 0001 env-overridable `OPENAI_CHAT_BASE_URL` | `common/llm/constants.py` | applied cleanly |
| 0002 allow custom embedding endpoint + `dimensions=` | `common/embedding/_registry.py` | applied cleanly (guard commented out) |
| 0003 `json_schema -> json_object` fallback on HTTP 400 | `common/llm/providers/openai.py` | **hand-rewritten** — upstream refactored `complete_json`; the provider class was renamed `OpenAIProvider` -> `OpenAILLMProvider`. The rewritten catch of `openai.BadRequestError` + retry with `{"type":"json_object"}` is in `build/v3.8.1/app/...`. |

Built image: `memclaw-core-api:v3.8.1`
(`sha256:3c6b3ca10b50e52ff1ac7e5f014ef02bdc4ed535e39179221d1204dda01744cc`).
The 3 patches were re-verified *inside the running pod* after deploy.

## New requirement: CORE_STORAGE_SHARED_SECRET

3.8.1 refuses to boot without a shared secret between core-api and storage-api:

- core-api: `app.py::_validate_startup_settings` raises
  `RuntimeError("CORE_STORAGE_SHARED_SECRET is required for core-api")`.
- storage-api: enforces it in `RequireStorageSharedSecretMiddleware`.

Fix: one key `core-storage-shared-secret` in Secret `memclaw-secret`, mounted as
`CORE_STORAGE_SHARED_SECRET` into **both** deployments (same value).

## storage-api start fix: worker healthcheck

`common/serve.py --timeout-worker-healthcheck` defaults to **5 s**. storage-api's
lifespan runs the synchronous `init_database()` (alembic), which blocks the event
loop; with `--workers 2` the uvicorn parent SIGKILLs the unresponsive worker in a
loop (`Child process N died`) and the service never listens.

The live `memclaw-storage-api` therefore runs with an explicit command override:

```
python -m common.serve core_storage_api.app:app \
  --settings core_storage_api.config:settings \
  --host 0.0.0.0 --port 8002 --workers 1 \
  --timeout-keep-alive 65 --timeout-worker-healthcheck 300
```

## DATABASE_URL gotcha

storage-api does **not** build `DATABASE_URL` from `POSTGRES_*` (its only
auto-build path is `ALLOYDB_*`), so `DATABASE_URL` must be set explicitly and
correctly. A generated manifest using `postgresql+asyncpg://memclaw:$(DB_PASSWORD)@...`
was wrong twice over: the env var is named `POSTGRES_PASSWORD`, and K8s only
expands `$(VAR)` for vars defined **earlier** in the same container's env list.

## Database migration (033 -> 044, ~20 migrations)

Run as a one-off pod against DB `memclaw`, *before* swapping the deployments, so
a failure never touches a running service:

```
kubectl -n memclaw apply -f migrate-live.json   # storage-api:v3.8.1, workers not relevant here
# command: python -c "import asyncio; from core_storage_api.database.init import init_database; asyncio.run(init_database())"
# env: DATABASE_URL=postgresql+asyncpg://memclaw:$(DB_PASSWORD)@memclaw-pg:5432/memclaw, ENVIRONMENT=production, POSTGRES_REQUIRE_SSL=false
```

Pre-cutover counts `memories=853 entities=3084 relations=2368 links=4340`
were preserved; post-cutover `alembic_version=044`; new tables
`memory_conflicts`, `tenant_usage_counters` and new memory columns
`content_hash`, `embedded_content_hash`, `is_inferred`, `search_vector`,
`subject_entity_id` present.

## Cutover sequence (as executed)

1. Fresh `pg_dump -Fc` backup + capture of the live manifests.
2. `kubectl -n memclaw scale deploy memclaw-api --replicas=0` (freeze writes).
3. One-off migration pod on DB `memclaw` -> alembic 044.
4. Patch `memclaw-storage-api`: image `...core-storage-api:v3.8.1`,
   `imagePullPolicy: IfNotPresent` (was `:latest` + `Always` — the drift risk is
   gone), `strategy: Recreate` (the node has only 4 GiB, ~95 % requested, so a
   RollingUpdate briefly cannot schedule a second pod), command override above,
   add `CORE_STORAGE_SHARED_SECRET`.
5. Patch `memclaw-api`: image `memclaw-core-api:v3.8.1`, `strategy: Recreate`,
   add `CORE_STORAGE_SHARED_SECRET`; scale back to 1.
6. Verify: `GET /api/v1/health` -> `200 {"status":"ok","storage":"connected",
   "redis":"connected","event_bus":"ok"}`; write + recall smoke test passed;
   MCP `memclaw_*` recall returns the new 3.8.1 `score_parts` response shape.
7. Remove the scratch side-by-side stack (`memclaw-v3-api`,
   `memclaw-v3-storage-api`, scratch DB `memclaw_v3`).

## Backup / rollback

- Pre-cutover dump: `memclaw-cutover-20260912T120806Z.dump`
  (19 430 885 bytes, sha256
  `59e9869a9dd33279ba8f9195c906673f1aab66118615461356e5368f547242f6`).
  Held on the host in `/root/memclaw-migration/` and locally in
  `~/backups/memclaw/`.
- Rollback: restore that dump, then
  `kubectl -n memclaw set image deploy/memclaw-api api=memclaw-core-api:v6` and
  `... deploy/memclaw-storage-api storage-api=ghcr.io/caura-ai/caura-memclaw-core-storage-api:latest`
  (2.27.0), and remove `CORE_STORAGE_SHARED_SECRET`. The DB is then back at 033
  only if the dump is restored — the apps and the schema version must move
  together.

## Operational notes

- Entity extraction on 3.8.1 is a fire-and-forget background task
  (`schedule_background_tasks` -> `process_entity_extraction`). On the Polza
  DeepSeek route it is slow (first attempt often `APITimeoutError`, then a retry;
  ~30–60 s+ to land). A freshly written memory can legitimately have zero
  `memory_entity_links` for a minute — not a failure.
- The recall classifier may pick `entity_lookup` for identifier-looking queries;
  such a query can miss a memory whose entity links have not landed yet.
- No IaC: the deployments live only in the cluster. `manifests/deployment.yaml`
  in this repo is a captured snapshot and predates this migration.
