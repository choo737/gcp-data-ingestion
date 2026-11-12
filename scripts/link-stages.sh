#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  link-stages.sh <source_stage_dir> [<source_stage_dir> ...] <target_stage_dir>
  link-stages.sh --export-gcs <gs://bucket/path.json> <source_stage_dir> [<source_stage_dir> ...]
  link-stages.sh --from-gcs <gs://bucket/path.json> [<gs://bucket/path2.json> ...] <target_stage_dir>
EOF
  exit 1
}

if [ "$#" -lt 2 ]; then
  usage
fi

mode="local"
if [ "$1" = "--export-gcs" ]; then
  mode="export-gcs"
  shift
  if [ "$#" -lt 2 ]; then
    usage
  fi
  gcs_uri="$1"
  shift
  source_dirs=("$@")
elif [ "$1" = "--from-gcs" ]; then
  mode="from-gcs"
  shift
  if [ "$#" -lt 2 ]; then
    usage
  fi
  args=("$@")
  target_dir="${args[$(( ${#args[@]} - 1 ))]}"
  gcs_uris=("${args[@]:0:$(( ${#args[@]} - 1 ))}")
else
  args=("$@")
  target_dir="${args[$(( ${#args[@]} - 1 ))]}"
  source_dirs=("${args[@]:0:$(( ${#args[@]} - 1 ))}")
fi

if [ "$mode" = "local" ] || [ "$mode" = "from-gcs" ]; then
  if [ ! -d "$target_dir" ] || [ ! -f "$target_dir/variables.tf" ]; then
    echo "Target stage must be a directory containing variables.tf: $target_dir" >&2
    exit 1
  fi
  target_abs="$(cd "$target_dir" && pwd)"
  out_file="$target_abs/00_linked.auto.tfvars.json"
fi

if [ "$mode" = "local" ] || [ "$mode" = "export-gcs" ]; then
  for src in "${source_dirs[@]}"; do
    if [ ! -d "$src" ]; then
      echo "Source stage directory does not exist: $src" >&2
      exit 1
    fi
  done
fi

if [ "$mode" = "export-gcs" ]; then
  if [[ "$gcs_uri" != gs://* ]]; then
    echo "Export destination must be a gs:// URI: $gcs_uri" >&2
    exit 1
  fi
  python3 - "$gcs_uri" "${source_dirs[@]}" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

gcs_uri = sys.argv[1]
source_dirs = [Path(p) for p in sys.argv[2:]]

exported: dict[str, object] = {}
for src in source_dirs:
    raw = subprocess.check_output(
        ["terraform", f"-chdir={src}", "output", "-json"],
        text=True,
    )
    outputs = json.loads(raw)
    for key, payload in outputs.items():
        if not isinstance(payload, dict):
            continue
        if payload.get("sensitive") is True:
            continue
        val = payload.get("value")
        if val is not None:
            exported[key] = val

with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".json", delete=False) as tmp:
    tmp_path = Path(tmp.name)
    tmp.write(json.dumps(exported, indent=2, sort_keys=True) + "\n")

try:
    os.chmod(tmp_path, 0o600)
    if shutil.which("gcloud"):
        subprocess.check_call(["gcloud", "storage", "cp", str(tmp_path), gcs_uri])
    elif shutil.which("gsutil"):
        subprocess.check_call(["gsutil", "cp", str(tmp_path), gcs_uri])
    else:
        raise RuntimeError("Neither gcloud nor gsutil is installed in PATH.")
finally:
    if tmp_path.exists():
        tmp_path.unlink()

print(f"Exported {len(exported)} non-sensitive output(s) to {gcs_uri}")
PY
  exit 0
fi

if [ "$mode" = "from-gcs" ]; then
  for uri in "${gcs_uris[@]}"; do
    if [[ "$uri" != gs://* ]]; then
      echo "Source URI must start with gs://: $uri" >&2
      exit 1
    fi
  done
  python3 - "$target_abs" "$out_file" "${gcs_uris[@]}" <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

target_dir = Path(sys.argv[1])
out_file = Path(sys.argv[2])
gcs_uris = sys.argv[3:]

var_re = re.compile(r'^\s*variable\s+"([A-Za-z0-9_]+)"\s*\{', re.MULTILINE)
declared_vars = set(var_re.findall((target_dir / "variables.tf").read_text(encoding="utf-8")))

merged: dict[str, object] = {}
for uri in gcs_uris:
    if shutil.which("gcloud"):
        raw = subprocess.check_output(["gcloud", "storage", "cp", uri, "-"], text=True)
    elif shutil.which("gsutil"):
        raw = subprocess.check_output(["gsutil", "cat", uri], text=True)
    else:
        raise RuntimeError("Neither gcloud nor gsutil is installed in PATH.")
    outputs = json.loads(raw)
    if not isinstance(outputs, dict):
        raise ValueError(f"Expected JSON object in {uri}")
    for key, payload in outputs.items():
        if key not in declared_vars:
            continue
        if isinstance(payload, dict) and "value" in payload and "sensitive" in payload:
            if payload.get("sensitive") is True:
                continue
            val = payload.get("value")
        else:
            val = payload
        if val is not None:
            merged[key] = val

tmp_file = out_file.with_name(f".{out_file.name}.{os.getpid()}.tmp")
fd = os.open(tmp_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(merged, indent=2, sort_keys=True) + "\n")
    os.chmod(tmp_file, 0o600)
    os.replace(tmp_file, out_file)
except Exception:
    if tmp_file.exists():
        tmp_file.unlink()
    raise

print(f"Wrote {len(merged)} linked variable(s) to {out_file}")
PY
  exit 0
fi

python3 - "$target_abs" "$out_file" "${source_dirs[@]}" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys

target_dir = Path(sys.argv[1])
out_file = Path(sys.argv[2])
source_dirs = [Path(p) for p in sys.argv[3:]]

var_re = re.compile(r'^\s*variable\s+"([A-Za-z0-9_]+)"\s*\{', re.MULTILINE)
declared_vars = set(var_re.findall((target_dir / "variables.tf").read_text(encoding="utf-8")))

merged: dict[str, object] = {}

for src in source_dirs:
    raw = subprocess.check_output(
        ["terraform", f"-chdir={src}", "output", "-json"],
        text=True,
    )
    outputs = json.loads(raw)
    for key, payload in outputs.items():
        if key not in declared_vars or not isinstance(payload, dict):
            continue
        if payload.get("sensitive") is True:
            continue
        val = payload.get("value")
        if val is not None:
            merged[key] = val

tmp_file = out_file.with_name(f".{out_file.name}.{os.getpid()}.tmp")
fd = os.open(tmp_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(merged, indent=2, sort_keys=True) + "\n")
    os.chmod(tmp_file, 0o600)
    os.replace(tmp_file, out_file)
except Exception:
    if tmp_file.exists():
        tmp_file.unlink()
    raise

print(f"Wrote {len(merged)} linked variable(s) to {out_file}")
PY
