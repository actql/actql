"""Independent, pretokenized BM25 law oracle; not a product evaluator.

Natural logarithms use rational atanh-series enclosures until both endpoints
round to the same binary64 value. No host logarithm or product output is used.
"""
from collections import Counter
from fractions import Fraction
from functools import lru_cache
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "portability/corpus/text-rank-numeric.json"


def bits(value):
    return struct.pack(">d", value).hex()


def finite(value):
    if not math.isfinite(value):
        raise ValueError("NonFinite")
    return value


def log_interval(value, terms):
    # ln(x) = 2 atanh((x-1)/(x+1)), for 1 <= x <= 2.
    z = (value - 1) / (value + 1)
    square = z * z
    power = z
    total = Fraction(0)
    for i in range(terms):
        total += power / (2 * i + 1)
        power *= square
    lower = 2 * total
    remainder = 2 * power / ((2 * terms + 1) * (1 - square))
    return lower, lower + remainder


@lru_cache(maxsize=4096)
def rounded_log(value):
    finite(value)
    if value <= 0:
        raise ValueError("LogDomain")
    if value == 1:
        return 0.0
    n, d = value.as_integer_ratio()
    exponent = n.bit_length() - d.bit_length()
    mantissa = Fraction(n, d) / Fraction(2) ** exponent
    if mantissa < 1:
        mantissa *= 2
        exponent -= 1
    for terms in (16, 32, 64, 128, 256):
        low, high = log_interval(mantissa, terms)
        two_low, two_high = log_interval(Fraction(2), terms)
        if exponent >= 0:
            low += exponent * two_low
            high += exponent * two_high
        else:
            low += exponent * two_high
            high += exponent * two_low
        if bits(float(low)) == bits(float(high)):
            return float(low)
    raise ValueError("UnresolvedLogRounding")


def string_key(value):
    return value.encode("utf-16-be")


def admitted(rows):
    if not isinstance(rows, list):
        raise ValueError("InvalidRows")
    seen = set()
    for row in rows:
        if (not isinstance(row, dict) or row.keys() != {"id", "tokens"} or
                not isinstance(row["id"], str) or not isinstance(row["tokens"], list) or
                any(not isinstance(token, str) for token in row["tokens"])):
            raise ValueError("InvalidRows")
        string_key(row["id"])
        if row["id"] in seen:
            raise ValueError("DuplicateIdentity")
        seen.add(row["id"])
        for token in row["tokens"]:
            if not token:
                raise ValueError("EmptyToken")
            string_key(token)
    return rows


def rank(case):
    docs, queries = admitted(case["corpus"]), admitted(case["queries"])
    if any(type(case[key]) not in (int, float) for key in ("k1", "b")):
        raise ValueError("InvalidScoring")
    k1, b = float(case["k1"]), float(case["b"])
    if not math.isfinite(k1) or k1 <= 0 or not math.isfinite(b) or not 0 <= b <= 1:
        raise ValueError("InvalidScoring")
    k = case["k"]
    if isinstance(k, bool) or not isinstance(k, int) or not 1 <= k <= 9007199254740991:
        raise ValueError("InvalidK")
    frequencies = [Counter(doc["tokens"]) for doc in docs]
    df = Counter()
    for frequencies_in_doc in frequencies:
        df.update(frequencies_in_doc.keys())
    total_length = sum(len(doc["tokens"]) for doc in docs)
    if not docs or total_length == 0:
        return []
    average = finite(float(total_length) / float(len(docs)))
    result = []
    for query in sorted(queries, key=lambda row: string_key(row["id"])):
        terms = sorted(set(query["tokens"]), key=string_key)
        scores = []
        for doc, tf in zip(docs, frequencies):
            score = 0.0
            for term in terms:
                if term not in tf:
                    continue
                # Each displayed binary operation has its own binary64 rounding.
                numerator = finite(finite(float(len(docs)) - float(df[term])) + 0.5)
                denominator = finite(float(df[term]) + 0.5)
                idf = rounded_log(finite(1.0 + finite(numerator / denominator)))
                ratio = finite(float(len(doc["tokens"])) / average)
                norm = finite(finite(1.0 - b) + finite(b * ratio))
                weighted_tf = finite(float(tf[term]) * finite(k1 + 1.0))
                divisor = finite(float(tf[term]) + finite(k1 * norm))
                contribution = finite(idf * finite(weighted_tf / divisor))
                score = finite(score + contribution)
            if score != 0:
                scores.append((doc["id"], score))
        scores.sort(key=lambda pair: (-pair[1], string_key(pair[0])))
        for position, (identity, score) in enumerate(scores[:k], 1):
            result.append({"query_id": query["id"], "candidate_id": identity,
                           "score_bits": bits(score), "rank": position})
    return result


def check():
    corpus = json.loads(CORPUS.read_text())
    if (corpus["version"] != "actql-text-rank-numeric-vectors/0.1" or
            corpus["status"] != "specification-only-pretokenized" or
            not corpus["cases"] or not corpus["logarithms"]):
        raise ValueError("InvalidCorpus")
    for case in corpus["logarithms"]:
        value = struct.unpack(">d", bytes.fromhex(case["input_bits"]))[0]
        if bits(rounded_log(value)) != case["expected_bits"]:
            raise AssertionError(f"log {case['input_bits']}")
    seen = set()
    for case in corpus["cases"]:
        fields = {"id", "corpus", "queries", "k1", "b", "k"}
        expectation = {"error"} if "error" in case else {"expected"}
        if case.keys() != fields | expectation or case["id"] in seen:
            raise ValueError("InvalidCase")
        seen.add(case["id"])
        try:
            actual = rank(case)
        except ValueError as error:
            if str(error) != case.get("error"):
                raise AssertionError(f"{case['id']}: {error}") from error
        else:
            if "error" in case or actual != case["expected"]:
                raise AssertionError(f"{case['id']}: {actual!r}")
            # Reordering either input and repeating query terms are semantic no-ops.
            variant = {**case, "corpus": list(reversed(case["corpus"])),
                       "queries": [{**q, "tokens": q["tokens"] * 2} for q in reversed(case["queries"])]}
            if rank(variant) != actual:
                raise AssertionError(f"{case['id']}: permutation or query multiplicity drift")
    print(f"Text ranking: {len(seen)} BM25 cases and {len(corpus['logarithms'])} logarithms verified")


if __name__ == "__main__":
    check()
