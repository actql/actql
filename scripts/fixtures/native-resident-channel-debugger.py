#!/usr/bin/env python3
"""Keep the original control under GDB; reuse its original stream bootstrap."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile


def run(report, target):
    debugger = shutil.which("gdb")
    if debugger is None:
        descriptor = os.open(report, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            json.dump({"conditions": ["debugger-unavailable"]}, stream)
        return 1
    index = target.index("--executor-entry-log")
    entry = target[index + 1]
    environment = {name: os.environ[name] for name in ("PATH", "LANG")}
    commands = ["set pagination off", "set confirm off", "set startup-with-shell off",
                "set print inferior-events off", "set print frame-arguments none",
                "set print address off", "set disable-randomization off",
                "set follow-fork-mode parent", "set detach-on-fork on",
                "set follow-exec-mode same", "set breakpoint pending on",
                "handle SIGPIPE nostop noprint pass", "handle SIGCHLD nostop noprint pass",
                "handle SIGTERM nostop noprint pass", "handle SIGINT nostop noprint pass"]
    arguments = [debugger, "-q", "-nx", "-batch", "--return-child-result"]
    for command in commands:
        arguments.extend(["-ex", command])
    observer = str(Path(__file__).with_name("native-resident-channel-gdb.py"))
    program = ("import importlib.util,gdb; "
               f"s=importlib.util.spec_from_file_location('channel_observer',{observer!r}); "
               "m=importlib.util.module_from_spec(s);s.loader.exec_module(m); "
               f"m.install(gdb,{report!r},{entry!r})")
    arguments.extend(["-ex", "python " + program, "-ex", "run"])
    streams = [os.dup(descriptor) for descriptor in range(3)]
    try:
        with tempfile.TemporaryFile() as original:
            original.write(json.dumps({"argv": target, "environment": environment}).encode("utf8"))
            original.flush()
            original.seek(0)
            inherited = (*streams, original.fileno())
            arguments.extend(["--args", sys.executable,
                              str(Path(__file__).with_name("native-resident-function-bootstrap.py")),
                              *(str(descriptor) for descriptor in inherited)])
            child = subprocess.Popen(arguments, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, env=environment, pass_fds=inherited)
    finally:
        for descriptor in streams:
            os.close(descriptor)

    def stop(signum, _frame):
        # Cancellation belongs to this original fresh fixture. There is no
        # sampling signal, attach, second start, or success inferred from exit.
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
    code = child.wait()
    return code if code >= 0 else 128 - code


if __name__ == "__main__":
    try:
        sys.exit(run(sys.argv[1], sys.argv[2:]))
    except Exception:
        # Private target argv and debugger exceptions are never forwarded.
        sys.exit(1)
