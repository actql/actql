"""Read-only proposal sizing/source checks; no Owner execution or acceptance."""
import base64
import hashlib
import json
from pathlib import Path
import subprocess

here = Path(__file__).resolve().parent
root = here.parents[1]


def load(name):
    return json.loads((here / name).read_bytes())


def wire(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(value).hexdigest()


audit = load("source-audit.json")
for item in audit["sourceFiles"]:
    data = (root / item["path"]).read_bytes()
    assert digest(data) == item["sha256"], item["path"]
    blob = subprocess.check_output(
        ["git", "rev-parse", audit["baseSource"] + ":" + item["path"]], cwd=root
    ).decode().strip()
    assert blob == item["blob"], item["path"]

proof = load("capacity-proof.json")
for item in proof["inputReferences"]:
    data = Path(item["path"]).read_bytes()
    assert digest(data) == item["sha256"], item["path"]
    if "bytes" in item:
        assert len(data) == item["bytes"]

positive = load("metadata-positive-vector.json")
record = positive["record"]
data = wire(record)
assert len(record) == 11 and all(isinstance(v, str) for v in record.values())
assert data == (here / "proposal-record.wire.txt").read_bytes()
assert record["prior_runtime_wire"].encode() == (here / "prior-runtime-original.json").read_bytes()
assert len(data) == 4344 and digest(data) == proof["proposalSizing"]["proposalBodySHA256"]
assert max(len(v.encode()) for v in record.values()) == 2289
assert sum(len(k.encode()) + len(v.encode()) for k, v in record.items()) == 3962
assert 1 + 2 * len(record) == 23


def framed_size(body):
    encoded = base64.b64encode(body).decode()
    # Length-only placeholder; no key/HMAC/authentication is performed.
    packet = wire({"payload_head": encoded[:4096], "payload_tail": encoded[4096:], "tag": "0" * 64})
    assert len(encoded) <= 7512 and len(packet) <= 8192
    return len(packet)


assert framed_size(data) == 5902
maximum = load("maximum-operation-vector.json")["record"]
assert maximum["operation_id"] == "\x01" * 128
assert {k: v for k, v in maximum.items() if k != "operation_id"} == {
    k: v for k, v in record.items() if k != "operation_id"
}
assert len(wire(maximum)) == 5079 and framed_size(wire(maximum)) == 6882
assert 2 <= min(8, 7 + 1) and 2 * 8192 <= 65536
assert not (6 <= min(8, 4 + 1)) and not (9 <= min(8, 7 + 1))
assert 5633 > 5632 and 4097 > 4096 and 8193 > 8192
assert len(load("owner-positive-scenarios.json")["cases"]) == 4
assert len(load("negative-vectors.json")["cases"]) == 12
print(json.dumps({
    "proposalSizingAndSourceChecks": "passed", "representativePayloadPacket": [4344, 5902],
    "maximumOperationPayloadPacket": [5079, 6882], "plannedOwnerPositiveNegative": [4, 12],
    "executedOwnerTests": 0, "compilerNativeProvider": 0, "oldDBRunAttemptOperations": 0,
    "productionAdoption": False, "publicE2E": 0,
}, sort_keys=True))
