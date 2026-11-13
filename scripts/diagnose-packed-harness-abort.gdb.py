"""Temporary, bounded native-stack observation of one original test command."""
import json
import os
from pathlib import Path

import gdb

directory = Path(os.environ["ACTQL_PACKED_HARNESS_EVIDENCE_DIRECTORY"])
original = gdb.selected_inferior().num
state = {"originalInferior": original, "parentExit": None, "signals": [], "exits": []}
trace_bytes = 0
trace_limit = 1024 * 1024


def save():
    (directory / "native-events.json").write_text(json.dumps(state, indent=2) + "\n")


def stopped(event):
    global trace_bytes
    if not isinstance(event, gdb.SignalEvent):
        return
    if event.stop_signal not in ("SIGABRT", "SIGSEGV", "SIGBUS", "SIGILL", "SIGFPE"):
        return
    inferior = gdb.selected_inferior()
    item = {"inferior": inferior.num, "pid": inferior.pid, "signal": event.stop_signal}
    # Native function stacks only: never locals, heap memory or a core image.
    if len(state["signals"]) < 8 and trace_bytes < trace_limit:
        try:
            text = gdb.execute("thread apply all bt 24", to_string=True)
            data = (json.dumps(item) + "\n" + text).encode()[:trace_limit - trace_bytes]
            with (directory / "native-backtrace.log").open("ab") as stream:
                stream.write(data)
            trace_bytes += len(data)
            item["backtraceCaptured"] = True
        except gdb.error as error:
            item["backtraceCaptured"] = False
            item["debuggerError"] = str(error)[:256]
        state["signals"].append(item)
    save()


def exited(event):
    if len(state["exits"]) < 256:
        state["exits"].append({"inferior": event.inferior.num,
                               "exitCode": getattr(event, "exit_code", None)})
    if event.inferior.num == original:
        state["parentExit"] = {"exitCode": getattr(event, "exit_code", None)}
    save()


gdb.events.stop.connect(stopped)
gdb.events.exited.connect(exited)
for setting in (
    "set pagination off",
    "set confirm off",
    "set auto-load off",
    "set debuginfod enabled off",
    "set disable-randomization off",
    "set print frame-arguments none",
    "set print elements 16",
    "set print max-depth 1",
    "set detach-on-fork off",
    "set follow-fork-mode parent",
    "set follow-exec-mode same",
    "set schedule-multiple on",
    "handle SIGPIPE nostop noprint pass",
    "handle SIGABRT stop print pass",
):
    gdb.execute(setting)
save()
try:
    gdb.execute("run")
    while state["parentExit"] is None:
        # An exited test child can remain selected. Continue the original live
        # coordinator and all other attached inferiors, rather than quitting it.
        live = [inferior for inferior in gdb.inferiors() if inferior.pid]
        if not live:
            raise gdb.GdbError("No live inferior before the original parent exit")
        selected = next((inferior for inferior in live if inferior.num == original), live[0])
        gdb.execute("inferior " + str(selected.num))
        gdb.execute("continue")
except gdb.error as error:
    state["debuggerError"] = str(error)[:256]
    save()
# The Node test coordinator's own exit remains separate from debugger status.
# A missing natural parent exit cannot become a successful diagnostic.
code = state["parentExit"]["exitCode"] if state["parentExit"] else None
gdb.execute("quit " + str(code if isinstance(code, int) and 0 <= code <= 255 else 70))
