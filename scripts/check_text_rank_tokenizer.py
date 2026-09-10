"""Independent Unicode-16 tokenizer oracle from pinned UCD source data.

This is specification tooling, not a product tokenizer or a resource-bounded
evaluator. No host Unicode categories, normalize(), casefold() or regex is used.
"""
from itertools import groupby
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UCD = ROOT / "vendor/unicode/16.0.0"
CORPUS = ROOT / "portability/corpus/text-rank-tokenizer.json"


class UnicodeTables:
    def __init__(self, directory=UCD):
        spec = importlib.util.spec_from_file_location("unicode_generator", ROOT / "scripts/generate-unicode-tables.py")
        generator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generator)
        manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        for name, digest in generator.validate_manifest(manifest).items():
            if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
                raise ValueError(f"Unicode input hash mismatch: {name}")
        self.classes, self.categories = {}, {}
        self.canonical, self.compatibility, self.compositions, self.folds = {}, {}, {}, {}
        exclusions = generator.read_exclusions(directory / "CompositionExclusions.txt")
        pending = None
        for line in (directory / "UnicodeData.txt").read_text(encoding="utf-8").splitlines():
            fields = line.split(";")
            cp, name, category, combining = int(fields[0], 16), fields[1], fields[2], int(fields[3])
            if name.endswith(", First>"):
                pending = (cp, category)
            elif name.endswith(", Last>"):
                first, first_category = pending
                if first_category != category:
                    raise ValueError("Inconsistent UCD range")
                if category[0] in "LNM":
                    self.categories.update((i, category[0]) for i in range(first, cp + 1))
                pending = None
            elif category[0] in "LNM":
                self.categories[cp] = category[0]
            if combining:
                self.classes[cp] = combining
            decomposition = fields[5].split()
            if decomposition:
                tagged = decomposition[0].startswith("<")
                values = tuple(int(s, 16) for s in (decomposition[1:] if tagged else decomposition))
                self.compatibility[cp] = values
                if not tagged:
                    self.canonical[cp] = values
        for cp, values in self.canonical.items():
            if len(values) == 2 and cp not in exclusions and self.classes.get(values[0], 0) == 0:
                self.compositions[values] = cp
        for line in (directory / "CaseFolding.txt").read_text(encoding="utf-8").splitlines():
            body = line.split("#", 1)[0].strip()
            if body:
                code, status, mapping, _ = (part.strip() for part in body.split(";"))
                if status in ("C", "F"):
                    cp = int(code, 16)
                    if cp in self.folds:
                        raise ValueError("Duplicate default full fold")
                    self.folds[cp] = tuple(int(part, 16) for part in mapping.split())

    def decompose(self, cp, compatibility):
        if 0xAC00 <= cp <= 0xD7A3:
            syllable = cp - 0xAC00
            result = [0x1100 + syllable // 588, 0x1161 + syllable % 588 // 28]
            if syllable % 28:
                result.append(0x11A7 + syllable % 28)
            return result
        table = self.compatibility if compatibility else self.canonical
        if cp not in table:
            return [cp]
        return [d for part in table[cp] for d in self.decompose(part, compatibility)]

    def compose(self, left, right):
        if 0x1100 <= left < 0x1113 and 0x1161 <= right < 0x1176:
            return 0xAC00 + (left - 0x1100) * 588 + (right - 0x1161) * 28
        if 0xAC00 <= left <= 0xD7A3 and (left - 0xAC00) % 28 == 0 and 0x11A8 <= right < 0x11C3:
            return left + right - 0x11A7
        return self.compositions.get((left, right))

    def normalize(self, text, compatibility=False):
        if any(0xD800 <= ord(c) <= 0xDFFF for c in text):
            raise ValueError("MalformedUnicode")
        decomposed = [cp for c in text for cp in self.decompose(ord(c), compatibility)]
        # Stable order independently within consecutive non-starter runs.
        ordered = []
        for nonstarter, group in groupby(decomposed, key=lambda cp: self.classes.get(cp, 0) != 0):
            ordered.extend(sorted(group, key=lambda cp: self.classes[cp]) if nonstarter else group)
        result, starter, previous = [], None, 0
        for cp in ordered:
            combining = self.classes.get(cp, 0)
            composite = self.compose(result[starter], cp) if starter is not None and (previous == 0 or previous < combining) else None
            if composite is not None:
                result[starter] = composite
            else:
                if combining == 0:
                    starter = len(result)
                result.append(cp)
                previous = combining
        return "".join(chr(cp) for cp in result)

    def prepare(self, text):
        normalized = self.normalize(text, compatibility=True)
        folded = "".join(chr(cp) for c in normalized for cp in self.folds.get(ord(c), (ord(c),)))
        return self.normalize(folded)

    def tokenize(self, text, mode):
        if mode not in ("unicode_words", "char_bigram"):
            raise ValueError("InvalidTokenizer")
        prepared = self.prepare(text)
        runs, run = [], []
        for scalar in prepared:
            category = self.categories.get(ord(scalar))
            if category in ("L", "N") or category == "M" and run:
                run.append(scalar)
            else:
                if run:
                    runs.append("".join(run))
                run = []
        if run:
            runs.append("".join(run))
        if mode == "unicode_words":
            return prepared, runs
        return prepared, [token for run in runs for token in
                          ([run] if len(run) == 1 else [run[i:i + 2] for i in range(len(run) - 1)])]


def check():
    tables = UnicodeTables()
    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    if corpus["version"] != "actql-text-rank-tokenizer-vectors/0.1" or corpus["unicode_version"] != "16.0.0" or not corpus["cases"]:
        raise ValueError("InvalidCorpus")
    seen = set()
    for case in corpus["cases"]:
        fields = {"id", "text", "error"} if "error" in case else {
            "id", "text", "normalized", "unicode_words", "char_bigram",
        }
        if case.keys() != fields or not isinstance(case["id"], str) or not case["id"] or case["id"] in seen:
            raise ValueError("InvalidCase")
        seen.add(case["id"])
        if "error" in case:
            for mode in ("unicode_words", "char_bigram"):
                try:
                    tables.tokenize(case["text"], mode)
                except ValueError as error:
                    if str(error) != case["error"]:
                        raise
                else:
                    raise AssertionError(f"{case['id']} {mode}: expected rejection")
        else:
            for mode in ("unicode_words", "char_bigram"):
                normalized, tokens = tables.tokenize(case["text"], mode)
                if normalized != case["normalized"] or tokens != case[mode]:
                    raise AssertionError(f"{case['id']} {mode}: {normalized!r}, {tokens!r}")
    print(f"Unicode 16 text-rank tokenizers: {len(seen)} fixed cases verified")


if __name__ == "__main__":
    check()
