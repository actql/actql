"""The documented report attributes, without a local checker or engine import."""
from dataclasses import asdict
from typing import Any
from actql_sdk import AsyncClient, Client, CheckObservation


def sync_check(client: Client) -> dict[str, Any]:
    outcome: CheckObservation = client.check('SELECT 1', kind='text', format='sql', scope='template_only')
    if outcome.report is not None:
        verdict: str = outcome.report.verdict
        for reason in outcome.report.reasons:
            code: str = reason.code
            if reason.location is not None:
                reason.location['code'] = code  # type: ignore[index]
        outcome.report.verdict = 'verified'  # type: ignore[misc]
    return asdict(outcome)


async def async_check(client: AsyncClient) -> str:
    outcome = await client.check({}, kind='program', scope='template_only')
    return outcome.outcome


def existing_observation_compatibility(outcome: CheckObservation) -> dict[str, Any]:
    from actql_sdk import Observation, get_check_input, get_check_fixes
    from actql_sdk._types import CheckOutcome
    legacy: Observation[CheckOutcome] = outcome
    original = get_check_input(outcome, 'source')
    fixes = get_check_fixes(outcome)
    return {'wire': legacy.to_dict(), 'input': original, 'fixes': fixes}
