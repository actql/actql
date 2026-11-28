"""Run one shared case through the installed public Python Local facades."""
import asyncio
import hashlib
import json
import os
from collections.abc import Mapping
from pathlib import Path
import sys


def plain(value):
    if isinstance(value, Mapping):
        return {key: plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(item) for item in value]
    return value


def same_json_value(actual, expected):
    # Python equality alone conflates boolean and numeric cells. Nested array
    # order and declared row/record key order survive the public conversion.
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(
            same_json_value(left, right) for left, right in zip(actual, expected)
        )
    if isinstance(expected, dict):
        return list(actual) == list(expected) and all(
            same_json_value(actual[key], value) for key, value in expected.items()
        )
    return actual == expected


def validate(case, state, rows):
    assert state["status"] == case["expected"]["status"]
    assert same_json_value(rows, case["expected"]["rows"])


def output_file(path):
    return open(path, "xb", opener=lambda name, flags: os.open(name, flags, 0o600))


def write_row(target, rows, row, case):
    assert len(rows) < len(case["expected"]["rows"])
    row = plain(row)
    target.write((json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))
    rows.append(row)


def validate_delivery(delivery, attempt_id, ref, result_name, target):
    assert delivery["kind"] == "found"
    attempt, record, receipt = (delivery[key] for key in ("attempt", "record", "hostReleaseReceipt"))
    assert attempt["attempt_id"] == attempt_id and attempt["result_name"] == result_name
    assert attempt["run_definition_cid"] == ref["runDefinitionCid"]
    assert record["state"] == "succeeded"
    data = Path(target).read_bytes()
    assert record["confirmed_byte_count"] == receipt["delivered_byte_count"] == len(data)
    assert receipt["delivered_sha256"] == hashlib.sha256(data).hexdigest()


def sync(case, directory, original, target):
    from actql import Client

    with Client.open(state_dir=directory) as client:
        if original is None:
            submission = client.new_submission()
            run = client.start_source(case["text"], format=case["format"], submission_ref=submission)
            state = run.wait()
        else:
            submission = original["submission"]
            observed = client.lookup_submission(submission)
            assert observed["kind"] == "ready" and plain(observed["admission"]["ref"]) == original["ref"]
            run = client.attach(original["ref"])
            assert plain(run.ref) == original["ref"]
            state = run.status()
        result_name = case["expected"]["resultName"]
        result = run.result(result_name)
        if original is not None:
            delivery = original["delivery"]
            assert plain(result.delivery_attempt(delivery["attempt"]["attempt_id"])) == delivery
        rows = []
        with output_file(target) as sink, result.rows() as reader:
            for row in reader:
                write_row(sink, rows, row, case)
            sink.flush()
            os.fsync(sink.fileno())
        assert reader.rows_yielded == len(rows)
        validate(case, state, rows)
        delivery = plain(reader.delivery_attempt())
        validate_delivery(delivery, reader.attempt_id, run.ref, result_name, target)
        return plain(submission), plain(run.ref), state["status"], rows, delivery


async def asynchronous(case, directory, original, target):
    from actql import AsyncClient

    async with await AsyncClient.open(state_dir=directory) as client:
        if original is None:
            submission = client.new_submission()
            run = await client.start_source(case["text"], format=case["format"], submission_ref=submission)
            state = await run.wait()
        else:
            submission = original["submission"]
            observed = await client.lookup_submission(submission)
            assert observed["kind"] == "ready" and plain(observed["admission"]["ref"]) == original["ref"]
            run = await client.attach(original["ref"])
            assert plain(run.ref) == original["ref"]
            state = await run.status()
        result_name = case["expected"]["resultName"]
        result = run.result(result_name)
        if original is not None:
            delivery = original["delivery"]
            assert plain(await result.delivery_attempt(delivery["attempt"]["attempt_id"])) == delivery
        rows = []
        with output_file(target) as sink:
            async with result.rows() as reader:
                async for row in reader:
                    write_row(sink, rows, row, case)
                sink.flush()
                os.fsync(sink.fileno())
        assert reader.rows_yielded == len(rows)
        validate(case, state, rows)
        delivery = plain(await reader.delivery_attempt())
        validate_delivery(delivery, reader.attempt_id, run.ref, result_name, target)
        return plain(submission), plain(run.ref), state["status"], rows, delivery


def observe_close():
    print(json.dumps(dict(stage="closed", pid=os.getpid(), clientCloseReturned=True, hostCloseReturned=True)), flush=True)
    assert sys.stdin.readline().strip() == "observed"
    print(json.dumps(dict(stage="close-observation-ack", pid=os.getpid())), flush=True)


