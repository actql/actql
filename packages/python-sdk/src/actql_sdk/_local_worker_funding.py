"""Original process funding ports; no Python quota, Run or cleanup decisions.

The trusted installed supplier binds these ports to the existing Common Ledger,
physical allocator and durable original custody. No production supplier or
numerical profile is adopted here. Missing inputs refuse before physical start.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from ._local_core import LocalCoreResources
    from ._local_distribution import LocalComponents


class LocalWorkerFundingUnavailable(RuntimeError):
    """No complete original funding; spawn/DLL/Config/Engine must not start."""

    def __init__(self, message: str, *, cleanup_preparation: object | None = None) -> None:
        self.cleanup_preparation = cleanup_preparation
        super().__init__(message)


class LocalWorkerFundingPending(RuntimeError):
    """Keep this original carrier; uncertainty does not permit a new reserve."""

    def __init__(self, funding: OriginalWorkerFunding) -> None:
        self.cleanup_funding = funding
        super().__init__('Original Local worker funding is unconfirmed')


class _WorkerFundingSupplier(ABC):
    """Installed-only binding, never a Client option or a serialized pointer.

    Common methods have their original Ledger/delegation signatures. Physical
    and durable ports must retain unknown originals internally on exceptions.
    A declaration, PID, boolean or recipe digest cannot implement these facts.
    """

    def __init__(self) -> None:
        self._original_supplier = self
        self._consumer: OriginalWorkerFunding | None = None

    def __copy__(self) -> _WorkerFundingSupplier:
        raise TypeError('Original worker funding supplier cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _WorkerFundingSupplier:
        raise TypeError('Original worker funding supplier cannot be copied')

    def _bind_original(self, consumer: OriginalWorkerFunding) -> None:
        if self._original_supplier is not self or self._consumer is not None:
            raise ValueError('Original worker funding supplier was already consumed')
        # A supplier instance owns one original provisioning claim. Binding
        # before acquire also keeps an exceptional acquire scoped to this same
        # carrier rather than an anonymous or replaceable cleanup target.
        self._consumer = consumer

    @abstractmethod
    def acquire_pre_spawn(self, components: LocalComponents) -> object:
        """Acquire actual original parent/bootstrap/child-domain funding."""

    @abstractmethod
    def original_ledger(self, physical: object) -> object:
        """Return the already funded original Common Ledger, not create one."""

    @abstractmethod
    def reserve_execution_delegation(self, ledger: object, limits: LocalCoreResources,
                                     retained: int, execution: int) -> object:
        """Invoke Common reserve_execution_delegation on that original Ledger."""

    @abstractmethod
    def preserve_original_delegation(self, physical: object, ledger: object,
                                    delegation: object) -> object:
        """Persist Owner-issued original custody before launch; no pointer wire."""

    @abstractmethod
    def require_launch_originals(self, physical: object, ledger: object,
                                delegation: object, durable: object) -> object:
        """Revalidate selected physical/current/durable scope before launch."""

    @abstractmethod
    def report_execution_delegation(self, ledger: object, delegation: object,
                                   usage: Any) -> object:
        """Invoke Common cumulative bounded report; no Python counter."""

    @abstractmethod
    def require_scoped_stop(self, physical: object, ledger: object,
                            delegation: object, durable: object, observation: object) -> object:
        """Adopt original process-domain stop through existing Owner/ports.

        This is not Provider, COMMIT, FD-close, Run-cancel or borrowed-Store ACK.
        """

    @abstractmethod
    def settle_execution_delegation(self, ledger: object, delegation: object,
                                   final_usage: Any | None) -> object:
        """Invoke Common settle; None consumes the unreported quota there."""

    @abstractmethod
    def close_original_funding(self, physical: object, ledger: object | None,
                               delegation: object | None, durable: object | None) -> object:
        """Existing Owner closes/reconciles pending custody, without reserve.

        Success is returned only after scoped physical retirement/settlement.
        Unknown retains the same carrier and one-shot descriptor responsibility.
        """


class OriginalWorkerFunding:
    """One original physical carrier, not a process/Run recovery controller."""

    def __init__(self, components: LocalComponents, supplier: _WorkerFundingSupplier | None,
                 *, limits: LocalCoreResources | None, retained: int | None,
                 execution: int | None) -> None:
        # The unavailable-error port is part of the small initial prelude.
        # Load the actual concrete resource types only at this funded caller.
        from ._local_core import LocalCoreResources
        from ._local_distribution import LocalComponents
        # Numbers and declarations never replace an actual installed supplier.
        if (type(components) is not LocalComponents or not isinstance(supplier, _WorkerFundingSupplier)
                or type(limits) is not LocalCoreResources or not limits.valid()
                or type(retained) is not int or not 0 <= retained <= 2**63 - 1
                or type(execution) is not int or not 0 < execution <= 2**63 - 1):
            raise LocalWorkerFundingUnavailable('Original Local worker funding supplier is unavailable')
        self._original = self
        self._supplier = supplier
        self._physical: object | None = None
        self._ledger: object | None = None
        self._delegation: object | None = None
        self._durable: object | None = None
        self._closed = False
        self._closing = False
        self._close_inflight = False
        self._driver_consumer: object | None = None
        supplier._bind_original(self)
        try:
            self._physical = supplier.acquire_pre_spawn(components)
            if not self._opaque(self._physical):
                raise LocalWorkerFundingUnavailable('Original Local worker physical funding is unavailable')
            self._ledger = supplier.original_ledger(self._physical)
            if not self._opaque(self._ledger):
                raise LocalWorkerFundingUnavailable('Original Local worker Ledger is unavailable')
            self._delegation = supplier.reserve_execution_delegation(self._ledger, limits, retained, execution)
            if not self._opaque(self._delegation):
                raise LocalWorkerFundingUnavailable('Original Local worker delegation is unavailable')
            self._durable = supplier.preserve_original_delegation(self._physical, self._ledger, self._delegation)
            if not self._opaque(self._durable):
                raise LocalWorkerFundingUnavailable('Original Local worker durable custody is unavailable')
        except BaseException as failure:
            # The supplier retains pending acquire/reserve/COMMIT facts even
            # when a return was lost. Never acquire or reserve again here.
            raise LocalWorkerFundingPending(self) from failure

    def __copy__(self) -> OriginalWorkerFunding:
        raise TypeError('Original Local worker funding cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> OriginalWorkerFunding:
        raise TypeError('Original Local worker funding cannot be copied')

    @staticmethod
    def _opaque(value: object) -> bool:
        # Encoded fields and numeric handles are not original nominal custody.
        return value is not None and type(value) not in (bool, int, float, str, bytes,
                                                        list, tuple, dict)

    @staticmethod
    def _ack(value: object) -> None:
        if value is not None:
            raise RuntimeError('Unconfirmed original worker Owner operation')

    def _nominal(self) -> None:
        if self._original is not self or self._closed or self._close_inflight:
            raise ValueError('Foreign or retired original Local worker funding')

    def _bind_driver(self, consumer: object) -> None:
        self._nominal()
        if self._closing or self._driver_consumer is not None:
            raise ValueError('Original Local worker funding already has a driver')
        self._driver_consumer = consumer

    def require_launch(self) -> None:
        self._nominal()
        if self._closing:
            raise LocalWorkerFundingUnavailable('Original Local worker funding is closing')
        if any(value is None for value in (self._physical, self._ledger, self._delegation, self._durable)):
            raise LocalWorkerFundingUnavailable('Original Local worker funding is incomplete')
        self._ack(self._supplier.require_launch_originals(
            self._physical, self._ledger, self._delegation, self._durable))
        self._nominal()
        if self._closing:
            raise LocalWorkerFundingUnavailable('Original Local worker funding is closing')

    def report(self, usage: Any) -> None:
        self.require_launch()
        self._ack(self._supplier.report_execution_delegation(self._ledger, self._delegation, usage))
        self._nominal()

    def settle_stopped(self, observation: object, *, final_usage: Any | None) -> None:
        self._nominal()
        if any(value is None for value in (self._physical, self._ledger, self._delegation, self._durable)):
            raise LocalWorkerFundingUnavailable('Original Local worker funding is incomplete')
        if not self._opaque(observation):
            raise ValueError('Original scoped worker stop observation is unavailable')
        self._ack(self._supplier.require_scoped_stop(self._physical, self._ledger, self._delegation,
                                                     self._durable, observation))
        self._nominal()
        self._ack(self._supplier.settle_execution_delegation(self._ledger, self._delegation, final_usage))
        self._nominal()

    def close(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign original Local worker funding')
        if self._closed:
            return
        if self._close_inflight:
            raise RuntimeError('Original Local worker funding close cannot reenter')
        self._closing = True
        self._close_inflight = True
        # This is one pass through the existing Owner, not a retry queue. A
        # failed close retains all refs; it does not repeat acquire/reserve.
        try:
            self._ack(self._supplier.close_original_funding(
                self._physical, self._ledger, self._delegation, self._durable))
            self._closed = True
        finally:
            self._close_inflight = False
