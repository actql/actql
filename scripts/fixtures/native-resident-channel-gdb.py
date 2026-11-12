"""Observe existing control-channel calls without making inferior calls or retaining DATA.

Loaded inside GDB on Linux x64. Registers and pointers are private, transient
selectors only. Reports contain closed labels, bounded lengths and counts.
"""
import json
import os
from pathlib import Path


FRAME_PREFIXES = (b"consumer ", b"effect-review\n", b"release ", b"retained-plan ",
                  b"retained-transfer ", b"retained-current ", b"effect-current ",
                  b"effect-resume ")
MAX_FRAME = 16 * 1024 * 1024
MAX_GROUPS = 64


def frame_kind(prefix):
    for value in FRAME_PREFIXES:
        if prefix.startswith(value):
            return value.decode("ascii").strip()
    return "other"


def signed32(value):
    value = int(value) & 0xffffffff
    return value if value < 0x80000000 else value - 0x100000000


def wait_kind(value):
    return "running" if value == -2 else "error" if value < 0 else "exited" if value < 256 else "signaled"


def consumer_entered(path):
    try:
        with open(path, "rb") as stream:
            return all(stream.readline(1048576).endswith(b"\n") for _ in range(2))
    except OSError:
        return False


class Observations:
    def __init__(self, report, entry):
        self.report, self.entry = report, entry
        self.groups, self.last, self.calls, self.dropped = [], None, 0, 0
        self.waits, self.conditions = {}, set()
        self.send_returns = {}

    def record(self, value):
        self.calls += 1
        self.last = dict(value)
        for group in self.groups:
            if group["observation"] == value:
                group["count"] += 1
                break
        else:
            if len(self.groups) < MAX_GROUPS:
                self.groups.append({"observation": dict(value), "count": 1})
            else:
                self.dropped += 1
        self.publish()

    def publish(self):
        value = {"version": 1, "diagnosticOnly": True, "sampleTarget": "original-control",
                 "consumerExecutorEntered": consumer_entered(self.entry),
                 "channelCalls": self.calls, "droppedGroups": self.dropped,
                 "observations": self.groups, "last": self.last,
                 "waitCounts": self.waits, "sendReturns": self.send_returns,
                 "conditions": sorted(self.conditions)}
        temporary = self.report + ".tmp"
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream)
        os.replace(temporary, self.report)


def install(gdb, report, entry):
    observation = Observations(report, entry)
    active, sends = {}, {}

    def thread():
        return gdb.selected_thread().global_num

    def register(name):
        return int(gdb.parse_and_eval("$" + name))

    def memory(address, count):
        return bytes(gdb.selected_inferior().read_memory(address, count))

    def unavailable(condition):
        observation.conditions.add(condition)
        observation.publish()

    class Returned(gdb.FinishBreakpoint):
        def __init__(self, callback):
            super().__init__(gdb.newest_frame(), internal=True)
            self.callback = callback

        def stop(self):
            try:
                self.callback(signed32(self.return_value if self.return_value is not None else register("rax")))
            except Exception:
                unavailable("return-unavailable")
            return False

        def out_of_scope(self):
            unavailable("return-unavailable")

    class Call(gdb.Breakpoint):
        def __init__(self, symbol, callback):
            super().__init__(symbol, internal=True)
            self.callback = callback

        def stop(self):
            try:
                self.callback()
            except Exception:
                unavailable("registers-unavailable")
            return False

    def channel():
        key = thread()
        length, offset = signed32(register("rcx")), signed32(register("r8"))
        if not 0 < length <= MAX_FRAME or not 0 <= offset < length:
            unavailable("frame-bounds-unavailable")
            return
        prefix = memory(register("rdx"), min(length, max(map(len, FRAME_PREFIXES))))
        value = {"selectedKind": frame_kind(prefix), "frameBytes": length, "offset": offset,
                 "requestedKind": sends.get(key, "unobserved"),
                 # NativeHolderChannel::send reaches this C call only after its
                 # existing nonblocking child wait returned running.
                 "childWait": "running", "ioctl": "not-entered", "unreadBytes": None,
                 "write": "not-entered", "writeBytes": None,
                 "consumerExecutorEntered": consumer_entered(entry)}
        active[key] = {"value": value, "writer": register("rdi"), "reader": register("rsi")}

        def returned(result):
            value["channelReturn"] = "busy" if result == -2 else "failure" if result < 0 else "progress"
            value["returnedBytes"] = result if result >= 0 else None
            observation.record(value)
            active.pop(key, None)
        Returned(returned)

    def ioctl():
        state = active.get(thread())
        if state is None or register("rdi") != state["reader"] or register("rsi") != 0x541b:
            return
        address = register("rdx")

        def returned(result):
            if result < 0:
                state["value"]["ioctl"] = "failure"
            else:
                unread = int.from_bytes(memory(address, 4), "little", signed=True)
                if not 0 <= unread <= MAX_FRAME:
                    state["value"]["ioctl"] = "unavailable"
                else:
                    state["value"].update(ioctl="empty" if unread == 0 else "busy", unreadBytes=unread)
        Returned(returned)

    def write():
        state = active.get(thread())
        if state is None or register("rdi") != state["writer"]:
            return

        def returned(result):
            state["value"].update(write="progress" if result > 0 else "nonprogress", writeBytes=max(0, result))
        Returned(returned)

    def wait():
        def returned(result):
            kind = wait_kind(result)
            observation.waits[kind] = observation.waits.get(kind, 0) + 1
            observation.publish()
        Returned(returned)

    def send():
        key = thread()
        # MoonBit's native string ABI is UTF-16. Only a matching fixed routing
        # prefix is inspected, never a frame body or an arbitrary decoded value.
        pointer = register("rsi")
        first = memory(pointer, 2)
        kind = "other"
        for encoded in FRAME_PREFIXES:
            prefix = encoded.rstrip(b"\n")
            if first == prefix[:1] + b"\0" and memory(pointer, len(prefix) * 2) == prefix.decode("ascii").encode("utf-16-le"):
                kind = prefix.decode("ascii").strip()
                break
        sends[key] = kind

        def returned(result):
            status = "true" if result == 1 else "false" if result == 0 else "unavailable"
            label = kind + "/" + status
            observation.send_returns[label] = observation.send_returns.get(label, 0) + 1
            sends.pop(key, None)
            observation.publish()
        Returned(returned)

    # The stable C entry is sufficient for channel offsets and actual syscall
    # results even when optimized MoonBit method symbols are unavailable.
    Call("actql_executor_slot_channel_write", channel)
    Call("actql_executor_slot_wait", wait)
    Call("ioctl", ioctl)
    Call("write", write)
    method_installed = False

    def method_symbols(_event=None):
        nonlocal method_installed
        if method_installed:
            return
        try:
            import re
            text = gdb.execute("info functions NativeHolderChannel", to_string=True)
            names = set(re.findall(r"\b([A-Za-z_][A-Za-z_0-9:.$~]*NativeHolderChannel[A-Za-z_0-9:.$~]*send[A-Za-z_0-9:.$~]*)\b", text))
            if len(names) == 1:
                Call(names.pop(), send)
                method_installed = True
        except Exception:
            pass

    def finished(_event):
        if not method_installed:
            observation.conditions.add("requested-kind-unavailable")
        if observation.calls == 0:
            observation.conditions.add("channel-not-observed")
        observation.publish()

    gdb.events.new_objfile.connect(method_symbols)
    gdb.events.exited.connect(finished)
    method_symbols()
    observation.publish()
