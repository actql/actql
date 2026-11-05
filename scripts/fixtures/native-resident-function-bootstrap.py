#!/usr/bin/env python3
"""Restore the original three streams, then exec the original Native image.

Only inherited descriptor numbers pass through GDB's no-shell command parser.
The private argv/environment DATA descriptor is anonymous and never reported.
"""
import json
import os
import resource
import sys


def main():
    streams = [int(value) for value in sys.argv[1:4]]
    with os.fdopen(int(sys.argv[4]), "r") as source:
        original = json.load(source)
    for destination, source in enumerate(streams):
        os.dup2(source, destination, inheritable=True)
    limit = resource.getrlimit(resource.RLIMIT_NOFILE)[0]
    if limit == resource.RLIM_INFINITY:
        limit = os.sysconf("SC_OPEN_MAX")
    os.closerange(3, limit)
    os.execve(original["argv"][0], original["argv"], original["environment"])


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # No Python error text or raw argv can enter GDB's diagnostic output.
        os._exit(125)
