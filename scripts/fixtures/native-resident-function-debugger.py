#!/usr/bin/env python3
"""GDB follows the original control into its holder; only function/stage DATA is retained.

Target stdout continues to its existing Node caller. Debugger text, target
arguments, environment, values, addresses and source paths are never reported.
No preload, attach, ASLR/security change or second execution is attempted.
"""
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading


def consumer_entered(path):
    try:
        with open(path, "rb") as stream:
            # Only count the existing entry records; do not parse or publish
            # claimant identities or retain their bytes in a diagnostic.
            return all(stream.readline(1048576).endswith(b"\n") for _ in range(2))
    except OSError:
        return False


def run(report, target):
    entered = threading.Event()
    sampled = threading.Event()
    done = threading.Event()
    functions = []
    conditions = set()
    report_lock = threading.RLock()

    def publish():
        # One owner, same-directory atomic replacement. A killed writer leaves
        # the preceding complete snapshot available to the outer supervisor.
        with report_lock:
            temporary = report + ".tmp"
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w") as stream:
                json.dump({"sampleTarget": "holder-descendant",
                           "consumerExecutorEntered": entered.is_set(),
                           "sampleRequested": sampled.is_set(), "functions": functions,
                           "conditions": sorted(conditions | (
                               set() if entered.is_set() else {"stage-not-observed"}))}, stream)
            os.replace(temporary, report)

    publish()
    code = 1
    debugger = shutil.which("gdb")
    if debugger is None:
        conditions.add("debugger-unavailable")
    else:
        # The original control uses posix_spawn for its holder. Follow that
        # child through exec, detaching the control so its poll/current duties
        # continue normally. A parent sample cannot locate consumer execution.
        commands = ["set pagination off", "set confirm off", "set startup-with-shell off",
                    "set print inferior-events off", "set print frame-arguments none",
                    "set print entry-values no", "set print address off",
                    "set disable-randomization off", "set follow-fork-mode child",
                    "set detach-on-fork on", "set follow-exec-mode same",
                    "handle SIGPIPE nostop noprint pass",
                    "handle SIGCHLD nostop noprint pass", "handle SIGUSR1 nostop noprint pass",
                    "handle SIGTERM nostop noprint pass", "unset environment LINES",
                    "unset environment COLUMNS",
                    "run", "thread apply all backtrace 16", "continue"]
        arguments = [debugger, "-q", "-nx", "-batch", "--return-child-result"]
        for command in commands:
            arguments.extend(["-ex", command])
        # This hash-fenced caller's exact original Native environment consists
        # of PATH and LANG. Exclude Python's own C-locale coercion variable.
        environment = {name: os.environ[name] for name in ("PATH", "LANG")}
        streams = [os.dup(descriptor) for descriptor in range(3)]
        try:
            with tempfile.TemporaryFile() as original:
                original.write(json.dumps({"argv": target, "environment": environment}).encode("utf8"))
                original.flush()
                original.seek(0)
                # GDB preserves the FDs it inherited when starting an inferior.
                # Keep its own output pipe separate from all three real target
                # streams; the bootstrap closes every surplus FD before exec.
                inherited = (*streams, original.fileno())
                arguments.extend(["--args", sys.executable,
                                  str(Path(__file__).with_name("native-resident-function-bootstrap.py")),
                                  *(str(descriptor) for descriptor in inherited)])
                child = subprocess.Popen(arguments, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                         stderr=subprocess.STDOUT, text=True, env=environment,
                                         pass_fds=inherited)
        finally:
            for descriptor in streams:
                os.close(descriptor)

        def interrupt_after_entry():
            try:
                index = target.index("--executor-entry-log")
                entry = target[index + 1]
            except (ValueError, IndexError):
                return
            while not done.wait(0.1):
                if not consumer_entered(entry):
                    continue
                entered.set()
                publish()
                # A single sample after the original pre-call record; no
                # second signal, new attempt or changed 60-second case bound.
                if not done.wait(2):
                    try:
                        sampled.set()
                        publish()
                        child.send_signal(signal.SIGINT)
                    except ProcessLookupError:
                        pass
                return

        def stop(signum, _frame):
            # The original fixture's process-group watchdog still owns this
            # fresh case. Forward cancellation, never turn it into an ACK.
            try:
                children = Path(f"/proc/{child.pid}/task/{child.pid}/children").read_text().split()
                if len(children) == 1:
                    os.kill(int(children[0]), signum)
                else:
                    child.send_signal(signum)
            except (OSError, ValueError):
                pass

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        threading.Thread(target=interrupt_after_entry, daemon=True).start()
        try:
            for line in child.stdout:
                match = re.match(r"^#\d+\s+(?:0x[0-9a-f]+\s+in\s+)?"
                                 r"([A-Za-z_][A-Za-z_0-9:.$~]{0,179})(?=\s|\()", line)
                with report_lock:
                    changed = False
                    if sampled.is_set() and match and len(functions) < 64:
                        functions.append(match.group(1))
                        changed = True
                    lower = line.lower()
                    for text, condition in [("operation not permitted", "permission-denied"),
                                            ("function not implemented", "debugger-platform-unsupported"),
                                            ("could not trace", "trace-unavailable"),
                                            ("no stack", "no-stack"),
                                            ("input/output error", "registers-unavailable")]:
                        if text in lower and condition not in conditions:
                            conditions.add(condition)
                            changed = True
                    if changed:
                        publish()
            code = child.wait()
        finally:
            done.set()
    publish()
    return code if code >= 0 else 128 - code


if __name__ == "__main__":
    try:
        sys.exit(run(sys.argv[1], sys.argv[2:]))
    except Exception:
        # No exception text: subprocess exceptions may include private argv.
        sys.exit(1)
