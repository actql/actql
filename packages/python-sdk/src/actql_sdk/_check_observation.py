"""Attribute views of admitted checks; the existing diagnostics own input custody.

Responsibility: expose the public report/reason attributes without another checker.
Inputs: only the original generated check-outcome admission selects a variant.
Identity: mapping/to_dict retain exact wire absence; dataclass copies are data.
Ownership: no view issues an input binding, Run, permission or original-call key.
Synchronization: construction is local and performs no callbacks or I/O.
Failure: completed, partial failure and unavailable remain separate outcomes.
Cancellation: projection neither starts nor cancels work or acknowledges cleanup.
Resources: the already bounded immutable response backs nested views.
Extension: new wire variants must first pass the same generated codec.
Verification: public facade, detached-copy and original-location tests.
"""
from __future__ import annotations

from collections.abc import Iterator, Mapping
from dataclasses import dataclass, fields
from typing import Any, Literal, Self, cast

from ._errors import ClientError
from ._run_state import _field_value
from ._values import Observation, freeze, snapshot, thaw
from ._wire_codec import check_outcome


class _CheckFields(Mapping[str, Any]):
    """Borrow an already immutable observation; never register original custody."""
    __slots__ = ('_source',)
    _source: Mapping[str, Any]
    __hash__ = object.__hash__
    __eq__ = object.__eq__

    def __setattr__(self, name: str, value: object) -> None:
        raise AttributeError('ImmutableCheckObservation')

    def __getitem__(self, key: str) -> Any:
        return self._source[key]

    def __iter__(self) -> Iterator[str]:
        return iter(self._source)

    def __len__(self) -> int:
        return len(self._source)

    def to_dict(self) -> dict[str, Any]:
        return thaw(self._source)  # type: ignore[no-untyped-call,no-any-return]

    @classmethod
    def _from_snapshot(cls, source: Mapping[str, Any]) -> Self:
        view = object.__new__(cls)
        object.__setattr__(view, '_source', source)
        for field in fields(cast(Any, cls)):
            value = source.get(field.name)
            projected = (tuple(CheckReason._from_snapshot(item) for item in source[field.name])
                         if isinstance(view, CheckReport) and field.name in ('reasons', 'requirements')
                         else _field_value(value))
            object.__setattr__(view, field.name, projected)
        return view

    def __copy__(self) -> Self:
        return type(self)._from_snapshot(self._source)

    def __deepcopy__(self, memo: dict[int, Any]) -> Self:
        return type(self)._from_snapshot(freeze(snapshot(self.to_dict())))  # type: ignore[no-untyped-call]


@dataclass(frozen=True, slots=True, eq=False, init=False)
class CheckReason(_CheckFields):
    """One admitted reason or requirement; optional attributes add no wire fields."""
    code: str
    facts: Mapping[str, Any] | None
    location: Mapping[str, Any] | None
    fixes: tuple[Mapping[str, Any], ...] | None


@dataclass(frozen=True, slots=True, eq=False, init=False)
class CheckReport(_CheckFields):
    """Immutable report data; verdict and runnable are the Host's observations."""
    context_ref: str
    scope: Mapping[str, Any]
    verdict: Literal['invalid', 'undetermined', 'verified']
    runnable: Mapping[str, Any]
    inputs: tuple[Mapping[str, Any], ...]
    reasons: tuple[CheckReason, ...]
    requirements: tuple[CheckReason, ...]
    coverage: Mapping[str, Any]
    omissions: Mapping[str, Any] | None


@dataclass(frozen=True, slots=True, eq=False, init=False)
class CheckObservation(Observation):
    """An admitted check snapshot; only bind_check attaches original inputs.

    Attribute views and dataclasses.asdict may include None for absent optional
    attributes. Mapping access and to_dict preserve the exact original wire.
    Copies/reconstruction never copy the diagnostics Owner's WeakMap entry.
    """
    version: Literal['actql-check-outcome/0.1']
    outcome: Literal['completed', 'failed', 'unavailable']
    reason_schema_cid: str
    outcome_schema_cid: str
    report: CheckReport | None
    partial_report: CheckReport | None
    problem: Mapping[str, Any] | None
    correlation_ref: str | None

    def __init__(self, value: dict[str, Any]) -> None:
        if hasattr(self, '_Observation__data'):
            raise AttributeError('ImmutableCheckObservation')
        if not check_outcome(value):  # type: ignore[no-untyped-call]
            raise ClientError('InvalidHostCheckOutcome')
        Observation.__init__(self, value)  # type: ignore[no-untyped-call]
        for field in fields(self):
            source = self.get(field.name)
            projected = (CheckReport._from_snapshot(source)
                         if field.name in ('report', 'partial_report') and source is not None
                         else _field_value(source))
            object.__setattr__(self, field.name, projected)

    def __copy__(self) -> CheckObservation:
        return type(self)(self.to_dict())  # type: ignore[no-untyped-call]

    def __deepcopy__(self, memo: dict[int, Any]) -> CheckObservation:
        return self.__copy__()
