"""Trusted optional Table I/O using the existing managed-process protocol.

No approval, request identity or replay decision is made here. The Host supplies
an already claimed whole-Relation operation. Transport acknowledgement is not a
commit receipt; original-operation reconciliation is a separate read.
"""
import json
import math
import os
import struct

PROTOCOL = "actql-local-execution/0.1"
MAX_BYTES = 4 * 1024 * 1024
MAX_NODES = 100000
MAX_DEPTH = 32
ENVELOPE = {"protocol", "session", "run", "kind", "sequence", "body"}


class ProtocolRefusal(ValueError):
    pass


def exact_keys(value, keys):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise ProtocolRefusal("TableProcessShape")


def check_shape(value, depth=0, count=None):
    count = [0] if count is None else count
    count[0] += 1
    if count[0] > MAX_NODES or depth > MAX_DEPTH:
        raise ProtocolRefusal("TableProcessShapeLimit")
    if value is None or type(value) in (bool, int):
        return
    if type(value) is float and math.isfinite(value):
        return
    if isinstance(value, str):
        value.encode("utf-8", errors="strict")
        return
    if isinstance(value, dict):
        for key, item in value.items():
            key.encode("utf-8", errors="strict")
            check_shape(item, depth + 1, count)
        return
    if isinstance(value, list):
        for item in value:
            check_shape(item, depth + 1, count)
        return
    raise ProtocolRefusal("TableProcessValue")


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ProtocolRefusal("TableProcessDuplicateKey")
        value[key] = item
    return value


def reject_constant(_):
    raise ProtocolRefusal("TableProcessNumber")


def precheck_depth(text):
    # Reject deep input before JSON's recursive parser can materialize it.
    depth, quoted, escaped = 0, False, False
    for char in text:
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char in "[{":
            depth += 1
            if depth > MAX_DEPTH:
                raise ProtocolRefusal("TableProcessShapeLimit")
        elif char in "]}":
            depth -= 1


def read_exact(stream, length):
    result = bytearray(length)
    offset = 0
    while offset < length:
        count = stream.readinto(memoryview(result)[offset:])
        if not count:
            raise EOFError("TableProcessTruncated")
        offset += count
    return result


def read_frame(stream):
    size = struct.unpack(">I", read_exact(stream, 4))[0]
    if not 1 <= size <= MAX_BYTES:
        raise ProtocolRefusal("TableProcessByteLimit")
    text = read_exact(stream, size).decode("utf-8", errors="strict")
    precheck_depth(text)
    value = json.loads(text, object_pairs_hook=unique_object, parse_constant=reject_constant)
    check_shape(value)
    return value


def write_frame(stream, value):
    check_shape(value)
    encoded = json.dumps(value, ensure_ascii=False, allow_nan=False,
                         separators=(",", ":")).encode("utf-8")
    if not 1 <= len(encoded) <= MAX_BYTES:
        raise ProtocolRefusal("TableProcessByteLimit")
    frame = memoryview(struct.pack(">I", len(encoded)) + encoded)
    while frame:
        written = stream.write(frame)
        if not written:
            raise EOFError("TableProcessWriteClosed")
        frame = frame[written:]
    stream.flush()


def dispatch(body, catalog_factory=None):
    # Import the optional physical libraries only after the ordinary bounded
    # handshake. Starting the channel neither opens the Catalog nor stages data.
    from catalog import TableCatalog
    from physical import PhysicalRefusal

    exact_keys(body, {"catalog", "command", "payload"})
    config, payload, command = body["catalog"], body["payload"], body["command"]
    exact_keys(config, {"database", "warehouse", "catalogCid", "limits"})
    for name in ("database", "warehouse"):
        if not isinstance(config[name], str) or not os.path.isabs(config[name]):
            raise ProtocolRefusal("TableProcessConfiguration")
    exact_keys(config["limits"], {"bytes", "files", "operations"})
    if any(type(value) is not int or not 1 <= value <= 9007199254740991
           for value in config["limits"].values()):
        raise ProtocolRefusal("TableProcessConfiguration")
    shapes = {"write": {"operation", "mapping", "rows", "reservation"},
              "reconcile": {"operation"}, "read": {"receipt", "mapping"},
              "cleanup": {"operation"}, "inspect": {"operation"}}
    if command not in shapes:
        raise ProtocolRefusal("TableProcessCommand")
    exact_keys(payload, shapes[command])
    factory = TableCatalog if catalog_factory is None else catalog_factory
    catalog = factory(config["database"], config["warehouse"], config["catalogCid"], config["limits"])
    try:
        try:
            if command == "write":
                result = catalog.write_claimed(payload["operation"], payload["mapping"],
                                               payload["rows"], payload["reservation"])
            elif command == "reconcile":
                result = catalog.reconcile(payload["operation"])
            elif command == "read":
                result = catalog.read_generation(payload["receipt"], payload["mapping"])
            elif command == "inspect":
                result = catalog.inspect_target(payload["operation"])
            else:
                result = catalog.cleanup_after_stop(payload["operation"])
            return {"ok": True, "result": result}
        except PhysicalRefusal as error:
            # An explicitly validated physical refusal is still not a common
            # Effect outcome. The Host must classify it after durable capture.
            return {"ok": False, "code": str(error)}
    finally:
        catalog.engine.dispose()


def serve(stream, catalog_factory=None):
    hello = read_frame(stream)
    exact_keys(hello, ENVELOPE)
    if hello["protocol"] != PROTOCOL or hello["kind"] != "hello" or \
            type(hello["sequence"]) is not int or hello["sequence"] != 0 or hello["body"] is not None or \
            not isinstance(hello["session"], str) or not hello["session"] or \
            not isinstance(hello["run"], str) or not 1 <= len(hello["run"]) <= 256:
        # This initial I/O worker does not accept delegated execution-budget
        # accounting; a transport byte bound is not an ActQL resource proof.
        raise ProtocolRefusal("TableProcessHandshake")

    def reply(kind, sequence, body):
        write_frame(stream, {**hello, "kind": kind, "sequence": sequence, "body": body})

    reply("ready", 0, None)
    sequence = 0
    while True:
        message = read_frame(stream)
        exact_keys(message, ENVELOPE)
        if any(message[name] != hello[name] for name in ("protocol", "session", "run")) or \
                type(message["sequence"]) is not int:
            raise ProtocolRefusal("TableProcessForeignMessage")
        if message["kind"] == "stop" and message["sequence"] == sequence and message["body"] is None:
            return
        if sequence != 0 or message["kind"] != "execute" or message["sequence"] != 1:
            raise ProtocolRefusal("TableProcessSequence")
        sequence = 1
        try:
            result = dispatch(message["body"], catalog_factory)
        except Exception:
            # Unexpected I/O errors do not establish noncommit. Do not disclose
            # SQL, paths, credentials or exception text on the response channel.
            reply("failed", sequence, {"code": "TablePhysicalUnknown"})
            return
        reply("reply", sequence, result)


if __name__ == "__main__":
    with os.fdopen(3, "r+b", buffering=0) as channel:
        serve(channel)
