"""Verify zero leaked identifiers, secrets, mocks, emojis, or banned words."""

import hashlib
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

BINARY_EXTENSIONS = frozenset({
    ".webp",
    ".gif",
    ".png",
    ".jpg",
    ".jpeg",
})

# SHA-256 digests of normalized lowercase forbidden customer/internal tokens.
FORBIDDEN_TOKEN_SHA256 = frozenset({
    "28a6c9ad99acc2abeef4831da37cf37001345f05fa7327562ee4a9b167019b04",
    "bf2e17a1a6bc6728a531b1f29fc3e9344836b4ee2dbc4826d52e7fad1ab903b4",
    "a1ff4908fbe5168909d20652cd786c91f25e62668cb7704e00b76b48bbd77061",
    "39c55727348dc27b1dfcca0c18ef5b993b5c5d05c35e84dda10667ffbf4901dd",
    "b39879ae27ef3ea552c5b1ef0d2e27d31e1e86fd9000f8e790efac1d4d66993b",
    "f7bed5a9de858cf4a466529421cb2394beafac86339684ef34b831877a0ae5d9",
    "cfb193f5ee1e7027fe5cfaaac3069069112470cd1de7dde83c109cfadd078f5a",
    "7ce3b7e784772b32867cef471271a3ddf571d4197f8e0a948d9106fa8470b2fe",
    "d43e610ed1d8b1bdf2fc1d636d5db802e331d6c3e8467e65f26b1ed874f5ad55",
    "05bc6fa1ff0770f5de13c86f1d27418c938adea2dac09bf99680e8c31bf89c1c",
    "8d2d5be141e37e13f3eaa4a427c1c998eb2f3f9d66d22bb85322e4f5e1cc65f5",
    "ff395a42edbe5317b427b2d700de5be8c6452880ba9a46f66391de6907b887b2",
    "bcaeb7aaf13db3381e1c0c07ca7d7c9e0b58bb1a77aa177c420d9ddc1f42b72f",
    "eadba710424a7ccf76ee3a5b175ea916c5095c23e0c9eb73cd06e0bd391a88de",
    "ea3b268fa7164cf31bb5a5b7d5a70a1da3411e7d2bb36734dca05bd4d97e611d",
    "fc3fcf326138c3a556919d0e9e38100c7f3d8ead8a6a2f2b80af0bb3bc3e7ad7",
    "d4d98d8e8d9d1caf68c53b512ffa9add380e62dde5437cf9a3dec954b87e4bd1",
    "8aabce2e29396d5ce7e7ff8a0c76829c638938d3dd86642dfa8d4f7850492673",
    "159bc6a26ae434afaf52019da41182f185220ad04d4a330e4cd42c631f58adf8",
    "49abed4953748a8a9a8295f28fe864af4ce0d856e0fa9f69ee1a4463cb246239",
    "13ed7955a8035437bf820cb1d940b7c222b86030834d0aecf9333acfa50735b4",
    "4e41237f5f263ce5dc9566a6ba831e3b732297c006415ec51c16b440d4e7c962",
    "b0b70f066e82230c9ae95610a7aeec44a28f8cf4c6d2edb1e4e231027055469f",
    "d599e93c589788ef7cf53ec1c648cc1c64244ce66b8d1785aa5b7293a8d97a68",
    "42db212c2a8ab6fe26978fadcba7c6f3c8c9ae7a81a7af34930ca174fede649b",
    "4c77cac1139b0f6d8f1811079c7e14daf82696b71a8804722e9fc44a509c1fc4",
    "188e6a694d69c6728ad7ea2ba5b5553dda27478b1bc2e4bb7cc50850280742bd",
    "c4c86be45204a944b7d1ffe6d5adec4f8bdfb7784b45b6c24d78f6e3ed9bccca",
    "133937e4fbee1a2cc88b809af2ff3ff8a964a8f4c6cd5996af6d49b10c50d203",
})

LEAKED_IDENTIFIERS = (
    "/usr/local/" + "google/home/",
    "@" + "google.com",
    ".c.googlers." + "com",
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
        if path.suffix.lower() in BINARY_EXTENSIONS:
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
        if not stripped or stripped.startswith(("#", "|", "---", "<picture", "</picture", "<source", "<img", "![")):
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
        alnum_re = re.compile(r"[a-z0-9]+")
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
                tokens = alnum_re.findall(lowered)
                for idx, tok in enumerate(tokens):
                    digest = hashlib.sha256(tok.encode("utf-8")).hexdigest()
                    self.assertNotIn(digest, FORBIDDEN_TOKEN_SHA256, f"Forbidden token digest {digest} in {rel}")
                    if idx + 1 < len(tokens):
                        pair_digest = hashlib.sha256((tok + tokens[idx + 1]).encode("utf-8")).hexdigest()
                        self.assertNotIn(pair_digest, FORBIDDEN_TOKEN_SHA256, f"Forbidden token pair digest {pair_digest} in {rel}")
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

    def test_visual_assets_have_valid_headers(self) -> None:
        webp_path = REPO_ROOT / "assets" / "cloud-city-ingestion.webp"
        gif_path = REPO_ROOT / "assets" / "cloud-city-ingestion.gif"

        self.assertTrue(webp_path.is_file(), f"Missing {webp_path}")
        self.assertGreater(webp_path.stat().st_size, 100_000)

        webp_head = webp_path.read_bytes()[:12]
        self.assertEqual(webp_head[:4], b"RIFF")
        self.assertEqual(webp_head[8:12], b"WEBP")

        self.assertFalse(gif_path.exists(), f"Duplicate GIF asset must not exist: {gif_path}")


if __name__ == "__main__":
    unittest.main()
