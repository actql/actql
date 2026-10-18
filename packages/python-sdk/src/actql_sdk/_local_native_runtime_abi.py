"""Generated private same-library declarations; do not edit."""
from ctypes import POINTER, c_int, c_int32, c_uint16, c_void_p

from typing import Any

BINDING_VERSION = 1
BINDING_SHA256 = '8e643ac041760fc965ea8b7edfd2bccf20893748dda76c8ed180ba80ff1e9538'

PARAMETERS = {
    'capture_utf16_into': (('host', 'host', 'borrow original Host'), ('read', 'read', 'borrow same original parent read'), ('root', 'utf16', 'borrow exact root UTF16 without normalization'), ('root_units', 'i32', 'UTF16 code units; 1..4096'), ('source', 'utf16', 'borrow exact source UTF16 without normalization'), ('source_units', 'i32', 'UTF16 code units; exact 40'), ('platform', 'utf16', 'borrow exact platform UTF16 without normalization'), ('platform_units', 'i32', 'UTF16 code units; 1..32'), ('manifest', 'utf16', 'borrow exact manifest UTF16 without normalization'), ('manifest_units', 'i32', 'UTF16 code units; exact 64'), ('ceiling', 'i32', 'positive diagnostic bytes within adopted workspace'), ('reply', 'reply_slot', 'persistent empty owned-reply output slot')),
    'capture_host_resources_utf16_into': (('host', 'host', 'borrow original Host'), ('read', 'read', 'borrow same original parent read'), ('resources', 'resources', 'borrow the same original Host resource pair and its already claimed Read; no replacement consumer or funding'), ('root', 'utf16', 'borrow exact root UTF16 without normalization'), ('root_units', 'i32', 'UTF16 code units; 1..4096'), ('source', 'utf16', 'borrow exact source UTF16 without normalization'), ('source_units', 'i32', 'UTF16 code units; exact 40'), ('platform', 'utf16', 'borrow exact platform UTF16 without normalization'), ('platform_units', 'i32', 'UTF16 code units; 1..32'), ('manifest', 'utf16', 'borrow exact manifest UTF16 without normalization'), ('manifest_units', 'i32', 'UTF16 code units; exact 64'), ('ceiling', 'i32', 'positive diagnostic bytes within adopted workspace'), ('reply', 'reply_slot', 'persistent empty owned-reply output slot')),
    'current_into': (('runtime', 'runtime', 'borrow original Runtime'), ('reply', 'reply_slot', 'persistent empty owned-reply output slot')),
    'close_into': (('runtime', 'runtime', 'borrow original Runtime until same cleanup ACK'), ('reply', 'reply_slot', 'persistent empty owned-reply output slot')),
    'originals_into': (('reply', 'reply', 'borrow original reply'), ('host', 'host_slot', 'owned original Host output'), ('read', 'read_slot', 'owned original parent-read output'), ('runtime', 'runtime_slot', 'owned nullable partial Runtime output')),
    'operation': (('reply', 'reply', 'borrow original reply'),),
    'issue_family': (('reply', 'reply', 'borrow original reply'),),
    'drop_reply': (('reply', 'reply_slot', 'same owned reply; null only after drop ACK'), ('host', 'host', 'borrow original Host'), ('read', 'read', 'borrow original read'), ('runtime', 'runtime', 'borrow nullable partial Runtime')),
    'finish_closed_data': (('host', 'host_slot', 'owned Host slot cleared after inner close ACK'), ('read', 'read_slot', 'owned parent-read slot cleared after inner close ACK'), ('runtime', 'runtime_slot', 'owned Runtime slot cleared after inner close ACK'), ('reply', 'reply_slot', 'owned close reply cleared after inner close ACK')),
    'finish_refused_capture': (('host', 'host_slot', 'owned Host slot after known no-Runtime refusal'), ('read', 'read_slot', 'owned read slot after known no-Runtime refusal'), ('reply', 'reply_slot', 'owned refusal reply slot')),
}

def bind(library: Any) -> dict[str, Any]:
    """Reject another compiled declaration before any Owner operation."""
    try:
        version = library.actql_packaged_runtime_binding_version
        byte = library.actql_packaged_runtime_binding_byte
    except AttributeError:
        raise ValueError("Unsupported original Native Runtime binding") from None
    version.argtypes, version.restype = [], c_int32
    byte.argtypes, byte.restype = [c_int32], c_int32
    if (version() != BINDING_VERSION or
            bytes(byte(i) for i in range(64)) != BINDING_SHA256.encode("ascii")):
        raise ValueError("Unsupported original Native Runtime binding")
    calls = {}
    call = library.actql_packaged_runtime_capture_utf16_into
    call.argtypes = [c_void_p, c_void_p, POINTER(c_uint16), c_int32, POINTER(c_uint16), c_int32, POINTER(c_uint16), c_int32, POINTER(c_uint16), c_int32, c_int32, POINTER(c_void_p)]
    call.restype = c_int
    calls['capture_utf16_into'] = call
    call = library.actql_packaged_runtime_capture_host_resources_utf16_into
    call.argtypes = [c_void_p, c_void_p, c_void_p, POINTER(c_uint16), c_int32, POINTER(c_uint16), c_int32, POINTER(c_uint16), c_int32, POINTER(c_uint16), c_int32, c_int32, POINTER(c_void_p)]
    call.restype = c_int
    calls['capture_host_resources_utf16_into'] = call
    call = library.actql_packaged_runtime_current_into
    call.argtypes = [c_void_p, POINTER(c_void_p)]
    call.restype = c_int
    calls['current_into'] = call
    call = library.actql_packaged_runtime_close_into
    call.argtypes = [c_void_p, POINTER(c_void_p)]
    call.restype = c_int
    calls['close_into'] = call
    call = library.actql_packaged_runtime_originals_into
    call.argtypes = [c_void_p, POINTER(c_void_p), POINTER(c_void_p), POINTER(c_void_p)]
    call.restype = c_int
    calls['originals_into'] = call
    call = library.actql_packaged_runtime_operation
    call.argtypes = [c_void_p]
    call.restype = c_int32
    calls['operation'] = call
    call = library.actql_packaged_runtime_issue_family
    call.argtypes = [c_void_p]
    call.restype = c_int32
    calls['issue_family'] = call
    call = library.actql_packaged_runtime_drop_reply
    call.argtypes = [POINTER(c_void_p), c_void_p, c_void_p, c_void_p]
    call.restype = c_int
    calls['drop_reply'] = call
    call = library.actql_packaged_runtime_finish_closed_data
    call.argtypes = [POINTER(c_void_p), POINTER(c_void_p), POINTER(c_void_p), POINTER(c_void_p)]
    call.restype = c_int
    calls['finish_closed_data'] = call
    call = library.actql_packaged_runtime_finish_refused_capture
    call.argtypes = [POINTER(c_void_p), POINTER(c_void_p), POINTER(c_void_p)]
    call.restype = c_int
    calls['finish_refused_capture'] = call
    return calls
