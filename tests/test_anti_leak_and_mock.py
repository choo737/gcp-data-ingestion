"""Verify zero leaked identifiers, secrets, mocks, emojis, or banned words."""

from pathlib import Path
import re
import unittest

REPO_ROOT = Path(__file__).resolve().parent.parent

SKIP_DIRS = frozenset({
    ".git",
    ".terraform",
    "__pycache__",
    ".pytest_cache",
    ".venv",
})

SKIP_FILES = frozenset({
    ".terraform.lock.hcl",
    ".DS_Store",
    "00_linked.auto.tfvars.json",
    "linked.auto.tfvars.json",
    "custom.auto.tfvars",
})

LEAKED_IDENTIFIERS = (
    "jacky" + "choo",
    "alto" + "strat",
    "playground-" + "473704",
    "641791" + "128082",
    "158706" + "953990",
    "016" + "D20",
    "C01" + "hil3w1",
)

SECRET_PATTERNS = (
    re.compile(r"-----BEGIN (?:[A-Z]+ )?" + r"PRIVATE KEY-----"),
    re.compile(r"\bAK" + r"IA[0-9A-Z]{16}\b"),
    re.compile(r"\bgh" + r"p_[A-Za-z0-9]{20,}\b"),
    re.compile(r"\bAI" + r"za[0-9A-Za-z_-]{35}\b"),
)

MOCK_MARKERS = (
    "mock_" + "success",
    "dummy_" + "payload",
    "fake_" + "output",
)

BANNED_AI_WORDS = (
    "del" + "ve",
    "navi" + "gate",
    "fos" + "ter",
    "cham" + "pion",
    "stream" + "line",
    "ele" + "vate",
    "har" + "ness",
    "orches" + "trate",
    "illu" + "minate",
    "tran" + "scend",
    "demy" + "stify",
    "emb" + "race",
    "un" + "lock",
    "tape" + "stry",
    "testa" + "ment",
    "bea" + "con",
    "re" + "alm",
    "land" + "scape",
    "para" + "digm",
    "syn" + "ergy",
    "fa" + "cet",
    "nua" + "nce",
    "corner" + "stone",
    "jour" + "ney",
    "blue" + "print",
    "para" + "mount",
    "multi" + "faceted",
    "vib" + "rant",
    "piv" + "otal",
    "hol" + "istic",
    "cru" + "cial",
    "compre" + "hensive",
    "meti" + "culous",
    "dyn" + "amic",
    "pro" + "found",
    "intr" + "icate",
    "further" + "more",
    "more" + "over",
    "in " + "conclusion",
    "at its " + "core",
    "it is worth " + "noting",
    "impor" + "tantly",
    "in " + "summary",
    "ulti" + "mately",
)

EMOJI_PATTERN = re.compile(r"[\U0001F300-\U0001FAFF\u2600-\u27BF\uFE0F]")
SECTION_SYMBOL = "\u00a7"
HCL_BLOCK_KEYWORD_RE = re.compile(r'\bdyn' + r'amic\s+"[a-z0-9_]+"')
BULLET_PREFIX_RE = re.compile(r"^(?:[-*]|\d+\.)\s+")


def _iter_repo_files() -> list[Path]:
    files: list[Path] = []
    for path in sorted(REPO_ROOT.rglob("*")):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.name in SKIP_FILES:
            continue
        if path.name.endswith((".tfstate", ".tfstate.backup")) or ".tfstate." in path.name:
            continue
        files.append(path)
    return files


def _extract_markdown_sentences(text: str) -> list[str]:
    lines = text.splitlines()
    in_code = False
    in_frontmatter = False
    prose_blocks: list[str] = []
    current_para: list[str] = []

    def flush_para() -> None:
        if current_para:
            prose_blocks.append(" ".join(current_para))
            current_para.clear()

    for idx, line in enumerate(lines):
        stripped = line.strip()
        if idx == 0 and stripped == "---":
            in_frontmatter = True
            continue
        if in_frontmatter:
            if stripped == "---":
                in_frontmatter = False
            continue
        if stripped.startswith("```"):
            flush_para()
            in_code = not in_code
            continue
        if in_code:
            continue
        if not stripped or stripped.startswith(("#", "|", "---")):
            flush_para()
            continue
        if BULLET_PREFIX_RE.match(stripped):
            flush_para()
            prose_blocks.append(BULLET_PREFIX_RE.sub("", stripped).strip())
            continue
        current_para.append(stripped)

    flush_para()

    sentences: list[str] = []
    for block in prose_blocks:
        for part in re.split(r"[.!?](?:\s+|$)", block):
            cleaned = part.strip()
            if cleaned:
                sentences.append(cleaned)
    return sentences


class AntiLeakAndMockTest(unittest.TestCase):
    """Enforce zero leaks, zero mocks, and clean style across tracked files."""

    def test_files_exist(self) -> None:
        self.assertGreater(len(_iter_repo_files()), 0)

    def test_no_leaked_identifiers_or_secrets(self) -> None:
        for path in _iter_repo_files():
            text = path.read_text(encoding="utf-8")
            lowered = text.lower()
            rel = str(path.relative_to(REPO_ROOT))
            with self.subTest(file=rel):
                for ident in LEAKED_IDENTIFIERS:
                    self.assertNotIn(
                        ident.lower(),
                        lowered,
                        f"Leaked identifier '{ident}' found in {rel}",
                    )
                for pat in SECRET_PATTERNS:
                    self.assertIsNone(
                        pat.search(text),
                        f"Secret pattern {pat.pattern} found in {rel}",
                    )
                for marker in MOCK_MARKERS:
                    self.assertNotIn(
                        marker,
                        lowered,
                        f"Mock marker '{marker}' found in {rel}",
                    )

    def test_no_emojis_section_symbol_or_banned_ai_words(self) -> None:
        word_patterns = {
            w: re.compile(rf"\b{re.escape(w)}\b", re.IGNORECASE)
            for w in BANNED_AI_WORDS
        }
        for path in _iter_repo_files():
            text = path.read_text(encoding="utf-8")
            rel = str(path.relative_to(REPO_ROOT))
            with self.subTest(file=rel):
                self.assertIsNone(
                    EMOJI_PATTERN.search(text),
                    f"Decorative emoji found in {rel}",
                )
                self.assertNotIn(
                    SECTION_SYMBOL,
                    text,
                    f"Forbidden section symbol found in {rel}",
                )
                scan_text = text
                if path.suffix == ".tf":
                    scan_text = HCL_BLOCK_KEYWORD_RE.sub("", text)
                for word, pat in word_patterns.items():
                    self.assertIsNone(
                        pat.search(scan_text),
                        f"Banned AI word '{word}' found in {rel}",
                    )

    def test_markdown_sentences_are_short(self) -> None:
        for path in _iter_repo_files():
            if path.suffix != ".md":
                continue
            rel = str(path.relative_to(REPO_ROOT))
            sentences = _extract_markdown_sentences(path.read_text(encoding="utf-8"))
            with self.subTest(markdown=rel):
                for sentence in sentences:
                    words = [w for w in sentence.split() if w]
                    self.assertLessEqual(
                        len(words),
                        20,
                        f"Sentence exceeds 20 words ({len(words)}) in {rel}: {sentence}",
                    )


if __name__ == "__main__":
    unittest.main()
