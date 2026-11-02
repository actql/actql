"""Standard product facade over the same Client and original Owner contracts."""
from os import PathLike as _PathLike
from actql_sdk import (
    AsyncClient, AsyncExecution, AsyncResult, AsyncReader, AsyncQuery, AsyncQueryReader,
    Client, Execution, Result, Reader, Query, QueryReader, ClientError, RequestConflict, Observation, RunState, Signer,
    CheckObservation, CheckReport, CheckReason,
    get_submission_input, get_check_input, get_submission_check_observation,
    resolve_check_location, resolve_check_text_range, explain_check_reason, get_check_fixes,
    JSONValue, Scope, SourceFormat, Token,
)

__all__ = [
    'open', 'AsyncClient', 'AsyncExecution', 'AsyncResult', 'AsyncReader',
    'Client', 'Execution', 'Result', 'Reader', 'Query', 'QueryReader', 'AsyncQuery', 'AsyncQueryReader', 'ClientError', 'RequestConflict', 'Observation', 'RunState', 'Signer',
    'CheckObservation', 'CheckReport', 'CheckReason',
    'get_submission_input', 'get_check_input', 'get_submission_check_observation',
    'resolve_check_location', 'resolve_check_text_range', 'explain_check_reason', 'get_check_fixes',
    'JSONValue', 'Scope', 'SourceFormat', 'Token',
]


def open(*, state_dir: str | _PathLike[str] = '.actql',
         signer: Signer | None = None) -> Client:
    """Open the same Local Client and its original Store, without a server."""
    return Client.open(state_dir=state_dir, signer=signer)
