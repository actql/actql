"""Generated from named existing C shim definitions; do not edit."""
from ctypes import POINTER, c_int, c_int32, c_int64, c_uint64, c_size_t, c_uint16, c_ubyte, c_void_p, c_double, c_bool
from typing import Any

SIGNATURES: dict[str, tuple[list[Any], Any]] = {
    'actql_native_python_initial_platform_begin_into': ([POINTER(c_void_p)], c_int),
    'actql_native_python_initial_platform_current': ([c_void_p], c_bool),
    'actql_native_python_initial_platform_restore': ([c_void_p], c_int),
}

PARAMETERS = {
    'actql_native_python_initial_platform_begin_into': (('slot', 'actql_native_python_initial_platform_original **'),),
    'actql_native_python_initial_platform_current': (('original', 'actql_native_python_initial_platform_original *'),),
    'actql_native_python_initial_platform_restore': (('original', 'actql_native_python_initial_platform_original *'),),
}

ORIGINS = {
    'actql_native_python_initial_platform_begin_into': ('src/platform_native/host_bootstrap/python_initial_platform.c', 103),
    'actql_native_python_initial_platform_current': ('src/platform_native/host_bootstrap/python_initial_platform.c', 151),
    'actql_native_python_initial_platform_restore': ('src/platform_native/host_bootstrap/python_initial_platform.c', 158),
}

def bind(library: Any, symbol: str) -> Any:
    """Bind only a declared operation on the already selected library."""
    arguments, result = SIGNATURES[symbol]
    call = getattr(library, symbol)
    call.argtypes, call.restype = list(arguments), result
    return call

def bind_group(library: Any, prefix: str, names: tuple[str, ...]) -> dict[str, Any]:
    return {name: bind(library, prefix + name) for name in names}
