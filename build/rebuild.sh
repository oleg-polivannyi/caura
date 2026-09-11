#!/usr/bin/env bash
# Rebuild memclaw-core-api:v6 from v5 + the patched app/ tree, then import it
# into the k3s containerd image store. Run ON THE HOST (root@ne.enpire.ru).
set -euo pipefail
cd "$(dirname "$0")/.."          # repo root (contains app/)

BASE=${BASE:-memclaw-core-api:v5}
NEW=${NEW:-memclaw-core-api:v6}
REG=${REG:-registry.enpire.ru/memclaw-core-api:v6}

echo "[*] building $NEW from $BASE (context: $(pwd))"
docker build -f build/Dockerfile.patch -t "$NEW" .

echo "[*] verifying the patched file is present in the new image"
docker create --name mc-verify "$NEW" >/dev/null
docker cp mc-verify:/app/common/llm/providers/openai.py /tmp/openai.patched.py >/dev/null
docker rm mc-verify >/dev/null
if grep -q "retrying with json_object" /tmp/openai.patched.py; then
  echo "    OK: fallback present in image"
else
  echo "    ERROR: fallback NOT found in image" >&2; exit 1
fi

echo "[*] importing into k3s containerd (namespace k8s.io)"
docker save "$NEW" | ctr -n k8s.io images import -

echo "[*] available memclaw images in containerd:"
ctr -n k8s.io images ls -q | grep memclaw-core-api || true

echo "[*] tagging for the private registry (push manually if desired):"
docker tag "$NEW" "$REG" && echo "    tagged $REG"
echo "    optional: docker push $REG"
