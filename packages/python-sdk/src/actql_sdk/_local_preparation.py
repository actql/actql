"""Private custody for the existing Core input-preparation ABI.

These references keep original buffer loans reachable. They are not Client
references, admission records, execution permits, or a second Checker.
"""
from dataclasses import dataclass
from typing import Literal

from ._local_core import LocalCore, LocalCoreError, _Input


@dataclass(frozen=True, slots=True, eq=False)
class _Environment:
    owner: object
    handle: int
    input: _Input


@dataclass(frozen=True, slots=True, eq=False)
class _Preparation:
    owner: object
    handle: int
    environment: _Environment
    input: _Input


@dataclass(frozen=True, slots=True)
class PreparedShape:
    """Original checked-plan counts, never Run admission or publication."""

    results: int
    tasks: int


class LocalPreparation:
    """Use one installed Core and its exact, already-accounted input loans.

    Host configuration chooses the environment; submitted Programs cannot
    supply an environment, Source authorization, or a publication grant.
    Every semantic decision remains in the existing Core preparation Owner.
    """

    def __init__(self, core: LocalCore) -> None:
        if type(core) is not LocalCore:
            raise ValueError('Local preparation requires the original Core')
        self._core = core
        self._identity = object()
        self._environments: dict[int, _Environment] = {}
        self._preparations: dict[int, _Preparation] = {}

    def _active(self) -> None:
        if self._core._closing:
            raise RuntimeError('Local Core is closing')

    def _environment(self, value: _Environment) -> None:
        if (type(value) is not _Environment or value.owner is not self._identity
                or self._environments.get(value.handle) is not value):
            raise ValueError('Foreign or released Local environment')

    def _preparation(self, value: _Preparation) -> None:
        if (type(value) is not _Preparation or value.owner is not self._identity
                or self._preparations.get(value.handle) is not value):
            raise ValueError('Foreign or released Local preparation')
        self._environment(value.environment)

    def install_environment(self, input: _Input, *,
                            profile: Literal['source-free', 'published']) -> _Environment:
        """Retain original Host configuration after the Core admits its wire.

        The published profile expects the existing publication envelope. This
        adapter neither builds Catalog facts nor infers an empty namespace.
        """
        with self._core._lock:
            self._active()
            self._core._owned_input(input)
            if profile not in ('source-free', 'published'):
                raise ValueError('Invalid Local environment profile')
            operation = ('install_environment' if profile == 'source-free'
                         else 'install_source_environment')
            handle = self._core._call('program', operation, input.handle)
            if handle <= 0:
                raise LocalCoreError(operation, handle)
            value = _Environment(self._identity, handle, input)
            self._environments[handle] = value
            return value

    def reserve(self, environment: _Environment, input: _Input, *,
                format: Literal['program', 'text']) -> _Preparation:
        """Issue custody before entering the existing parser/lowerer/Checker.

        Program wire and JSON-string text wire remain opaque original bytes.
        No normalization, placeholder binding or semantic parsing occurs here.
        """
        with self._core._lock:
            self._active()
            self._environment(environment)
            self._core._owned_input(input)
            if format not in ('program', 'text'):
                raise ValueError('Invalid Local input format')
            kind = 1 if format == 'program' else 2
            handle = self._core._call('program', 'reserve_preparation',
                                      environment.handle, input.handle, kind)
            if handle <= 0:
                raise LocalCoreError('reserve_preparation', handle)
            value = _Preparation(self._identity, handle, environment, input)
            self._preparations[handle] = value
            return value

    def prepare(self, value: _Preparation) -> PreparedShape:
        """Ask the original Owner; failure/trap retains the issued handle.

        Negative counts remain typed ABI failures, including incomplete or
        rejected preparation. They are not a public invalid classification.
        """
        with self._core._lock:
            self._active()
            self._preparation(value)
            self._core._check('prepare', self._core._call('program', 'prepare', value.handle))
            results = self._core._call('program', 'prepared_results', value.handle)
            if results < 0:
                raise LocalCoreError('prepared_results', results)
            tasks = self._core._call('program', 'prepared_tasks', value.handle)
            if tasks < 0:
                raise LocalCoreError('prepared_tasks', tasks)
            return PreparedShape(results, tasks)

    def close_preparation(self, value: _Preparation) -> bool:
        """Return the same original borrow only when its Core Owner succeeds."""
        with self._core._lock:
            self._preparation(value)
            code = self._core._call('program', 'close_preparation', value.handle)
            if code == -9:
                return False
            self._core._check('close_preparation', code)
            del self._preparations[value.handle]
            return True

    def close_environment(self, value: _Environment) -> bool:
        with self._core._lock:
            self._environment(value)
            code = self._core._call('program', 'close_environment', value.handle)
            if code == -9:
                return False
            self._core._check('close_environment', code)
            del self._environments[value.handle]
            return True
