"""Private original Run/physical-start loans, not a Run state machine.

Opaque inputs are supplied by the installed Host. Only the existing Core
Owners decide compilation, dispatch and physical start. No method admits a
Submission, persists an acceptance, invokes Compute, or cancels a Run.
"""
from dataclasses import dataclass
from typing import Literal

from ._local_core import LocalCore, LocalCoreError, _Input, _Compute
from ._local_preparation import LocalPreparation, _Preparation


@dataclass(frozen=True, slots=True, eq=False)
class _RunConfiguration:
    owner: object
    handle: int
    input: _Input


@dataclass(frozen=True, slots=True, eq=False)
class _Run:
    owner: object
    handle: int
    configuration: _RunConfiguration
    preparation: _Preparation
    input: _Input


@dataclass(frozen=True, slots=True, eq=False)
class _PhysicalStart:
    owner: object
    handle: int
    run: _Run
    current: _RunConfiguration
    input: _Input


@dataclass(frozen=True, slots=True, eq=False)
class _SourceFreeCompute:
    owner: object
    core: _Compute
    start: _PhysicalStart
    input: _Input


class LocalRunCustody:
    """Keep exact Core parents and loans reachable across refusal or interruption.

    This bridge neither interprets authored Program bytes nor constructs
    account grants, request identities, physical journal facts, or outcomes.
    Readiness is private Owner evidence, never public Run acceptance.
    """

    def __init__(self, core: LocalCore, preparation: LocalPreparation) -> None:
        if type(core) is not LocalCore or type(preparation) is not LocalPreparation:
            raise ValueError('Local Run custody requires the original Core preparation')
        preparation._nominal()
        if preparation._core is not core:
            raise ValueError('Foreign Local preparation Core')
        self._original = self
        self._core = core
        self._preparation = preparation
        self._identity = object()
        self._configurations: dict[int, _RunConfiguration] = {}
        self._runs: dict[int, _Run] = {}
        self._starts: dict[int, _PhysicalStart] = {}
        self._computes: dict[int, _SourceFreeCompute] = {}
        self._compute_currents: dict[int, _RunConfiguration] = {}

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied Local Run custody bridge')
        self._preparation._nominal()

    def _active(self) -> None:
        self._nominal()
        if self._core._closing:
            raise RuntimeError('Local Core is closing')

    def _configuration(self, value: _RunConfiguration) -> None:
        self._nominal()
        if (type(value) is not _RunConfiguration or value.owner is not self._identity
                or self._configurations.get(value.handle) is not value):
            raise ValueError('Foreign or released Local Run configuration')

    def _run(self, value: _Run) -> None:
        self._nominal()
        if (type(value) is not _Run or value.owner is not self._identity
                or self._runs.get(value.handle) is not value):
            raise ValueError('Foreign or released Local Run loan')
        self._configuration(value.configuration)
        self._preparation._preparation(value.preparation)

    def _start(self, value: _PhysicalStart) -> None:
        self._nominal()
        if (type(value) is not _PhysicalStart or value.owner is not self._identity
                or self._starts.get(value.handle) is not value):
            raise ValueError('Foreign or released Local physical-start loan')
        self._run(value.run)
        self._configuration(value.current)

    def install_configuration(self, input: _Input) -> _RunConfiguration:
        """Ask the existing Account Owner to admit installed Host configuration."""
        with self._core._lock:
            self._active()
            self._core._owned_input(input)
            handle = self._core._call('run', 'install_configuration', input.handle)
            if handle <= 0:
                raise LocalCoreError('install_configuration', handle)
            value = _RunConfiguration(self._identity, handle, input)
            self._configurations[handle] = value
            return value

    def reserve(self, configuration: _RunConfiguration, preparation: _Preparation,
                input: _Input) -> _Run:
        """Retain invocation custody before compilation; this is not admission."""
        with self._core._lock:
            self._active()
            self._configuration(configuration)
            self._preparation._preparation(preparation)
            self._core._owned_input(input)
            handle = self._core._call('run', 'reserve', configuration.handle,
                                      preparation.handle, input.handle)
            if handle <= 0:
                raise LocalCoreError('reserve', handle)
            value = _Run(self._identity, handle, configuration, preparation, input)
            self._runs[handle] = value
            return value

    def prepare(self, value: _Run) -> None:
        """Preserve original rejection/unknown; never turn readiness into execution."""
        with self._core._lock:
            self._active()
            self._run(value)
            self._core._check('prepare', self._core._call('run', 'prepare', value.handle))
            self._core._check('prepared', self._core._call('run', 'prepared', value.handle))

    def dispatch_action(self, value: _Run, current: _RunConfiguration,
                        input: _Input) -> Literal[1, 2]:
        """Project the original Owner action; no physical CAS or I/O occurs here."""
        with self._core._lock:
            self._active()
            self._run(value)
            self._configuration(current)
            self._core._owned_input(input)
            action = self._core._call('run', 'dispatch_action', value.handle,
                                      current.handle, input.handle)
            if action == 1:
                return 1
            if action == 2:
                return 2
            raise LocalCoreError('dispatch_action', action)

    def reserve_physical_start(self, value: _Run, current: _RunConfiguration,
                               input: _Input) -> _PhysicalStart:
        """Retain the exact Host journal-fact loan before start Owner evaluation."""
        with self._core._lock:
            self._active()
            self._run(value)
            self._configuration(current)
            self._core._owned_input(input)
            handle = self._core._call('run', 'reserve_physical_start', value.handle,
                                      current.handle, input.handle)
            if handle <= 0:
                raise LocalCoreError('reserve_physical_start', handle)
            start = _PhysicalStart(self._identity, handle, value, current, input)
            self._starts[handle] = start
            return start

    def confirm_physical_start(self, value: _PhysicalStart) -> None:
        """Use the original start Owner, independently of durable reservation.

        Confirmation does not perform physical work or advertise a public
        admission. An interrupted or unknown decision retains the same loan.
        """
        with self._core._lock:
            self._active()
            self._start(value)
            self._core._check('confirm_physical_start', self._core._call(
                'run', 'confirm_physical_start', value.handle))
            self._core._check('physical_start_ready', self._core._call(
                'run', 'physical_start_ready', value.handle))

    def close_physical_start(self, value: _PhysicalStart) -> bool:
        with self._core._lock:
            self._start(value)
            code = self._core._call('run', 'close_physical_start', value.handle)
            if code == -9:
                return False
            self._core._check('close_physical_start', code)
            del self._starts[value.handle]
            return True

    def close_run(self, value: _Run) -> bool:
        with self._core._lock:
            self._run(value)
            code = self._core._call('run', 'close', value.handle)
            if code == -9:
                return False
            self._core._check('close', code)
            del self._runs[value.handle]
            return True

    def close_configuration(self, value: _RunConfiguration) -> bool:
        with self._core._lock:
            self._configuration(value)
            code = self._core._call('run', 'close_configuration', value.handle)
            if code == -9:
                return False
            self._core._check('close_configuration', code)
            del self._configurations[value.handle]
            return True


    def reserve_source_free_compute(self, start: _PhysicalStart,
                                    input: _Input) -> _SourceFreeCompute:
        """Borrow the original start/Run and config input; Core checks readiness.

        This creates no Source, activation grant, publication policy or durable
        admission. An unknown invocation keeps its same handle and parents.
        """
        with self._core._lock:
            self._active()
            self._start(start)
            self._core._owned_input(input)
            handle = self._core._call('compute', 'reserve_source_free',
                                      start.run.handle, start.handle, input.handle)
            if handle <= 0:
                raise LocalCoreError('reserve_source_free_compute', handle)
            core = _Compute(self._core._identity, handle)
            self._core._compute_loans[handle] = core
            value = _SourceFreeCompute(self._identity, core, start, input)
            self._computes[handle] = value
            return value

    def _compute(self, value: _SourceFreeCompute) -> None:
        self._nominal()
        if (type(value) is not _SourceFreeCompute or value.owner is not self._identity
                or self._computes.get(value.core.handle) is not value):
            raise ValueError('Foreign or released source-free Compute loan')
        self._start(value.start)
        self._core._owned_compute(value.core)

    def configure_source_free_compute(self, value: _SourceFreeCompute,
                                      current: _RunConfiguration) -> None:
        """Configure original task resources; no task execution or Result issuance."""
        with self._core._lock:
            self._active()
            self._compute(value)
            self._configuration(current)
            # Retain the first current configuration before Core can trap.
            # Core refuses a different configuration after invocation begins.
            self._compute_currents.setdefault(value.core.handle, current)
            self._core._check('configure_source_free_compute', self._core._call(
                'compute', 'configure_source_free', value.core.handle, current.handle))
            self._core._check('source_free_compute_configured', self._core._call(
                'compute', 'configured', value.core.handle))

    def close_source_free_compute(self, value: _SourceFreeCompute) -> bool:
        with self._core._lock:
            self._compute(value)
            if not self._core.close_native_compute(value.core):
                return False
            del self._computes[value.core.handle]
            self._compute_currents.pop(value.core.handle, None)
            return True
