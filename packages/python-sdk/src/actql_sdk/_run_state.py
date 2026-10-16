"""Immutable public Run observation values; the generated wire owns admission.

Responsibility: project admitted Host data, without an execution controller.
Inputs and outputs: exact generated Run-state fields become immutable attributes.
Identity: state revision and cancellation-control revision remain independent.
Ownership: snapshots and detached dataclass copies carry no original permission.
Synchronization: projection performs no I/O, waiting, polling or revision update.
Failure: missing or malformed fields fail the existing generated wire admission.
Cancellation: observing or copying state neither cancels nor acknowledges stop.
Resources: the existing transport and reader limits remain authoritative.
Extension: new fields must first be admitted by the current wire contract.
Verification: independent facade and immutable-copy cases cover this projection.
"""
from __future__ import annotations

from collections.abc import Iterator, Mapping
from dataclasses import dataclass, fields
from typing import Any, Literal

from ._wire_codec import valid
from ._errors import ClientError
from ._values import Observation, snapshot, thaw


class _StateMapping(Mapping[str, Any]):
    """Read-only nested data with an ordinary dataclasses.asdict projection.

    Its source is the observation's already immutable snapshot. Deep copying
    produces detached data, without original-call custody or Owner authority.
    """
    __slots__ = ('_source',)
    _source: Mapping[str, Any]

    def __init__(self, source: Mapping[str, Any]) -> None:
        object.__setattr__(self, '_source', source)

    def __setattr__(self, name: str, value: object) -> None:
        raise AttributeError('ImmutableRunState')

    def __getitem__(self, key: str) -> Any:
        return _field_value(self._source[key])

    def __iter__(self) -> Iterator[str]:
        return iter(self._source)

    def __len__(self) -> int:
        return len(self._source)

    def __deepcopy__(self, memo: dict[int, Any]) -> dict[str, Any]:
        return thaw(self._source)  # type: ignore[no-untyped-call,no-any-return]


def _field_value(value: Any) -> Any:
    if isinstance(value, Mapping):
        return _StateMapping(value)
    if isinstance(value, tuple):
        return tuple(_field_value(item) for item in value)
    return value


@dataclass(frozen=True, slots=True, eq=False, init=False)
class RunState(Observation):
    """One admitted Host state, not a local execution or revision controller.

    Attribute access is the public dataclass interface. Mapping access and
    to_dict preserve the original wire's absent fields. asdict returns detached
    data with None for absent optional dataclass fields, never a new wire reply.
    State revision is independent of the cancellation-control revision.
    """
    version: Literal['actql-run-state/0.1']
    run_id: str
    status: Literal['preparing', 'running', 'waiting_checkpoint', 'resuming',
                    'needs_reconciliation', 'succeeded', 'failed', 'cancelled']
    revision: int
    updated_at: str
    next_action: Mapping[str, Any]
    result_available: bool
    result_availability: Mapping[str, Any]
    checkpoint: Mapping[str, Any] | None
    terminal_error: Mapping[str, Any] | None
    control: Mapping[str, Any] | None

    def __init__(self, value: dict[str, Any]) -> None:
        captured = snapshot(value)  # type: ignore[no-untyped-call]
        if not valid(captured, 'run_state'):  # type: ignore[no-untyped-call]
            raise ClientError('InvalidHostRunState')
        Observation.__init__(self, captured)  # type: ignore[no-untyped-call]
        for field in fields(self):
            object.__setattr__(self, field.name, _field_value(self.get(field.name)))
