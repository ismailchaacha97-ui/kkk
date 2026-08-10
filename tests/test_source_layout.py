import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "MQL4" / "Indicators" / "Adaptive_SMC_Dashboard.mq4"
PRESETS = ROOT / "MQL4" / "Presets"


def strip_comments_and_literals(text: str) -> str:
    """Return enough code text for delimiter checks without false positives."""
    result = []
    i = 0
    state = "code"
    while i < len(text):
        char = text[i]
        following = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if char == "/" and following == "/":
                state = "line_comment"
                i += 2
                continue
            if char == "/" and following == "*":
                state = "block_comment"
                i += 2
                continue
            if char == '"':
                state = "string"
                i += 1
                continue
            if char == "'":
                state = "literal"
                i += 1
                continue
            result.append(char)
        elif state == "line_comment":
            if char == "\n":
                state = "code"
                result.append(char)
        elif state == "block_comment":
            if char == "*" and following == "/":
                state = "code"
                i += 2
                continue
        elif state in {"string", "literal"}:
            quote = '"' if state == "string" else "'"
            if char == "\\":
                i += 2
                continue
            if char == quote:
                state = "code"
        i += 1
    return "".join(result)


class SourceLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")

    def test_delimiters_are_balanced(self):
        code = strip_comments_and_literals(self.source)
        for opening, closing in (("(", ")"), ("[", "]"), ("{", "}")):
            with self.subTest(pair=opening + closing):
                self.assertEqual(code.count(opening), code.count(closing))

    def test_expected_indicator_contract_exists(self):
        self.assertIn("#property indicator_buffers 4", self.source)
        for index in range(4):
            self.assertRegex(self.source, rf"SetIndexBuffer\({index},")
        self.assertIn("int OnCalculate(", self.source)
        self.assertIn("void OnChartEvent(", self.source)

    def test_all_preset_keys_are_real_inputs(self):
        inputs = set(
            re.findall(
                r"^input\s+[^;=]+?\s+(\w+)\s*(?:=|;)",
                self.source,
                flags=re.MULTILINE,
            )
        )
        self.assertGreater(len(inputs), 50)
        for preset in PRESETS.glob("*.set"):
            with self.subTest(preset=preset.name):
                keys = {
                    line.split("=", 1)[0].strip()
                    for line in preset.read_text(encoding="utf-8").splitlines()
                    if line.strip() and not line.lstrip().startswith(";") and "=" in line
                }
                self.assertFalse(keys - inputs, f"Unknown keys: {sorted(keys - inputs)}")

    def test_no_untracked_task_markers(self):
        self.assertNotIn("TODO", self.source)
        self.assertNotIn("FIXME", self.source)


if __name__ == "__main__":
    unittest.main()
