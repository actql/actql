"""Installed control binding between the original process/pipe and Client Wire.

This assembly does not supply the missing physical/Common/durable bootstrap
ports. They are mandatory before slot/spawn/DLL/Engine. No pointer is serialized
here and a startup/close return is never inferred from a PID or pipe EOF.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
import httpx

from ._local_worker_driver import _OriginalWorkerChannel
from ._local_worker_funding import OriginalWorkerFunding, LocalWorkerFundingUnavailable
from ._local_worker_pipe import OriginalWorkerPipe
from ._local_worker_process import OriginalWorkerProcess


class _InstalledWorkerControl(ABC):
    """Trusted installed Owner binding, not a user option or permit registry.

    Construction performs no physical acquisition. Implementations retain
    original bootstrap, I/O reservations and responses on exceptional returns.
    Wire framing transports only original data, never nominal object pointers.
    These abstract signatures do not prove a production supplier exists.
    """

    def __init__(self) -> None:
        self._original = self
        self._channel: OriginalWorkerPipeChannel | None = None

    def _bind(self, channel: OriginalWorkerPipeChannel) -> None:
        if self._original is not self or self._channel is not None:
            raise ValueError('Original installed worker control already has a channel')
        self._channel = channel

    @abstractmethod
    def prepare_original_bootstrap(self, process: OriginalWorkerProcess) -> object:
        """Existing Owner prepares durable same-scope startup before spawn.

        The returned nominal carrier stays local. Child transport must use the
        original Owner's data/adoption, not pickle or reissued pointer authority.
        Unknown preserves the same original durable responsibility, no reserve.
        """

    @abstractmethod
    async def start_original_host(self, process: OriginalWorkerProcess,
                                  pipe: OriginalWorkerPipe, bootstrap: object) -> object:
        """Original bootstrap exchange/adoption before DLL/Config/Engine.

        Selected source/recipe/child identity and actual scoped funding must be
        checked by existing Owners. None confirms only this startup scope.
        """

    @abstractmethod
    def require_current_original(self, process: OriginalWorkerProcess) -> object:
        """Same physical/lease/current Owner, not a PID-presence boolean."""

    @abstractmethod
    async def exchange_original_wire(self, process: OriginalWorkerProcess,
                                     pipe: OriginalWorkerPipe,
                                     operation: str, payload: bytes) -> httpx.Response:
        """Bounded existing Wire exchange under original I/O reservations.

        Reserve/charge/cleanup belong to existing resource Owners. Capture the
        original response stream before await/return; keep it after cancellation
        or post-current failure. Never retry/restart or synthesize a Run result.
        """

    @abstractmethod
    async def close_original_host(self, process: OriginalWorkerProcess,
                                  pipe: OriginalWorkerPipe, bootstrap: object | None) -> object:
        """Existing Owner closes/reconciles original pending Host/transport.

        It retains failed response/Store/FD/child custody. It must not turn exit
        into those ACKs or resend a prior close on lost acknowledgement. None is
        scoped Host/transport cleanup, separate from delegation settlement.
        """


class OriginalWorkerPipeChannel(_OriginalWorkerChannel):
    """Connect existing Driver.start/open/close to one process and pipe."""

    def __init__(self, funding: OriginalWorkerFunding | None,
                 process: OriginalWorkerProcess,
                 control: _InstalledWorkerControl | None) -> None:
        if type(funding) is not OriginalWorkerFunding or not isinstance(control, _InstalledWorkerControl):
            raise LocalWorkerFundingUnavailable('Original installed worker control is unavailable')
        if type(process) is not OriginalWorkerProcess or process._funding is not funding:
            raise ValueError('Foreign original worker channel process')
        super().__init__(funding)
        self._process, self._control = process, control
        self._pipe = OriginalWorkerPipe(funding, process)
        self._bootstrap: object | None = None
        self._start_attempted = False
        self._ready = False
        self._exchange_active = False
        self._exchange_unknown = False
        self._closing = False
        self._closed = False
        self._close_active = False
        self._host_close_confirmed = False
        control._bind(self)

    def _nominal(self) -> None:
        if (self._original_channel is not self or self._closing or self._closed
                or self._control._channel is not self or self._control._original is not self._control
                or self._driver is None):
            raise ValueError('Foreign or closing original worker channel')
        self._funding._nominal()
        if self._funding._closing or self._funding._driver_consumer is not self._driver:
            raise ValueError('Original worker channel funding is unavailable')

    async def start_original(self) -> object:
        self._nominal()
        if self._start_attempted:
            raise RuntimeError('Original worker channel startup was already attempted')
        self._funding.require_launch()
        self._nominal()
        self._start_attempted = True
        self._bootstrap = self._control.prepare_original_bootstrap(self._process)
        if not self._funding._opaque(self._bootstrap):
            raise LocalWorkerFundingUnavailable('Original worker bootstrap is unavailable')
        self._nominal()
        self._funding.require_launch()
        self._nominal()
        # The same original bootstrap is prepared before any slot/spawn I/O.
        self._process._slot.open()
        if not self._process._slot.try_acquire():
            raise LocalWorkerFundingUnavailable('Original worker slot is busy')
        self._process.spawn()
        self._pipe.prepare()
        self._funding._ack(await self._control.start_original_host(self._process, self._pipe, self._bootstrap))
        self.require_current_original()
        self._ready = True
        return None

    def require_current_original(self) -> object:
        self._nominal()
        self._funding.require_launch()
        self._funding._ack(self._control.require_current_original(self._process))
        self._nominal()
        return None

    async def exchange_original(self, operation: str, payload: bytes) -> httpx.Response:
        self.require_current_original()
        if not self._ready or self._exchange_active or self._exchange_unknown:
            raise ValueError('Original worker channel is not ready for an exchange')
        self._exchange_active = True
        try:
            response = await self._control.exchange_original_wire(self._process, self._pipe, operation, payload)
            # The control retains response custody before this current check.
            # SDK validates its actual public semantics, including failures.
            self.require_current_original()
            if not isinstance(response, httpx.Response):
                raise RuntimeError('Invalid original worker Wire response')
            return response
        except BaseException:
            # Unknown framing/reply progress stays in this same control. Do
            # not issue another command on a possibly misaligned pipe stream.
            self._exchange_unknown = True
            raise
        finally:
            self._exchange_active = False

    async def close_original(self) -> object:
        if (self._original_channel is not self or self._control._channel is not self
                or self._control._original is not self._control):
            raise ValueError('Foreign original worker channel')
        if self._closed:
            return None
        if self._close_active or self._exchange_active:
            raise RuntimeError('Original worker Host close is still in use')
        self._closing = True
        self._close_active = True
        try:
            if not self._host_close_confirmed:
                self._funding._ack(await self._control.close_original_host(self._process, self._pipe, self._bootstrap))
                self._host_close_confirmed = True
            self._pipe.close_parent()
            self._closed = True
        finally:
            self._close_active = False
        # Driver subsequently asks the same funding Owner to retire/settle.
        # Parent FD close and Host ACK alone never release that responsibility.
        return None
