"""Verify Terraform module and runnable stage file symmetry contracts."""

from pathlib import Path
import re
import unittest

REPO_ROOT = Path(__file__).resolve().parent.parent

MODULE_FILES = frozenset({
    "README.md",
    "main.tf",
    "variables.tf",
    "outputs.tf",
    "versions.tf",
})

STAGE_FILES = frozenset({
    "README.md",
    "main.tf",
    "variables.tf",
    "outputs.tf",
    "versions.tf",
    "terraform.tfvars.example",
})

EXPECTED_MODULES = frozenset({
    "modules/ingestion/datastream-cdc",
    "modules/ingestion/pubsub-bigquery",
    "modules/ingestion/batch-elt-job",
    "modules/ingestion/pipeline-workflows",
})

EXPECTED_STAGES = frozenset({
    "stages/sandbox",
    "stages/enterprise",
})

IGNORED_NAMES = frozenset({
    ".terraform",
    ".terraform.lock.hcl",
    "__pycache__",
    ".DS_Store",
    "terraform.tfstate",
    "terraform.tfstate.backup",
    "terraform.tfvars",
})


def _is_ignored(name: str) -> bool:
    if name in IGNORED_NAMES:
        return True
    if name.endswith((".auto.tfvars", ".auto.tfvars.json", ".tfplan")):
        return True
    if name.startswith("terraform.tfstate."):
        return True
    return False


def _visible_entries(directory: Path) -> set[str]:
    return {
        entry.name
        for entry in directory.iterdir()
        if not _is_ignored(entry.name)
    }


def _discover_modules() -> list[Path]:
    ingestion_dir = REPO_ROOT / "modules" / "ingestion"
    if not ingestion_dir.is_dir():
        return []
    return [
        mod_dir
        for mod_dir in sorted(ingestion_dir.iterdir())
        if mod_dir.is_dir() and not mod_dir.name.startswith(".")
    ]


def _discover_stages() -> list[Path]:
    stages_dir = REPO_ROOT / "stages"
    if not stages_dir.is_dir():
        return []
    return [
        stage_dir
        for stage_dir in sorted(stages_dir.iterdir())
        if stage_dir.is_dir() and not stage_dir.name.startswith(".")
    ]


class RepoSymmetryTest(unittest.TestCase):
    """Validate 4 five-file modules, 2 six-file stages, and version pins."""

    def test_modules_obey_five_file_contract(self) -> None:
        modules = _discover_modules()
        discovered_rel = {str(m.relative_to(REPO_ROOT)) for m in modules}
        self.assertEqual(discovered_rel, EXPECTED_MODULES)

        for mod_dir in modules:
            with self.subTest(module=str(mod_dir.relative_to(REPO_ROOT))):
                actual = _visible_entries(mod_dir)
                self.assertEqual(
                    actual,
                    MODULE_FILES,
                    f"{mod_dir} must contain exact 5-file contract: {sorted(MODULE_FILES)}",
                )
                for entry in mod_dir.iterdir():
                    if entry.name in MODULE_FILES:
                        self.assertTrue(entry.is_file(), f"Expected file, found non-file: {entry}")

    def test_stages_obey_six_file_contract(self) -> None:
        stages = _discover_stages()
        discovered_rel = {str(s.relative_to(REPO_ROOT)) for s in stages}
        self.assertEqual(discovered_rel, EXPECTED_STAGES)

        for stage_dir in stages:
            with self.subTest(stage=str(stage_dir.relative_to(REPO_ROOT))):
                actual = _visible_entries(stage_dir)
                self.assertEqual(
                    actual,
                    STAGE_FILES,
                    f"{stage_dir} must contain exact 6-file contract: {sorted(STAGE_FILES)}",
                )
                for entry in stage_dir.iterdir():
                    if entry.name in STAGE_FILES:
                        self.assertTrue(entry.is_file(), f"Expected file, found non-file: {entry}")

    def test_versions_tf_pins_terraform_and_google_provider(self) -> None:
        targets = _discover_modules() + _discover_stages()
        self.assertEqual(len(targets), len(EXPECTED_MODULES) + len(EXPECTED_STAGES))
        tf_pattern = re.compile(r'required_version\s*=\s*">=\s*1\.8\.0"')
        google_pattern = re.compile(
            r'source\s*=\s*"hashicorp/google"[\s\S]*?version\s*=\s*">=\s*8\.0\.0,\s*<\s*9\.0\.0"'
        )
        time_pattern = re.compile(
            r'source\s*=\s*"hashicorp/time"[\s\S]*?version\s*=\s*">=\s*0\.11\.0'
        )
        for target in targets:
            versions_path = target / "versions.tf"
            with self.subTest(versions=str(versions_path.relative_to(REPO_ROOT))):
                text = versions_path.read_text(encoding="utf-8")
                self.assertRegex(text, tf_pattern)
                self.assertRegex(text, google_pattern)
                if target in _discover_stages():
                    self.assertRegex(text, time_pattern)

    def test_no_empty_string_coalesce_in_terraform(self) -> None:
        bad_coalesce = re.compile(r'coalesce\([^)]*""')
        skip_dirs = {".git", ".terraform", "__pycache__", ".pytest_cache", ".venv"}
        for tf_path in sorted(REPO_ROOT.rglob("*.tf")):
            if any(part in skip_dirs for part in tf_path.parts):
                continue
            rel = str(tf_path.relative_to(REPO_ROOT))
            with self.subTest(file=rel):
                self.assertIsNone(
                    bad_coalesce.search(tf_path.read_text(encoding="utf-8")),
                    f"Empty-string coalesce found in {rel}",
                )


if __name__ == "__main__":
    unittest.main()
