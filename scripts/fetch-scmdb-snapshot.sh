#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-https://scmdb.net}"
OUTPUT_PATH="${2:-api/SCMDBSnapshot/scmdb-fabricator-snapshot.json}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl wird benoetigt, ist aber nicht installiert." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 wird benoetigt, ist aber nicht installiert." >&2
  exit 1
fi

NORMALIZED_BASE="${BASE_URL%/}"
CURL_UA="QuestBoard-SCMDB-Fetch/1.0"
CURL_ARGS=(--fail --silent --show-error --location --retry 3 --retry-all-errors --connect-timeout 20 --max-time 180 -H "Accept: application/json" -A "$CURL_UA")

fetch_json() {
  local url="$1"
  local output="$2"
  curl "${CURL_ARGS[@]}" "$url" -o "$output"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VERSIONS_PATH="$TMP_DIR/versions.json"
BLUEPRINTS_PATH="$TMP_DIR/crafting_blueprints.json"
ITEMS_PATH="$TMP_DIR/crafting_items.json"

fetch_json "$NORMALIZED_BASE/data/versions.json" "$VERSIONS_PATH"

VERSION="$(python3 - "$VERSIONS_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    versions = json.load(handle)

if not versions:
    raise SystemExit("SCMDB versions.json lieferte keine Versionen.")

selected = versions[0]
version = selected.get("version")
if not version:
    raise SystemExit("SCMDB versions.json enthaelt keine gueltige Version.")

print(version)
PY
)"

echo "Nutze SCMDB-Version $VERSION"

fetch_json "$NORMALIZED_BASE/data/crafting_blueprints-$VERSION.json" "$BLUEPRINTS_PATH"
fetch_json "$NORMALIZED_BASE/data/crafting_items-$VERSION.json" "$ITEMS_PATH"

mkdir -p "$(dirname "$OUTPUT_PATH")"

python3 - "$NORMALIZED_BASE" "$VERSION" "$BLUEPRINTS_PATH" "$ITEMS_PATH" "$OUTPUT_PATH" <<'PY'
import json
import sys
from datetime import datetime, timezone

base_url, version, blueprints_path, items_path, output_path = sys.argv[1:6]

with open(blueprints_path, "r", encoding="utf-8") as handle:
    crafting_blueprints = json.load(handle)

with open(items_path, "r", encoding="utf-8") as handle:
    crafting_items = json.load(handle)

snapshot = {
    "sourceBaseURL": base_url,
    "version": version,
    "fetchedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "craftingBlueprints": crafting_blueprints,
    "craftingItems": crafting_items,
}

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(snapshot, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

echo "SCMDB-Snapshot geschrieben nach $OUTPUT_PATH"