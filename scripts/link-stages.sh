#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  link-stages.sh [--env <env>] [--domain-name <domain>] [--tfstate-bucket <bucket>] <source_stage_dir> [<source_stage_dir> ...] <target_stage_dir>
  link-stages.sh [--env <env>] [--domain-name <domain>] [--tfstate-bucket <bucket>] --export-gcs <gs://bucket/path.json> <source_stage_dir> [<source_stage_dir> ...]
  link-stages.sh [--env <env>] [--domain-name <domain>] --from-gcs <gs://bucket/path.json> [<gs://bucket/path2.json> ...] <target_stage_dir>
EOF
}

die_usage() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

require_flag_value() {
  local flag="$1"
  local remaining="$2"
  local value="${3:-}"
  if [ "$remaining" -lt 2 ] || [ -z "$value" ] || [[ "$value" == -* ]]; then
    die_usage "Missing or empty value for ${flag}"
  fi
}

BUCKET_RE='^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$'
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

env_name=""
domain_name="${DOMAIN_NAME:-}"
domain_name_explicit=false
tfstate_bucket="${TFSTATE_BUCKET:-${GCP_TFSTATE_BUCKET:-${TF_STATE_BUCKET:-}}}"
tfstate_bucket_explicit=false
mode="local"
gcs_uri=""
positional=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      require_flag_value "$1" "$#" "${2:-}"
      env_name="$2"
      shift 2
      ;;
    --env=*)
      env_name="${1#--env=}"
      if [ -z "$env_name" ] || [[ "$env_name" == -* ]]; then
        die_usage "Missing or empty value for --env"
      fi
      shift
      ;;
    --domain-name)
      require_flag_value "$1" "$#" "${2:-}"
      domain_name="$2"
      domain_name_explicit=true
      shift 2
      ;;
    --domain-name=*)
      domain_name="${1#--domain-name=}"
      domain_name_explicit=true
      if [ -z "$domain_name" ] || [[ "$domain_name" == -* ]]; then
        die_usage "Missing or empty value for --domain-name"
      fi
      shift
      ;;
    --tfstate-bucket)
      require_flag_value "$1" "$#" "${2:-}"
      tfstate_bucket="$2"
      tfstate_bucket_explicit=true
      shift 2
      ;;
    --tfstate-bucket=*)
      tfstate_bucket="${1#--tfstate-bucket=}"
      tfstate_bucket_explicit=true
      if [ -z "$tfstate_bucket" ] || [[ "$tfstate_bucket" == -* ]]; then
        die_usage "Missing or empty value for --tfstate-bucket"
      fi
      shift
      ;;
    --export-gcs)
      if [ "$mode" != "local" ]; then
        usage
        exit 1
      fi
      mode="export-gcs"
      shift
      if [ "$#" -lt 1 ]; then
        usage
        exit 1
      fi
      gcs_uri="$1"
      shift
      ;;
    --from-gcs)
      if [ "$mode" != "local" ]; then
        usage
        exit 1
      fi
      mode="from-gcs"
      shift
      ;;
    -h|--help)
      usage
      exit 0
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

if [ -n "$domain_name" ]; then
  if [[ ! "$domain_name" =~ ^[a-z][a-z0-9-]{0,19}[a-z0-9]$ ]]; then
    die_usage "Invalid --domain-name value: ${domain_name}"
  fi
elif [ "$domain_name_explicit" = true ]; then
  die_usage "Missing or empty value for --domain-name"
fi

if [ -n "$tfstate_bucket" ]; then
  if [[ ! "$tfstate_bucket" =~ $BUCKET_RE ]]; then
    die_usage "Invalid --tfstate-bucket value: ${tfstate_bucket}"
  fi
elif [ "$tfstate_bucket_explicit" = true ]; then
  die_usage "Missing or empty value for --tfstate-bucket"
fi

if [ "$mode" = "export-gcs" ]; then
  if [ "${#positional[@]}" -lt 1 ]; then
    usage
    exit 1
  fi
  source_dirs=("${positional[@]}")
elif [ "$mode" = "from-gcs" ]; then
  if [ "${#positional[@]}" -lt 2 ]; then
    usage
    exit 1
  fi
  target_dir="${positional[$(( ${#positional[@]} - 1 ))]}"
  gcs_uris=("${positional[@]:0:$(( ${#positional[@]} - 1 ))}")
