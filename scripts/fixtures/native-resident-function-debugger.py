#!/usr/bin/env python3
"""GDB parents one original control; only function/stage DATA is retained.

Target stdout continues to its existing Node caller. Debugger text, target
arguments, environment, values, addresses and source paths are never reported.
No preload, attach, ASLR/security change or second execution is attempted.
"""
import json
import os
from pathlib import Path
import pty
import re
import shutil
import signal
import subprocess
import sys
import termios
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
                json.dump({"consumerExecutorEntered": entered.is_set(),
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
        master, slave = pty.openpty()
        attributes = termios.tcgetattr(slave)
        attributes[1] &= ~termios.OPOST
        attributes[3] &= ~(termios.ECHO | termios.ICANON | termios.ISIG)
        termios.tcsetattr(slave, termios.TCSANOW, attributes)
        commands = ["set pagination off", "set confirm off", "set startup-with-shell off",
                    "set print inferior-events off", "set print frame-arguments none",
                    "set print entry-values no", "set print address off",
                    "set disable-randomization off", "set follow-fork-mode parent",
                    "set detach-on-fork on", "handle SIGPIPE nostop noprint pass",
                    "handle SIGCHLD nostop noprint pass", "handle SIGUSR1 nostop noprint pass",
                    "handle SIGTERM nostop noprint pass", "unset environment LINES",
                    "unset environment COLUMNS", "set inferior-tty " + os.ttyname(slave),
                    "run", "thread apply all backtrace 16", "continue"]
        arguments = [debugger, "-q", "-nx", "-batch", "--return-child-result"]
        for command in commands:
            arguments.extend(["-ex", command])
        arguments.extend(["--args", *target])
        # This hash-fenced caller's exact original Native environment consists
        # of PATH and LANG. Exclude Python's own C-locale coercion variable.
        environment = {name: os.environ[name] for name in ("PATH", "LANG")}
        child = subprocess.Popen(arguments, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, env=environment)

        def forward_target():
            while True:
                try:
                    data = os.read(master, 65536)
                    if not data:
                        return
                    cursor = 0
                    while cursor < len(data):
                        cursor += os.write(1, data[cursor:])
                except OSError:
                    return

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
        output_thread = threading.Thread(target=forward_target, daemon=True)
        output_thread.start()
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
            os.close(slave)
            output_thread.join(timeout=1)
            os.close(master)
    publish()
    return code if code >= 0 else 128 - code


if __name__ == "__main__":
    try:
        sys.exit(run(sys.argv[1], sys.argv[2:]))
    except Exception:
        # No exception text: subprocess exceptions may include private argv.
        sys.exit(1)
