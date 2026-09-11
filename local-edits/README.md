# Our local edits (standalone patches)

Each `.patch` here is one of **our** changes, relative to the upstream project.
They are the same changes that are already baked into `../app/` (the deployed
runtime source), but here they are split out so you can read and apply them
individually.

Base the patches apply to:

- upstream repo: `https://github.com/caura-ai/caura-memclaw`
- commit: `9e222a1dba31b33b0e95560ee3ee09620809b119`
  (tag `backend-v2.19.0`; the revision the deployed image was built from)

Apply them with `git apply` (or `patch -p1`) from the repo root:

```bash
git clone https://github.com/caura-ai/caura-memclaw.git
cd caura-memclaw
git checkout 9e222a1dba31b33b0e95560ee3ee09620809b119
for p in <this-dir>/*.patch; do git apply "$p"; done
```

Verified: all three apply to a clean checkout of that commit with no fuzz, and
applying all three reproduces the three files in `../app/` byte-for-byte.

## The three edits

| Patch | File | What it does |
| --- | --- | --- |
| `0001-env-overridable-openai-chat-base-url.patch` | `common/llm/constants.py` | `OPENAI_CHAT_BASE_URL` becomes `os.environ.get("OPENAI_CHAT_BASE_URL", "https://api.openai.com/v1")` — lets us point the LLM client at a custom OpenAI-compatible host (Polza) by env var, no rebuild. |
| `0002-allow-custom-embedding-endpoint.patch` | `common/embedding/_registry.py` | Comments out the `if base_url and send_dimensions: raise ValueError(...)` guard. Upstream made "custom embedding URL + `dimensions=`" a hard startup failure; our custom embedding host needs it allowed. |
| `0003-json-schema-json-object-fallback.patch` | `common/llm/providers/openai.py` | `OpenAILLMProvider.complete_json` catches `openai.BadRequestError` and retries **once** with `response_format={"type": "json_object"}` when it had used `json_schema`. Polza's DeepSeek route rejects `json_schema` with HTTP 400, which broke entity extraction. |

Patches **0001** and **0002** are the "custom API host" support edits (they were
already present in the `v5` image as found). Patch **0003** is the code fix we
wrote on top (`v6`).

## Note on upstream drift

Upstream `main` has moved on since our build commit and is **not** a valid patch
base: among other things it renamed the MCP tools `memclaw_*` → `caura_*`, while
our deployed image uses `memclaw_*`. Always use the pinned commit above.