def ordered(state_dir, fixture_path, original_path):
    from actql import Client

    raw = Path(fixture_path).read_bytes()
    fixture = json.loads(raw)
    cases = fixture["cases"]
    assert [case["originalId"] for case in cases] == list(range(1, 14))
    fixture_hash = hashlib.sha256(raw).hexdigest()
    fields = {"pid": os.getpid(), "fixtureSha256": fixture_hash}
    client = Client.open(state_dir=state_dir)
    try:
        print(json.dumps(dict(stage="ordered-opened", **fields)), flush=True)
        for case in cases:
            original_id, text, sql_sha256 = (case[key] for key in ("originalId", "text", "sqlSha256"))
            assert hashlib.sha256(text.encode("utf-8")).hexdigest() == sql_sha256
            identity = dict(originalId=original_id, sqlSha256=sql_sha256, **fields)
            print(json.dumps(dict(stage="ordered-query-start", **identity)), flush=True)
            query = client.aql(text)
            rows = plain(query.all(max_rows=1000))
            assert same_json_value(rows, case["rows"]), f"Original Python query {original_id} changed typed rows"
            run = query.execution
            ref = plain(run.ref)
            print(json.dumps(dict(stage="ordered-query-result", rows=rows, ref=ref, **identity)), flush=True)
        result_name = fixture["lastResultName"]
        with run.result(result_name).rows() as reader:
            first = plain(next(reader))
            assert reader.rows_yielded == 1 and same_json_value(first, rows[0])
        delivery = plain(reader.delivery_attempt())
        assert delivery["attempt"]["attempt_id"] == reader.attempt_id
        material = json.dumps(dict(ref=ref, resultName=result_name, delivery=delivery, **fields),
                              ensure_ascii=False, separators=(",", ":")) + "\n"
        with output_file(original_path) as retained:
            retained.write(material.encode("utf-8"))
        print(json.dumps(dict(stage="ordered-early-close", first=first, rowsYielded=1,
                              original=material, **fields)), flush=True)
    except BaseException as primary:
        try:
            client.close()
            observe_close()
        except BaseException as cleanup:
            primary.add_note(f"First close after original Python query failure: {cleanup!r}")
        raise
    client.close()
    observe_close()


def ordered_saved(state_dir, fixture_path, original_path):
    from actql import Client

    raw = Path(fixture_path).read_bytes()
    fixture = json.loads(raw)
    fixture_hash = hashlib.sha256(raw).hexdigest()
    material = Path(original_path).read_bytes()
    original = json.loads(material)
    last = fixture["cases"][-1]
    assert last["originalId"] == 13
    assert original["fixtureSha256"] == fixture_hash and original["pid"] != os.getpid()
    result_name = fixture["lastResultName"]
    assert original["resultName"] == result_name
    early = original["delivery"]
    assert early["record"]["state"] == "cancelled" and early["hostReleaseReceipt"] is None
    case = {"expected": {"rows": last["rows"], "status": "succeeded"}}
    sink_path = original_path + ".saved.jsonl"
    with Client.open(state_dir=state_dir) as client:
        run = client.attach(original["ref"])
        ref = plain(run.ref)
        assert ref == original["ref"]
        status = run.status()
        result = run.result(result_name)
        early_attempt = early["attempt"]["attempt_id"]
        assert plain(result.delivery_attempt(early_attempt)) == early
        rows = []
        with output_file(sink_path) as sink, result.rows() as reader:
            for row in reader:
                write_row(sink, rows, row, case)
            sink.flush()
            os.fsync(sink.fileno())
        assert reader.rows_yielded == len(rows) and reader.attempt_id != early_attempt
        validate(case, status, rows)
        delivery = plain(reader.delivery_attempt())
        validate_delivery(delivery, reader.attempt_id, ref, result_name, sink_path)
        assert plain(result.delivery_attempt(early_attempt)) == early
    print(json.dumps(dict(stage="ordered-saved-result", pid=os.getpid(), originalPid=original["pid"],
                          fixtureSha256=fixture_hash, originalSha256=hashlib.sha256(material).hexdigest(),
                          ref=ref, resultName=result_name, rows=rows, delivery=delivery,
                          earlyDelivery=early, submissionCalls=0)), flush=True)
    observe_close()


def parity():
    facade, phase, state_dir, fixture_path, original_path = sys.argv[1:]
    assert facade in ("sync", "async") and phase in ("run", "saved")
    raw = Path(fixture_path).read_bytes()
    case = json.loads(raw)
    fixture_hash = hashlib.sha256(raw).hexdigest()
    original = json.loads(Path(original_path).read_bytes()) if phase == "saved" else None
    if original is not None:
        assert original["pid"] != os.getpid() and original["fixtureSha256"] == fixture_hash
    sink_path = original_path + "." + phase + ".jsonl"
    if facade == "sync":
        submission, ref, status, rows, delivery = sync(case, state_dir, original, sink_path)
    else:
        submission, ref, status, rows, delivery = asyncio.run(asynchronous(case, state_dir, original, sink_path))
    if original is None:
        with open(original_path, "x", encoding="utf-8", opener=lambda name, flags: os.open(name, flags, 0o600)) as target:
            json.dump(dict(pid=os.getpid(), fixtureSha256=fixture_hash, submission=submission, ref=ref, delivery=delivery), target)
    print(json.dumps(dict(stage="observed", phase=phase, runtime="python-" + facade, pid=os.getpid(),
                          fixtureSha256=fixture_hash, caseId=case["id"], ref=ref, status=status,
                          resultName=case["expected"]["resultName"], rows=rows, readerComplete=True,
                          submissionCalls=1 if phase == "run" else 0, delivery=delivery,
                          originalDeliveryRecovered=original is not None)), flush=True)
    observe_close()


if __name__ == "__main__":
    if sys.argv[1:2] == ["--ordered"]:
        ordered(*sys.argv[2:])
    elif sys.argv[1:2] == ["--ordered-saved"]:
        ordered_saved(*sys.argv[2:])
    else:
        parity()
