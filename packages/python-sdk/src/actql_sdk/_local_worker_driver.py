"""Bounded existing Client/Wire transport for one originally funded worker.

No process implementation, Engine, Run state machine or public supplier is
created here. The installed channel retains physical requests/responses and
their unknown/cleanup custody independently of the awaiting SDK coroutine.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable
import httpx

from . import _wire as wire
from ._local_installation import _object
from ._local_worker_funding import OriginalWorkerFunding, LocalWorkerFundingUnavailable

_LOCAL_SELECTION = {'mode': 'local', 'owner': 'local', 'durability': 'durable',
                    'consentRefs': [], 'runners': []}
_MAX_OPERATION_BYTES = 1048576  # Same operation bound as InstalledLocalHost.open.


class LocalWorkerDriverPending(RuntimeError):
    """Original worker/channel/funding remain owned; never a resend permit."""

    def __init__(self, driver: OriginalWorkerDriver) -> None:
        self.cleanup_driver = driver
        super().__init__('Original Local worker transport is unconfirmed')


class _OriginalWorkerChannel(ABC):
    """Unstarted installed physical carrier, tied to one original funding.

    Construction must not acquire descriptors, spawn or load a DLL/Engine.
    Startup registers the actual
    child/slot/channel before awaiting. Exchange registers physical response
    custody before returning; failed/lost replies stay with its original Host.
    None startup/close returns represent only scoped Owner-accepted physical
    operations, never Run/Provider/COMMIT/FD-close conclusions inferred from exit.
    """

    def __init__(self, funding: OriginalWorkerFunding) -> None:
        self._original_channel = self
        self._funding = funding
        self._driver: OriginalWorkerDriver | None = None

    def _bind_driver(self, funding: OriginalWorkerFunding, driver: OriginalWorkerDriver) -> None:
        if self._original_channel is not self or self._funding is not funding or self._driver is not None:
            raise ValueError('Foreign or already consumed original worker channel')
        self._driver = driver

    def __copy__(self) -> _OriginalWorkerChannel:
        raise TypeError('Original Local worker channel cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _OriginalWorkerChannel:
        raise TypeError('Original Local worker channel cannot be copied')

    @abstractmethod
    async def start_original(self) -> object:
        """Start once under the already reserved original process/lease scope."""

    @abstractmethod
    def require_current_original(self) -> object:
        """Require the same live process/lease/Host current binding; no PID Bool."""

    @abstractmethod
    async def exchange_original(self, operation: str, payload: bytes) -> httpx.Response:
        """One exact existing Wire exchange, no restart/retry/response synthesis.

        Bounded framing/stream loans and response correlation belong to the
        physical channel; the existing SDK validates public response semantics.
        """

    @abstractmethod
    async def close_original(self) -> object:
        """Ask the existing Host to close, retaining unknown physical custody."""


class OriginalWorkerDriver:
    """Same Local Host transport shape used by sync and async SDK facades."""

    def __init__(self, funding: OriginalWorkerFunding | None,
                 channel_factory: Callable[[OriginalWorkerFunding], _OriginalWorkerChannel]) -> None:
        if type(funding) is not OriginalWorkerFunding:
            raise LocalWorkerFundingUnavailable('Original Local worker funding is unavailable')
        funding.require_launch()
        if not callable(channel_factory):
            raise ValueError('Original worker channel supplier is unavailable')
        self._original = self
        self._funding = funding
        self._channel: _OriginalWorkerChannel | None = None
        self._launch_attempted = False
        self._ready = False
        self._closing = False
        self._close_inflight = False
        self._closed = False
        self._channel_close_confirmed = False
        funding._bind_driver(self)
        try:
            channel = channel_factory(funding)
            if not isinstance(channel, _OriginalWorkerChannel):
                raise ValueError('Invalid original worker channel')
            channel._bind_driver(funding, self)
            self._channel = channel
            self._nominal()
        except BaseException as failure:
            raise LocalWorkerDriverPending(self) from failure

    def __copy__(self) -> OriginalWorkerDriver:
        raise TypeError('Original Local worker driver cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> OriginalWorkerDriver:
        raise TypeError('Original Local worker driver cannot be copied')

    def _nominal(self) -> None:
        if self._original is not self or self._closed or self._closing:
            raise ValueError('Foreign or closing original Local worker driver')
        self._funding._nominal()
        if (self._funding._closing or self._funding._driver_consumer is not self
                or self._channel is None or self._channel._driver is not self):
            raise ValueError('Original Local worker funding or channel is unavailable')

    async def start(self) -> None:
        self._nominal()
        if self._launch_attempted:
            raise RuntimeError('Original Local worker startup was already attempted')
        self._funding.require_launch()
        self._launch_attempted = True
        try:
            assert self._channel is not None
            self._funding._ack(await self._channel.start_original())
            self._nominal()
        except BaseException as failure:
            raise LocalWorkerDriverPending(self) from failure
        self._ready = True

    async def open(self, operation: str, payload: bytes) -> httpx.Response:
        self._nominal()
        if not self._ready:
            raise LocalWorkerFundingUnavailable('Original Local worker startup is unconfirmed')
        body = _object(payload, _MAX_OPERATION_BYTES)
        if (type(operation) is not str or body.get('connection') != _LOCAL_SELECTION
                or not wire.valid_body(operation, body)):  # type: ignore[no-untyped-call]
            raise ValueError('Invalid original Local Client operation')
        assert self._channel is not None
        self._funding._ack(self._channel.require_current_original())
        self._nominal()
        # Exact immutable bytes retain the SDK's original request and input.
        # No Client operation is retried or reclassified on an exception/EOF.
        response = await self._channel.exchange_original(operation, payload)
        self._funding._ack(self._channel.require_current_original())
        self._nominal()
        if not isinstance(response, httpx.Response):
            raise RuntimeError('Invalid original Local worker response')
        return response

    async def aclose(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign original Local worker driver')
        if self._closed:
            return
        if self._close_inflight:
            raise RuntimeError('Original Local worker driver close cannot reenter')
        self._closing = True
        self._close_inflight = True
        try:
            if self._channel is not None and not self._channel_close_confirmed:
                self._funding._ack(await self._channel.close_original())
                # Retain this scoped physical/Owner return, so funding cleanup
                # failure cannot repeat an already acknowledged Host close.
                self._channel_close_confirmed = True
            # Delegation/parent funding settlement is a separate original Owner
            # pass. Channel EOF or successful Host close cannot substitute it.
            self._funding.close()
        except BaseException as failure:
            raise LocalWorkerDriverPending(self) from failure
        else:
            self._closed = True
        finally:
            self._close_inflight = False