else
  if [ "${#positional[@]}" -lt 2 ]; then
    usage
    exit 1
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
  if [[ ! "$gcs_uri" =~ ^gs://[a-z0-9][a-z0-9._-]{1,61}[a-z0-9](/.*)?$ ]]; then
    echo "Invalid GCS URI: $gcs_uri" >&2
    exit 1
  fi
  python3 - "$env_name" "$gcs_uri" "$tfstate_bucket" "$REPO_ROOT" "$domain_name" "${source_dirs[@]}" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

env_name = sys.argv[1]
raw_gcs_uri = sys.argv[2]
tfstate_bucket = sys.argv[3]
repo_root = Path(sys.argv[4]).resolve()
domain_name = sys.argv[5]
raw_sources = sys.argv[6:]


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
    if obj == "shared" or obj.startswith("shared/"):
        return uri
    parts = obj.split("/")
    filename = parts[-1]
    if env in parts[:-1]:
        return uri
    if filename and (
        f"-{env}." in filename
        or filename.startswith(f"{env}-")
        or filename == f"{env}.json"
    ):
        return uri
    if obj.endswith("/"):
        return f"gs://{bucket}/{obj}{env}/foundation-outputs.json"
    parent = "/".join(parts[:-1])
    if parent:
        return f"gs://{bucket}/{parent}/{env}/{filename}"
    return f"gs://{bucket}/{env}/{filename}"


def find_repo_root(stage_abs: Path) -> Path | None:
    for candidate in (stage_abs, *stage_abs.parents):
        if candidate == candidate.parent:
            break
        if (candidate / ".git").exists():
            return candidate
    for candidate in stage_abs.parents:
        if candidate == candidate.parent:
            break
        if candidate.name in ("stages", "foundation", "data"):
            return candidate.parent
    return None


def resolve_backend_prefix(raw_src: str, src_abs: Path, env: str) -> str:
    resolved_src = src_abs.resolve()
    try:
        rel_stage = resolved_src.relative_to(repo_root).as_posix()
        in_self_repo = True
    except ValueError:
        ext_root = find_repo_root(resolved_src)
        if ext_root is not None:
            rel_stage = resolved_src.relative_to(ext_root).as_posix()
        else:
            rel_stage = resolved_src.name
        in_self_repo = (
            rel_stage.startswith("stages/")
            and (ext_root is None or ext_root.name != "gcp-data-science")
        )
    if not in_self_repo:
        effective_env = "shared" if rel_stage == "foundation/01-org-governance" else env
        return f"{rel_stage}/{effective_env}"
    if rel_stage.startswith("stages/"):
        rel_stage = rel_stage[len("stages/"):]
    if domain_name:
        return f"ingestion/{domain_name}/{rel_stage}/{env}"
    return f"ingestion/{rel_stage}/{env}"


def stage_uses_gcs_backend(stage_abs: Path) -> bool:
    if (stage_abs / "envs").is_dir():
        return True
    versions_tf = stage_abs / "versions.tf"
    return versions_tf.is_file() and 'backend "gcs"' in versions_tf.read_text(encoding="utf-8")


def read_stage_outputs(raw_src: str, env: str, state_bucket: str) -> dict[str, object]:
    src = Path(raw_src)
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

    if env and state_bucket and stage_uses_gcs_backend(effective_src):
        backend_prefix = resolve_backend_prefix(raw_src, effective_src.resolve(), env)
        subprocess.run(
            [
                "terraform",
                f"-chdir={effective_src}",
                "init",
                "-reconfigure",
                "-input=false",
                f"-backend-config=bucket={state_bucket}",
                f"-backend-config=prefix={backend_prefix}",
            ],
            check=True,
            env=cmd_env,
            stdout=subprocess.DEVNULL,
        )

    raw = subprocess.check_output(
        ["terraform", f"-chdir={effective_src}", "output", "-json"],
        text=True,
        env=cmd_env,
    )
    outputs = json.loads(raw)
    if env and isinstance(outputs.get("environment"), dict):
        actual_env = outputs["environment"].get("value")
        if isinstance(actual_env, str) and actual_env.strip() and actual_env.strip() != env:
            print(
                f"ERROR: Stage {raw_src} Terraform state has environment='{actual_env.strip()}', expected '{env}'. "
                f"Re-init the stage for '{env}' or pass --tfstate-bucket.",
                file=sys.stderr,
            )
            raise SystemExit(1)
    return outputs


gcs_uri = resolve_env_gcs_uri(raw_gcs_uri, env_name)
exported: dict[str, object] = {}
for raw_src in raw_sources:
    outputs = read_stage_outputs(raw_src, env_name, tfstate_bucket)
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
    if [[ ! "$uri" =~ ^gs://[a-z0-9][a-z0-9._-]{1,61}[a-z0-9](/.*)?$ ]]; then
      echo "Invalid GCS URI: $uri" >&2
      exit 1
    fi
  done
  python3 - "$env_name" "$target_abs" "$out_file" "$domain_name" "${gcs_uris[@]}" <<'PY'
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
domain_name = sys.argv[4]
raw_uris = sys.argv[5:]


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
    if obj == "shared" or obj.startswith("shared/"):
        return uri
    parts = obj.split("/")
    filename = parts[-1]
    if env in parts[:-1]:
        return uri
    if filename and (
        f"-{env}." in filename
        or filename.startswith(f"{env}-")
        or filename == f"{env}.json"
    ):
        return uri
    if obj.endswith("/"):
        return f"gs://{bucket}/{obj}{env}/foundation-outputs.json"
    parent = "/".join(parts[:-1])
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
if domain_name and "domain_name" in declared_vars and "domain_name" not in merged:
    merged["domain_name"] = domain_name

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

python3 - "$env_name" "$target_abs" "$out_file" "$tfstate_bucket" "$REPO_ROOT" "$domain_name" "${source_dirs[@]}" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys

env_name = sys.argv[1]
target_dir = Path(sys.argv[2])
out_file = Path(sys.argv[3])
tfstate_bucket = sys.argv[4]
repo_root = Path(sys.argv[5]).resolve()
domain_name = sys.argv[6]
raw_sources = sys.argv[7:]

var_re = re.compile(r'^\s*variable\s+"([A-Za-z0-9_]+)"\s*\{', re.MULTILINE)
declared_vars = set(var_re.findall((target_dir / "variables.tf").read_text(encoding="utf-8")))


def find_repo_root(stage_abs: Path) -> Path | None:
    for candidate in (stage_abs, *stage_abs.parents):
        if candidate == candidate.parent:
            break
        if (candidate / ".git").exists():
            return candidate
    for candidate in stage_abs.parents:
        if candidate == candidate.parent:
            break
        if candidate.name in ("stages", "foundation", "data"):
            return candidate.parent
    return None


def resolve_backend_prefix(raw_src: str, src_abs: Path, env: str) -> str:
    resolved_src = src_abs.resolve()
    try:
        rel_stage = resolved_src.relative_to(repo_root).as_posix()
        in_self_repo = True
    except ValueError:
        ext_root = find_repo_root(resolved_src)
        if ext_root is not None:
            rel_stage = resolved_src.relative_to(ext_root).as_posix()
        else:
            rel_stage = resolved_src.name
        in_self_repo = (
            rel_stage.startswith("stages/")
            and (ext_root is None or ext_root.name != "gcp-data-science")
        )
    if not in_self_repo:
        effective_env = "shared" if rel_stage == "foundation/01-org-governance" else env
        return f"{rel_stage}/{effective_env}"
    if rel_stage.startswith("stages/"):
        rel_stage = rel_stage[len("stages/"):]
    if domain_name:
        return f"ingestion/{domain_name}/{rel_stage}/{env}"
    return f"ingestion/{rel_stage}/{env}"


def stage_uses_gcs_backend(stage_abs: Path) -> bool:
    if (stage_abs / "envs").is_dir():
        return True
    versions_tf = stage_abs / "versions.tf"
    return versions_tf.is_file() and 'backend "gcs"' in versions_tf.read_text(encoding="utf-8")


def read_stage_outputs(raw_src: str, env: str, state_bucket: str) -> dict[str, object]:
    src = Path(raw_src)
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

    if env and state_bucket and stage_uses_gcs_backend(effective_src):
        backend_prefix = resolve_backend_prefix(raw_src, effective_src.resolve(), env)
        subprocess.run(
            [
                "terraform",
                f"-chdir={effective_src}",
                "init",
                "-reconfigure",
                "-input=false",
                f"-backend-config=bucket={state_bucket}",
                f"-backend-config=prefix={backend_prefix}",
            ],
            check=True,
            env=cmd_env,
            stdout=subprocess.DEVNULL,
        )

    raw = subprocess.check_output(
        ["terraform", f"-chdir={effective_src}", "output", "-json"],
        text=True,
        env=cmd_env,
    )
    outputs = json.loads(raw)
    if env and isinstance(outputs.get("environment"), dict):
        actual_env = outputs["environment"].get("value")
        if isinstance(actual_env, str) and actual_env.strip() and actual_env.strip() != env:
            print(
                f"ERROR: Stage {raw_src} Terraform state has environment='{actual_env.strip()}', expected '{env}'. "
                f"Re-init the stage for '{env}' or pass --tfstate-bucket.",
                file=sys.stderr,
            )
            raise SystemExit(1)
    return outputs


merged: dict[str, object] = {}

for raw_src in raw_sources:
    outputs = read_stage_outputs(raw_src, env_name, tfstate_bucket)
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
if domain_name and "domain_name" in declared_vars and "domain_name" not in merged:
    merged["domain_name"] = domain_name

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
