"""Bounded definition-time callable records for one fixed original Host driver."""
from types import FunctionType
from typing import Any, cast


def _code(method: object) -> object:
    if type(method) in (classmethod, staticmethod):
        return cast(FunctionType, method.__func__).__code__
    if type(method) is property:
        getter = method.fget
        assert getter is not None
        return getter.__code__
    return method.__code__ if type(method) is FunctionType else None


def _capture_prepare_methods(cls: type, names: tuple[str, ...]) -> tuple[type, tuple[Any, ...]]:
    # Called beside the defining class, never from phase admission. The records
    # refer to code, not to an untrusted instance's current bound methods.
    return cls, tuple((name, vars(cls)[name], _code(vars(cls)[name])) for name in names)


def _capture_prepare_functions(namespace: dict[str, Any], names: tuple[str, ...]) -> tuple[Any, ...]:
    return namespace, tuple((name, namespace[name], _code(namespace[name])) for name in names)
