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


class LocalPreparationFailure(RuntimeError):
    """The same preparation Owner retained a known failure, not a transport error.

    This object supplies neither a public phase nor a durable receipt. The
    Host must commit and independently read its original terminal outcome.
    """
    def __init__(self, owner: object, preparation: _Preparation) -> None:
        super().__init__('Original Local preparation failed')
        self._owner = owner
        self.preparation = preparation


class LocalPreparation:
    """Use one installed Core and its exact, already-accounted input loans.

    Host configuration chooses the environment; submitted Programs cannot
    supply an environment, Source authorization, or a publication grant.
    Every semantic decision remains in the existing Core preparation Owner.
    """

    def __init__(self, core: LocalCore) -> None:
        if type(core) is not LocalCore:
            raise ValueError('Local preparation requires the original Core')
        self._original = self
        self._core = core
        self._identity = object()
        self._environments: dict[int, _Environment] = {}
        self._preparations: dict[int, _Preparation] = {}
        self._failures: dict[int, LocalPreparationFailure] = {}

    def _active(self) -> None:
        self._nominal()
        if self._core._closing:
            raise RuntimeError('Local Core is closing')

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied Local preparation bridge')

    def _environment(self, value: _Environment) -> None:
        self._nominal()
        if (type(value) is not _Environment or value.owner is not self._identity
                or self._environments.get(value.handle) is not value):
            raise ValueError('Foreign or released Local environment')

    def _preparation(self, value: _Preparation) -> None:
        self._nominal()
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
                format: Literal['program', 'text', 'submitted']) -> _Preparation:
        """Issue custody before entering the existing parser/lowerer/Checker.

        Program wire and JSON-string text wire remain opaque original bytes.
        No normalization, placeholder binding or semantic parsing occurs here.
        """
        with self._core._lock:
            self._active()
            self._environment(environment)
            self._core._owned_input(input)
            if format not in ('program', 'text', 'submitted'):
                raise ValueError('Invalid Local input format')
            kind = {'program': 1, 'text': 2, 'submitted': 3}[format]
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
            if value.handle in self._failures:
                raise RuntimeError('Original Local preparation already failed; retain its outcome')
            self._core._check('prepare', self._core._call('program', 'prepare', value.handle))
            outcome = self._core._call('program', 'prepared_outcome', value.handle)
            if type(outcome) is not int or outcome not in (0, 1, 2):
                raise RuntimeError('Invalid original Local preparation outcome')
            if outcome == 2:
                failure = LocalPreparationFailure(self._identity, value)
                self._failures[value.handle] = failure
                raise failure
            if outcome != 1:
                raise LocalCoreError('prepared_outcome', outcome)
            results = self._core._call('program', 'prepared_results', value.handle)
            if results < 0:
                raise LocalCoreError('prepared_results', results)
            tasks = self._core._call('program', 'prepared_tasks', value.handle)
            if tasks < 0:
                raise LocalCoreError('prepared_tasks', tasks)
            return PreparedShape(results, tasks)

    def failed_original(self, failure: LocalPreparationFailure) -> _Preparation:
        """Borrow the same issued failure DATA without preparing or granting work."""
        with self._core._lock:
            self._nominal()
            if (type(failure) is not LocalPreparationFailure or failure._owner is not self._identity
                    or self._failures.get(failure.preparation.handle) is not failure):
                raise ValueError('Foreign or retired original Local preparation failure')
            self._preparation(failure.preparation)
            return failure.preparation

    def close_preparation(self, value: _Preparation) -> bool:
        """Return the same original borrow only when its Core Owner succeeds."""
        with self._core._lock:
            self._preparation(value)
            code = self._core._call('program', 'close_preparation', value.handle)
            if code == -9:
                return False
            self._core._check('close_preparation', code)
            del self._preparations[value.handle]
            self._failures.pop(value.handle, None)
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
