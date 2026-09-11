# memclaw-patches

Patch archive for the **custom MemClaw deployment** at `https://memclaw.enpire.ru/mcp`
(k3s namespace `memclaw`, host `root@ne.enpire.ru`).

The running image `memclaw-core-api:v5` was built outside this host and **no source
repository exists on the server** (only the built image). This repo exists so that
our local patches are never lost, are reproducible, and can be applied to the
upstream project.

---

## Why this repo exists

- The k3s namespace has **no IaC / Helm / manifest source** — config lives only
  in-cluster and is applied ad-hoc with `kubectl`.
- The container image has **no build source on the host**, so edits would
  otherwise be invisible.
- We needed a real code fix (not just env) for the Polza `json_schema` 400 errors
  breaking entity extraction — see [`patches/`](patches/).

## Layout

```
app/                     full /app source tree extracted from memclaw-core-api:v5 (VERSION 2.19.0)
                         commit 1 = pristine v5 baseline, commit 2 = our patches applied
manifests/               k8s objects exported from the live cluster (secrets redacted)
  deployment.yaml          Deployments: memclaw-api, memclaw-pg, memclaw-redis, memclaw-storage-api
  service.yaml             Services
  configmap.yaml           kube-root-ca.crt only
  memclaw-api.env.txt      sanitised env of the memclaw-api container (secret refs by name)
build/
  rebuild.sh             rebuild memclaw-core-api:v6 from v5 + app/  (run on the host)
  deploy.sh              switch deployment to v6 (+ timeout) and wait for rollout
  rollback.sh            last-resort rollback to v5
  Dockerfile.patch       the equivalent Dockerfile fragment (for documentation)
patches/                 git-format-patch output (one .patch per commit)
```

Baseline provenance:
- image `docker.io/library/memclaw-core-api:v5` (image id `622f2af8897b`, built 2 months before 2026-09-11)
- `/app/VERSION` = `2.19.0`; `PLUGIN`/core-api version differs from upstream main (see "Upstream").

## Secrets

No secret **values** are stored here. `memclaw-secret` keys referenced by the
deployment are: `admin-api-key`, `api-key`, `db-password`, `openai-api-key`.
`SETTINGS_ENCRYPTION_KEY` was a plain env value in the live manifest and is
**redacted** here — read it from the cluster:

```bash
kubectl -n memclaw get deploy memclaw-api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SETTINGS_ENCRYPTION_KEY")].value}'
```

## Upstream

The product is CAURA's **caura-memclaw**, Apache-2.0:

- source: `https://github.com/caura-ai/caura-memclaw`
- published image: `ghcr.io/caura-ai/caura-memclaw-core-api:latest`
  (revision `9e222a1dba31b33b0e95560ee3ee09620809b119`, 2026-07-05)

Our image is **much older than upstream main** (`backend-v3.8.1` at the time of
writing vs our `core-api 2.19.0`), so upstream main cannot be used as the patch
base directly. We keep the exact deployed tree in `app/` as the base, and the
individual changes as git commits on top.

The `openai.py` provider is essentially identical upstream, so the patch below
**also applies cleanly to upstream** — see `patches/` and the fork instructions
at the end.

---

## The patch (commit 2)

**File:** `app/common/llm/providers/openai.py`
**Function:** `OpenAILLMProvider.complete_json`

**Problem.** `entity_extraction.py` passes
`response_schema=ExtractedGraph.model_json_schema()`, so `complete_json` sends
`response_format={"type": "json_schema", ...}`. Polza's DeepSeek route rejects
that with HTTP 400 instead of ignoring it:

```
"Model 'deepseek/deepseek-v4.1-flash' does not support 'json_schema' response
 format. Supported formats: json_object."
```

Every entity extraction therefore failed (2 retries) and fell back to fake
extraction. The provider docstring claimed unsupported providers "ignore this
kwarg" — they do not.

**Fix.** Wrap the chat-completions call: if the request used `json_schema` and
the endpoint returns `openai.BadRequestError`, retry **once** with shape-less
`{"type": "json_object"}`. The prompt still specifies the schema and the
caller's Pydantic parse (`ExtractedGraph(**raw)`) remains the guardrail.
Providers that *do* support `json_schema` are unaffected.

## Build & deploy (on the host)

```bash
scp build/rebuild.sh build/deploy.sh root@ne.enpire.ru:/root/memclaw-patches/
ssh root@ne.enpire.ru 'cd /root/memclaw-patches && ./rebuild.sh && ./deploy.sh'
```

- `rebuild.sh` copies the patched `openai.py` into a container created from
  `memclaw-core-api:v5`, deletes the stale `__pycache__` entry, commits
  `memclaw-core-api:v6`, tags it `registry.enpire.ru/memclaw-core-api:v6`, saves
  it and imports it into the k3s containerd namespace `k8s.io`.
- `deploy.sh` sets the image and `OPENAI_REQUEST_TIMEOUT_SECONDS=120` (the
  DeepSeek route can take ~84 s on large content; the code default is 25 s) and
  waits for the rollout.

## Rollback

```bash
cd /root/memclaw-patches && ./rollback.sh
```

Or manually:

```bash
kubectl -n memclaw set image deployment/memclaw-api api=memclaw-core-api:v5
kubectl -n memclaw rollout status deployment/memclaw-api
```

## Verification signal

After a memory write, `memclaw-api` logs should show the fallback firing and a
successful call — and never `All LLM providers failed for entity-extraction`:

```
WARNING Provider rejected json_schema response_format for model deepseek/deepseek-v4.1-flash; retrying with json_object
INFO    OpenAI-compatible complete_json (deepseek/deepseek-v4.1-flash) took <N>ms
```

## Preserving this in GitHub

Two options (see the session notes):

1. **Private repo for our fork/patches** — push this repository as-is
   (`app/` baseline + commits + scripts). Exact reproduction of our deployment.
2. **Fork upstream** `caura-ai/caura-memclaw` and open a PR with only the
   `openai.py` change (commit 2). Recommended for longevity: the fix is generic
   and upstream `complete_json` is the same shape.
