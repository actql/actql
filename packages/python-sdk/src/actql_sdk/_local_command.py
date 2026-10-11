"""Bounded physical command decoding; Core owns SQL and value admission."""
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, cast

from ._local_duckdb import DuckDBParameter
from ._values import decode_json


@dataclass(frozen=True, slots=True)
class NativeCommand:
    sql: str
    parameters: tuple[DuckDBParameter, ...]


def native_command(payload: bytes) -> NativeCommand:
    """Consume the existing Core projection, never parse or rewrite query SQL.

    The shared JSON admission rejects duplicate keys, invalid Unicode and
    unrepresentable numbers. Physical scalar binding validates bits/copy limits
    before preparation. Neither decoding step is Program checking or a permit.
    """
    if type(payload) is not bytes or len(payload) > 100_000:
        raise ValueError('Invalid Native command transfer')
    value = cast(Callable[[bytes], Any], decode_json)(payload)
    if (type(value) is not dict or set(value) != {'sql', 'parameters'}
            or type(value['sql']) is not str or not value['sql']
            or '\0' in value['sql'] or type(value['parameters']) is not list
            or len(value['parameters']) > 32):
        raise ValueError('Invalid Native command projection')
    parameters = []
    for parameter in value['parameters']:
        if (type(parameter) is not dict or set(parameter) != {'type', 'value'}
                or type(parameter['type']) is not dict
                or set(parameter['type']) != {'id'}
                or type(parameter['type']['id']) is not str):
            raise ValueError('Invalid Native parameter projection')
        kind = parameter['type']['id']
        scalar = parameter['value']
        if (kind not in ('BOOLEAN', 'DOUBLE', 'VARCHAR')
                or (scalar is not None and not (
                    kind == 'BOOLEAN' and type(scalar) is bool
                    or kind in ('DOUBLE', 'VARCHAR') and type(scalar) is str))):
            raise ValueError('Unsupported Native physical binding')
        parameters.append(DuckDBParameter(kind, scalar))
    return NativeCommand(value['sql'], tuple(parameters))
