"""Compiler-call transport through the original Native process Owner.

The caller supplies its already selected compiler executable. Its digest is
checked for byte correspondence, not treated as funding or code admission.
This module neither builds/adopts that executable nor interprets its output as
an image or a physical receipt. Native retains every process/region decision.
"""
from __future__ import annotations

import math
import os
from pathlib import Path
import select
import time
from typing import Any

from actql_sdk._local_distribution import _read_file


class CompilerChildProcessError(RuntimeError):
    """Keep the same original parent/process and any partial reply.

    No stop, close, resend or replacement child is inferred from this error.
    Cleanup continues only through the retained existing Native owners.
    """

    def __init__(self, parent: Any) -> None:
        self.cleanup_parent = parent
        self.cleanup_process: Any = None
        self.response = bytearray()
        super().__init__('Original compiler child transport did not complete')


def _selected_executable(path: Path, size: int, digest: str) -> None:
    if (not path.is_absolute() or path.resolve() != path
            or type(size) is not int or size <= 0
            or type(digest) is not str or len(digest) != 64
            or any(c not in '0123456789abcdef' for c in digest)
            or not os.access(path, os.X_OK)):
        raise ValueError('Selected original compiler executable is unavailable')
    _read_file(path, maximum=size, expected=size, digest=digest)


def invoke_original_compiler(parent: Any, *, executable: Path, executable_bytes: int,
                             executable_sha256: str, module: Path, destination: Path,
                             slot: str, nonce: int, timeout: float) -> bytes:
    """One original invocation, followed by separate typed physical cleanup.

    Source-bound configuration/module/library/link verification is the existing
    compiler producer's responsibility before calling this private assembly.
    The received bytes remain untrusted compiler output. Even an empty/malformed
    report is not allowed to stand in for original stop or region retirement.
    A timeout/lost reply keeps the same carrier; it never launches another child.
    """
    from actql_sdk._local_native_domain_custody import _OriginalDomainMaterialFunctions

    if (type(timeout) not in (int, float) or not math.isfinite(timeout) or timeout <= 0
            or not module.is_absolute() or not destination.is_absolute()
            or '\0' in str(module) or '\0' in str(destination)
            or destination.exists() or destination.is_symlink()):
        raise ValueError('Original compiler invocation inputs are unavailable')
    _selected_executable(executable, executable_bytes, executable_sha256)
    parent.runtime.current()
    if parent._closed or parent.domain is None:
        raise ValueError('Original compiler parent is unavailable')
    material = parent.domain._project_original_material(
        _OriginalDomainMaterialFunctions(parent.library))
    if (material.source != parent.original.holding.source_sha
            or material.recipe != parent.original.recipe):
        raise ValueError('Original compiler material differs from its parent')
    # This is the same original DATA projection, not another reservation or a
    # reconstructed child Ledger. Native preparation still binds its live frame,
    # original channel and captured FD4 before this DATA can be used by the child.
    arguments = (material.recipe.hex(), *(str(n) for n in material.scalars),
                 str(module), str(destination))
    failure = CompilerChildProcessError(parent)
    deadline = time.monotonic() + timeout
    try:
        process = parent.prepare_process(path=slot, nonce=nonce)
        failure.cleanup_process = process
        _, endpoints = process._operate(3)
        if (endpoints is None or endpoints[0] < 0 or endpoints[1] < 0
                or endpoints[0] == endpoints[1]):
            raise ValueError('Original compiler endpoints are unavailable')
        writer, reader = endpoints[:2]
        process.prepare_child(str(executable), arguments, (('LANG', 'C'),))
        _selected_executable(executable, executable_bytes, executable_sha256)
        process.spawn()
        process.current()
        # Exactly one byte. No retry after a lost/short write: the child might
        # already have received it. This pipe is borrowed from the same Owner.
        if os.write(writer, b'R') != 1:
            raise OSError('Original compiler binding write is unconfirmed')
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([reader], [], [], remaining)[0]:
                raise TimeoutError('Original compiler response deadline elapsed')
            # A fixed control-response bound, not an image/arena/funding budget.
            part = os.read(reader, 4097 - len(failure.response))
            if not part:
                break
            failure.response.extend(part)
            if len(failure.response) > 4096:
                raise ValueError('Original compiler control response exceeds its bound')
        # EOF is only an observation. Return IPC through its original Owner,
        # then require its typed stop and actual region/FD retirement separately.
        process.restrict_transport()
        process.return_transport()
        while not process.poll_stop():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('Original compiler stop remains unconfirmed')
            time.sleep(min(0.001, remaining))
        process.retire_stopped()
        parent.close_unstarted()
        # The caller's backing descriptor and process-lifetime Runtime alias are
        # still caller-owned. Neither is closed by returning these report bytes.
        return bytes(failure.response)
    except BaseException as primary:
        if failure.cleanup_process is None:
            failure.cleanup_process = parent.domain._installed_process_original
        if failure.cleanup_process is None:
            # A known local refusal before registration created no new custody.
            raise
        raise failure from primary
