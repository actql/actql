"""Independent Calendar law oracle over the pinned transition artifact.

Expected intervals are hand-authored in the portability corpus, never generated
from MoonBit output. This checker uses integer Gregorian arithmetic and table
inversion, not datetime's timezone conversion or an ambient timezone database.
It is test tooling, not an ActQL evaluator or a production resource algorithm.
"""
from __future__ import annotations

from bisect import bisect_right
from datetime import datetime, timedelta
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "portability/corpus/calendar-boundaries.json"
TABLE = ROOT / "portability/corpus/calendar-tzdb-2025b.json"
EPOCH = datetime(1970, 1, 1)


def millis(value):
    # Naive datetimes represent integer civil coordinates here, never host time.
    d = value - EPOCH
    return d.days * 86400000 + d.seconds * 1000 + d.microseconds // 1000


def parse(text):
    if not text.endswith("Z"):
        raise ValueError("InvalidTimestamp")
    try:
        value = datetime.fromisoformat(text[:-1])
    except ValueError as error:
        raise ValueError("InvalidTimestamp") from error
    if value.tzinfo is not None or stamp(millis(value)) != text:
        raise ValueError("InvalidTimestamp")
    return millis(value)


def civil(value):
    try:
        return EPOCH + timedelta(milliseconds=value)
    except OverflowError as error:
        raise ValueError("BoundaryOutOfRange") from error


def stamp(value):
    d = civil(value)
    return (f"{d.year:04}-{d.month:02}-{d.day:02}T{d.hour:02}:{d.minute:02}:"
            f"{d.second:02}.{d.microsecond // 1000:03}Z")


class Zone:
    def __init__(self, profile, name):
        if name not in profile["zones"]:
            raise ValueError("UnknownZone")
        table = profile["zones"][name]
        self.start = profile["coverage_start_ms"]
        self.end = profile["coverage_end_ms"]
        self.times = [self.start] + [t["at_ms"] for t in table["transitions"]]
        self.offsets = [table["initial_offset_seconds"]] + [t["offset_seconds"] for t in table["transitions"]]

    def offset(self, utc):
        if not self.start <= utc < self.end:
            raise ValueError("BoundaryOutOfRange")
        return self.offsets[bisect_right(self.times, utc) - 1] * 1000

    def resolve(self, local):
        # Invert every distinct offset, then select the earliest valid occurrence.
        civil(local)
        candidates = []
        for seconds in set(self.offsets):
            utc = local - seconds * 1000
            if self.start <= utc < self.end and self.offset(utc) == seconds * 1000:
                candidates.append(utc)
        if candidates:
            return min(candidates)
        # A forward jump removes [old-local, new-local); advance to its instant.
        gaps = [at for i, at in enumerate(self.times[1:], 1)
                if at + self.offsets[i - 1] * 1000 <= local < at + self.offsets[i] * 1000]
        if gaps:
            return min(gaps)
        raise ValueError("BoundaryOutOfRange")


def floor(value, unit, week_start):
    d = value.replace(hour=0, minute=0, second=0, microsecond=0)
    try:
        if unit == "week":
            origin = {"monday": 0, "sunday": 6}[week_start]
            return d - timedelta(days=(d.weekday() - origin) % 7)
        if unit == "day":
            return d
        if unit == "month":
            return d.replace(day=1)
        if unit == "quarter":
            return d.replace(month=(d.month - 1) // 3 * 3 + 1, day=1)
        if unit == "year":
            return d.replace(month=1, day=1)
    except OverflowError as error:
        raise ValueError("BoundaryOutOfRange") from error
    raise ValueError("InvalidUnit")


def advance(d, unit, direction):
    try:
        if unit in ("day", "week"):
            return d + timedelta(days=direction * (1 if unit == "day" else 7))
        months = {"month": 1, "quarter": 3, "year": 12}[unit]
        index = (d.year - 1) * 12 + d.month - 1 + months * direction
        return d.replace(year=index // 12 + 1, month=index % 12 + 1)
    except (OverflowError, ValueError) as error:
        raise ValueError("BoundaryOutOfRange") from error


def bucket(zone, time, unit, week_start=None):
    d = floor(civil(time + zone.offset(time)), unit, week_start)
    start = zone.resolve(millis(d))
    while start > time:
        d = advance(d, unit, -1)
        start = zone.resolve(millis(d))
    while True:
        d = advance(d, unit, 1)
        end = zone.resolve(millis(d))
        if end > time:
            return [stamp(start), stamp(end)]
        # Equal resolved boundaries collapse instead of emitting zero-length rows.
        start = end


def evaluate(profile, case):
    zone = Zone(profile, case["timezone"])
    operation = case["operation"]
    if operation == "resolve":
        # Local civil text deliberately has no UTC suffix; parse only reuses the
        # strict Gregorian spelling check, not a timezone conversion.
        return stamp(zone.resolve(parse(case["local"] + "Z")))
    unit, week = case["unit"], case.get("week_start")
    if unit not in ("day", "week", "month", "quarter", "year"):
        raise ValueError("InvalidUnit")
    if ((unit == "week" and week not in ("monday", "sunday")) or
            (unit != "week" and week is not None)):
        raise ValueError("InvalidWeekStart")
    if operation == "bucket":
        return bucket(zone, parse(case["time"]), unit, week)
    if operation != "series":
        raise ValueError("InvalidOperation")
    start, end = parse(case["start"]), parse(case["end"])
    if start > end:
        raise ValueError("ReversedRange")
    rows = []
    while start < end:
        row = bucket(zone, start, unit, week)
        rows.append(row)
        start = parse(row[1])
        if len(rows) > 10000:
            raise ValueError("OracleFixtureLimit")
    return rows


def check():
    corpus = json.loads(CORPUS.read_text())
    if (corpus.get("version") != "actql-calendar-boundary-corpus/0.1" or
            not isinstance(corpus.get("cases"), list) or not corpus["cases"]):
        raise ValueError("Invalid Calendar boundary corpus")
    raw = TABLE.read_bytes()
    if "sha256:" + hashlib.sha256(raw).hexdigest() != corpus["transition_artifact_cid"]:
        raise ValueError("Calendar corpus transition pin mismatch")
    profile = json.loads(raw)
    if (profile["tzdb_version"] != corpus["tzdb_version"] or
            profile["conversion_law"] != corpus["conversion_law"]):
        raise ValueError("Calendar corpus profile mismatch")
    seen = set()
    for case in corpus["cases"]:
        fields = {
            "resolve": {"local"}, "bucket": {"unit", "time"},
            "series": {"unit", "start", "end"},
        }.get(case.get("operation"))
        required = {"id", "operation", "timezone"} | (fields or set())
        optional = {"expected", "error"} | ({"week_start"} if fields and "unit" in fields else set())
        if (fields is None or not required <= case.keys() or
                not case.keys() <= required | optional or
                not isinstance(case["id"], str) or not case["id"] or
                case["id"] in seen or ("expected" in case) == ("error" in case)):
            raise ValueError("Invalid corpus case")
        seen.add(case["id"])
        try:
            actual = evaluate(profile, case)
        except ValueError as error:
            if str(error) != case.get("error"):
                raise AssertionError(f"{case['id']}: unexpected {error}") from error
        else:
            if "error" in case or actual != case["expected"]:
                raise AssertionError(f"{case['id']}: {actual!r} != {case.get('expected')!r}")
    print(f"Calendar boundary corpus: {len(seen)} fixed cases verified")


if __name__ == "__main__":
    check()
