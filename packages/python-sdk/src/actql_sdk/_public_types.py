"""Python call-site types; Host wire DTOs are generated in _types.py."""
from collections.abc import Awaitable, Callable
from typing import Literal, TypeAlias, Union

JSONValue: TypeAlias = Union[None, bool, int, float, str, list['JSONValue'], dict[str, 'JSONValue']]
Scope: TypeAlias = Literal['template_only', 'bound_input']
SourceFormat: TypeAlias = Literal['sql', 'aql', 'aql-text', 'aql-json', 'aql-yaml', 'json', 'yaml']
Token: TypeAlias = str | Callable[[], str | Awaitable[str]]
