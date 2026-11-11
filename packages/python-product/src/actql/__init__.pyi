from os import PathLike as _PathLike
from actql_sdk import (
    AsyncClient as AsyncClient, AsyncExecution as AsyncExecution,
    AsyncResult as AsyncResult, AsyncReader as AsyncReader,
    Client as Client, Execution as Execution, Result as Result, Reader as Reader,
    Query as Query, QueryReader as QueryReader,
    AsyncQuery as AsyncQuery, AsyncQueryReader as AsyncQueryReader,
    ClientError as ClientError, RequestConflict as RequestConflict, Observation as Observation, RunState as RunState, Signer as Signer,
    CheckObservation as CheckObservation, CheckReport as CheckReport, CheckReason as CheckReason,
    get_submission_input as get_submission_input, get_check_input as get_check_input,
    get_submission_check_observation as get_submission_check_observation,
    resolve_check_location as resolve_check_location,
    resolve_check_text_range as resolve_check_text_range,
    explain_check_reason as explain_check_reason, get_check_fixes as get_check_fixes,
    JSONValue as JSONValue, Scope as Scope, SourceFormat as SourceFormat, Token as Token,
)

def open(*, state_dir: str | _PathLike[str] = ..., signer: Signer | None = ...) -> Client: ...

connect = Client.connect
