"""Type-only current Run observation consumer; no runtime or Host invocation."""
from dataclasses import asdict
from collections.abc import Mapping
from typing import Any

from actql_sdk import AsyncExecution, Execution, RunState


def sync_observation(run: Execution) -> dict[str, Any]:
    state: RunState = run.status()
    revision: int = state.revision
    control: Mapping[str, Any] | None = state.control
    # The data field is immutable and supplies no cancellation permission.
    state.revision = revision + 1  # type: ignore[misc]
    if control is not None:
        control['revision'] = revision  # type: ignore[index]
    return asdict(run.wait(since=revision))


async def async_observation(run: AsyncExecution) -> int:
    state: RunState = await run.reconcile()
    return (await run.wait(since=state.revision)).revision
