# MemClaw — custom deployment archive (our fork)

Everything for our **custom MemClaw (CAURA) deployment** lives here, on the
**`main`** branch. There is nothing to hunt for in other branches.

- Runs at: `https://memclaw.enpire.ru/mcp`
- Host: `root@ne.enpire.ru`, k3s namespace `memclaw`
- Deployed image: **`memclaw-core-api:v6`** (built from this repo)

This branch is a faithful mirror of what actually runs, **with all our fixes
already applied**, plus the scripts to rebuild and deploy it, plus the
individual fixes as readable patches.

---

## What is here

```
app/                        the deployed runtime source (/app from the container),
                            with all our fixes applied  (= the "fixed state")
build/
  Dockerfile.patch          the Dockerfile fragment (FROM v5 + copy app/ over)
  rebuild.sh                build memclaw-core-api:v6 from v5 + app/, import into k3s
  deploy.sh                 switch the deployment to v6 + timeout, wait for rollout
  rollback.sh               switch back to v5
manifests/                  k8s objects exported from the live cluster (secrets REDACTED)
local-edits/                OUR fixes as standalone patches vs upstream (3 files) + README
LOCAL-CUSTOMIZATIONS.md     full write-up: upstream identity + every local edit, and the diff
                            between upstream evolution and our edits
README.md                   this file
```

## Our fixes (the short version)

Three files differ from upstream. All three are in `app/` **and** as standalone
patches in [`local-edits/`](local-edits/):

| # | File | Purpose |
| --- | --- | --- |
| 1 | `common/llm/constants.py` | `OPENAI_CHAT_BASE_URL` overridable by env → point the LLM client at our host (Polza). |
| 2 | `common/embedding/_registry.py` | Allow a custom embedding URL together with `dimensions=` (upstream hard-failed this). |
| 3 | `common/llm/providers/openai.py` | Fall back `json_schema` → `json_object` on HTTP 400 — the fix for the entity-extraction errors. |

Fixes 1–2 are the "custom API host" support edits; fix 3 is the code patch
(what turned image `v5` into `v6`). See `LOCAL-CUSTOMIZATIONS.md` for details and
`local-edits/README.md` for how to apply them to upstream.

## Rebuild & deploy (on the host)

```bash
scp build/rebuild.sh build/deploy.sh root@ne.enpire.ru:/root/memclaw-patches/
ssh root@ne.enpire.ru 'cd /root/memclaw-patches && ./rebuild.sh && ./deploy.sh'
```

`rebuild.sh` creates a container from `memclaw-core-api:v5`, copies `app/` over
`/app`, purges `__pycache__`, commits `memclaw-core-api:v6` and imports it into
the k3s containerd namespace `k8s.io`. `deploy.sh` sets the image and
`OPENAI_REQUEST_TIMEOUT_SECONDS=240`, then waits for the rollout.

> Note: `docker push registry.enpire.ru` is not reachable from this host, so the
> image lives only in local docker + k3s containerd. This repo is the source of
> truth — rebuild from it if the image is ever lost.

## Rollback

```bash
cd /root/memclaw-patches && ./rollback.sh
# or:
kubectl -n memclaw set image deployment/memclaw-api api=memclaw-core-api:v5
```

## Verification signal

After a memory write, `memclaw-api` should log the fallback firing and a
successful call — and never `All LLM providers failed for entity-extraction`:

```
WARNING Provider rejected json_schema response_format for model deepseek/deepseek-v4.1-flash; retrying with json_object
INFO    OpenAI-compatible complete_json (deepseek/deepseek-v4.1-flash) took <N>ms
```

## Secrets

No secret **values** are stored here. `memclaw-secret` keys used by the
deployment: `admin-api-key`, `api-key`, `db-password`, `openai-api-key`.
`SETTINGS_ENCRYPTION_KEY` was a plain env value in the live manifest and is
redacted here — read it from the cluster:

```bash
kubectl -n memclaw get deploy memclaw-api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SETTINGS_ENCRYPTION_KEY")].value}'
```

## Upstream

- Product: **caura-memclaw** (Apache-2.0) — `https://github.com/caura-ai/caura-memclaw`
- Our image was built from commit `9e222a1` (tag `backend-v2.19.0`).
  (`caura-ai/caura` is a mirror of the same code at that commit.)
- Upstream `main` has since renamed the MCP tools `memclaw_*` → `caura_*`, so it
  is **not** a valid diff/apply base. Pin the commit above.

This fork is an **archive** — we do not intend to contribute back upstream.
