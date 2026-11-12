#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  link-stages.sh [--env <env>] <source_stage_dir> [<source_stage_dir> ...] <target_stage_dir>
  link-stages.sh [--env <env>] --export-gcs <gs://bucket/path.json> <source_stage_dir> [<source_stage_dir> ...]
  link-stages.sh [--env <env>] --from-gcs <gs://bucket/path.json> [<gs://bucket/path2.json> ...] <target_stage_dir>
EOF
  exit 1
}

env_name=""
mode="local"
gcs_uri=""
positional=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      shift
      if [ "$#" -lt 1 ]; then
        usage
      fi
      env_name="$1"
      shift
      ;;
    --env=*)
      env_name="${1#--env=}"
      shift
      ;;
    --export-gcs)
      if [ "$mode" != "local" ]; then
        usage
      fi
      mode="export-gcs"
      shift
      if [ "$#" -lt 1 ]; then
        usage
      fi
      gcs_uri="$1"
      shift
      ;;
    --from-gcs)
      if [ "$mode" != "local" ]; then
        usage
      fi
      mode="from-gcs"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [ -n "$env_name" ]; then
  if [[ ! "$env_name" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]]; then
    echo "Invalid --env value: $env_name" >&2
    exit 1
  fi
fi

if [ "$mode" = "export-gcs" ]; then
  if [ "${#positional[@]}" -lt 1 ]; then
    usage
  fi
  source_dirs=("${positional[@]}")
elif [ "$mode" = "from-gcs" ]; then
  if [ "${#positional[@]}" -lt 2 ]; then
    usage
  fi
  target_dir="${positional[$(( ${#positional[@]} - 1 ))]}"
  gcs_uris=("${positional[@]:0:$(( ${#positional[@]} - 1 ))}")
else
  if [ "${#positional[@]}" -lt 2 ]; then
    usage
  fi
  target_dir="${positional[$(( ${#positional[@]} - 1 ))]}"
  source_dirs=("${positional[@]:0:$(( ${#positional[@]} - 1 ))}")
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
  python3 - "$env_name" "$gcs_uri" "${source_dirs[@]}" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

env_name = sys.argv[1]
raw_gcs_uri = sys.argv[2]
source_dirs = [Path(p) for p in sys.argv[3:]]


def resolve_env_gcs_uri(uri: str, env: str) -> str:
    if not env:
        return uri
    rest = uri[len("gs://"):]
    if "/" not in rest:
        return f"gs://{rest}/{env}/foundation-outputs.json"
    bucket, obj = rest.split("/", 1)
    obj = obj.lstrip("/")
    if not obj:
        return f"gs://{bucket}/{env}/foundation-outputs.json"
    parts = obj.split("/")
    if env in parts[:-1]:
        return uri
    if obj.endswith("/"):
        return f"gs://{bucket}/{obj}{env}/foundation-outputs.json"
    parent = "/".join(parts[:-1])
    filename = parts[-1]
    if parent:
        return f"gs://{bucket}/{parent}/{env}/{filename}"
    return f"gs://{bucket}/{env}/{filename}"


def read_stage_outputs(src: Path, env: str) -> dict[str, object]:
    effective_src = src
    sub_env = src / env if env else None
    envs_sub = src / "envs" / env if env else None
    if env and sub_env is not None and sub_env.is_dir():
        effective_src = sub_env
    elif env and envs_sub is not None and envs_sub.is_dir():
        effective_src = envs_sub

    cmd_env = os.environ.copy()
    if env and (effective_src / "terraform.tfstate.d" / env).is_dir():
        cmd_env["TF_WORKSPACE"] = env

    raw = subprocess.check_output(
        ["terraform", f"-chdir={effective_src}", "output", "-json"],
        text=True,
        env=cmd_env,
    )
    return json.loads(raw)


gcs_uri = resolve_env_gcs_uri(raw_gcs_uri, env_name)
exported: dict[str, object] = {}
for src in source_dirs:
    outputs = read_stage_outputs(src, env_name)
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
  python3 - "$env_name" "$target_abs" "$out_file" "${gcs_uris[@]}" <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

env_name = sys.argv[1]
target_dir = Path(sys.argv[2])
out_file = Path(sys.argv[3])
raw_uris = sys.argv[4:]


def resolve_env_gcs_uri(uri: str, env: str) -> str:
    if not env:
        return uri
    rest = uri[len("gs://"):]
    if "/" not in rest:
        return f"gs://{rest}/{env}/foundation-outputs.json"
    bucket, obj = rest.split("/", 1)
    obj = obj.lstrip("/")
    if not obj:
        return f"gs://{bucket}/{env}/foundation-outputs.json"
    parts = obj.split("/")
    if env in parts[:-1]:
        return uri
    if obj.endswith("/"):
        return f"gs://{bucket}/{obj}{env}/foundation-outputs.json"
    parent = "/".join(parts[:-1])
    filename = parts[-1]
    if parent:
        return f"gs://{bucket}/{parent}/{env}/{filename}"
    return f"gs://{bucket}/{env}/{filename}"


gcs_uris = [resolve_env_gcs_uri(u, env_name) for u in raw_uris]

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

if env_name and "environment" in declared_vars and "environment" not in merged:
    merged["environment"] = env_name

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

python3 - "$env_name" "$target_abs" "$out_file" "${source_dirs[@]}" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys

env_name = sys.argv[1]
target_dir = Path(sys.argv[2])
out_file = Path(sys.argv[3])
source_dirs = [Path(p) for p in sys.argv[4:]]

var_re = re.compile(r'^\s*variable\s+"([A-Za-z0-9_]+)"\s*\{', re.MULTILINE)
declared_vars = set(var_re.findall((target_dir / "variables.tf").read_text(encoding="utf-8")))


def read_stage_outputs(src: Path, env: str) -> dict[str, object]:
    effective_src = src
    sub_env = src / env if env else None
    envs_sub = src / "envs" / env if env else None
    if env and sub_env is not None and sub_env.is_dir():
        effective_src = sub_env
    elif env and envs_sub is not None and envs_sub.is_dir():
        effective_src = envs_sub

    cmd_env = os.environ.copy()
    if env and (effective_src / "terraform.tfstate.d" / env).is_dir():
        cmd_env["TF_WORKSPACE"] = env

    raw = subprocess.check_output(
        ["terraform", f"-chdir={effective_src}", "output", "-json"],
        text=True,
        env=cmd_env,
    )
    return json.loads(raw)


merged: dict[str, object] = {}

for src in source_dirs:
    outputs = read_stage_outputs(src, env_name)
    for key, payload in outputs.items():
        if key not in declared_vars or not isinstance(payload, dict):
            continue
        if payload.get("sensitive") is True:
            continue
        val = payload.get("value")
        if val is not None:
            merged[key] = val

if env_name and "environment" in declared_vars and "environment" not in merged:
    merged["environment"] = env_name

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
