"""Atomic physical reservation driven by the existing Core start Owner.

This private Host adapter does not issue a Submission, authorize execution,
claim a physical start, or infer a Run outcome. The caller separately retains
the original Core materials and uses the physical-start Owner before I/O.
"""
from collections.abc import Callable
from dataclasses import dataclass
from enum import Enum
import json
from typing import cast

from ._local_storage import LocalByteStore, LocalStorageError, StoredBytes


def _encode(facts: dict[str, object]) -> bytes:
    # Physical flags only. The original Core-issued request stays an exact
    # string; it is not parsed, normalized or reissued by Python.
    return json.dumps(facts, ensure_ascii=False, separators=(',', ':'),
                      allow_nan=False).encode('utf-8')


class DispatchAction(Enum):
    RESERVED = 'reserved'
    RECONCILE = 'reconcile'


@dataclass(frozen=True)
class DispatchObservation:
    # The generation is physical CAS custody, not a Run/control revision.
    action: DispatchAction
    retained: StoredBytes


class LocalDispatchUnknown(LocalStorageError):
    """A lost write/competing record permits lookup, never physical execution."""


def reserve_dispatch(store: LocalByteStore, key: str, *, request: str,
                     definition_cid: str,
                     decide: Callable[[bytes], int]) -> DispatchObservation:
    """Persist only an exact Owner-approved reservation using one physical CAS.

    `decide` is the installed Host's current Core projection, never a Client
    callback. A retained record passes it again before any public observation.
    A CAS conflict or commit failure is returned as unknown without retry.
    """
    retained = store.read(key)
    payload = retained.payload if retained is not None else _encode({
        'request': request, 'definition_cid': definition_cid,
        'reserved': False, 'physically_unstarted': True,
        'cancellation_requested': False, 'pre_start_failure_confirmed': False,
    })
    # The shared Owner checks closed fields, exact request/Run and current
    # authority. Python only persists the fact returned by that Owner.
    action = decide(payload)
    if type(action) is not int or action not in (1, 2):
        raise LocalStorageError('Invalid Core dispatch decision')
    if action == 2:
        if retained is None:
            raise LocalStorageError('Missing retained dispatch reservation')
        return DispatchObservation(DispatchAction.RECONCILE, retained)
    facts = cast(dict[str, object], json.loads(payload))
    facts['reserved'] = True
    reserved = _encode(facts)
    try:
        generation = store.compare_exchange(
            key, None if retained is None else retained.generation, reserved)
    except Exception as failure:
        raise LocalDispatchUnknown('Local dispatch reservation write is unknown') from failure
    if generation is None:
        raise LocalDispatchUnknown('Local dispatch reservation changed concurrently')
    return DispatchObservation(DispatchAction.RESERVED, StoredBytes(generation, reserved))
