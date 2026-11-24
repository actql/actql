"""Exact opaque JSON values and the existing canonical identity domains."""
from collections.abc import Mapping
import hashlib
from itertools import chain as _chain
import json
import math
import unicodedata
import rfc8785
from ._errors import ClientError

SAFE_INTEGER = 9007199254740991
_JSON_MAX_NODES = 100000
_JSON_MAX_DEPTH = 64
_RETAINED_NODE_BYTES = 64


def _admit_value(value, max_nodes, max_depth, *, measure_fresh):
    # Only the internal JSON decoder can supply a tree that has never escaped.
    # A mutable caller value still takes the original snapshot and cycle checks.
    nodes = 0
    members = 0
    extent = 0
    active = None if measure_fresh else set()

    def visit(item, depth):
        nonlocal nodes, members, extent
        nodes += 1
        if nodes > max_nodes or depth > max_depth:
            raise ClientError('ClientValueLimit')
        kind = type(item)
        if kind is list or kind is dict:
            if measure_fresh:
                # Brackets or braces, plus separators. Key order affects the
                # wire but cannot change its extent.
                extent += 2 + max(0, len(item) - 1)
                if kind is dict:
                    members += len(item)
                    extent += len(item)  # One colon per member.
                    for key, child in item.items():
                        visit(key, depth + 1)
                        visit(child, depth + 1)
                else:
                    for child in item:
                        visit(child, depth + 1)
                return item
            if id(item) in active:
                raise ClientError('InvalidClientValue')
            active.add(id(item))
            try:
                if kind is list:
                    return [visit(child, depth + 1) for child in item]
                if any(type(key) is not str for key in item):
                    raise ClientError('InvalidClientValue')
                return {visit(key, depth + 1): visit(child, depth + 1) for key, child in item.items()}
            finally:
                active.remove(id(item))
        if kind is int:
            if abs(item) > SAFE_INTEGER:
                raise ClientError('UnrepresentableClientNumber')
        elif kind is float:
            if not math.isfinite(item) or item == 0 and math.copysign(1, item) < 0:
                raise ClientError('UnrepresentableClientNumber')
        elif item is not None and kind is not bool and kind is not str:
            raise ClientError('InvalidClientValue')
        if measure_fresh:
            # The existing canonical scalar encoder also rejects invalid text.
            # Its scalar bytes are discarded immediately. No whole row is encoded.
            extent += len(rfc8785.dumps(item))
        elif kind is str:
            try:
                item.encode('utf-8', 'strict')
            except UnicodeError:
                raise ClientError('InvalidClientText') from None
        return item

    original = visit(value, 0)
    retained = extent + (nodes + members) * _RETAINED_NODE_BYTES if measure_fresh else 0
    return original, retained


def snapshot(value, *, max_nodes=_JSON_MAX_NODES, max_depth=_JSON_MAX_DEPTH):
    original, _ = _admit_value(value, max_nodes, max_depth, measure_fresh=False)
    return original


def canonical_bytes(value, *, data_keys=False):
    captured = snapshot(value)

    def keys(item):
        if type(item) is list:
            return [keys(child) for child in item]
        if type(item) is not dict:
            return item
        result = {}
        for key, child in item.items():
            name = key if data_keys else unicodedata.normalize('NFC', key).replace('\r\n', '\n').replace('\r', '\n')
            if name in result:
                raise ClientError('CanonicalKeyCollision')
            result[name] = keys(child)
        return result

    return rfc8785.dumps(keys(captured))


def bytes_cid(value):
    return 'sha256:' + hashlib.sha256(value).hexdigest()


def content_cid(value, *, data_keys=False):
    return bytes_cid(canonical_bytes(value, data_keys=data_keys))


def wire_bytes(value):
    # Wire order follows the caller's captured insertion order. Only identities sort keys.
    captured = snapshot(value)
    def encode(item):
        if type(item) is dict:
            # An ECMAScript array index is a canonical decimal uint32
            # strictly below 2**32 - 1. Bound the integer conversion first.
            indices, ordinary = [], []
            for key in item:
                length = len(key)
                if (0 < length <= 10 and (length == 1 or key[0] != '0')
                        and key.isascii() and key.isdecimal()):
                    index = int(key)
                    if index < 4294967295:
                        indices.append((index, key))
                        continue
                ordinary.append(key)
            indices.sort()
            keys = _chain((key for _, key in indices), ordinary)
            return b'{' + b','.join(rfc8785.dumps(key) + b':' + encode(item[key]) for key in keys) + b'}'
        if type(item) is list:
            return b'[' + b','.join(encode(child) for child in item) + b']'
        return rfc8785.dumps(item)
    return encode(captured)


def _decode_json(raw, *, measure_fresh):
    def object_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ClientError('InvalidHostResponse')
            result[key] = value
        return result
    def bad_constant(_):
        raise ClientError('InvalidHostResponse')
    def integer(text):
        if text == '-0':
            raise ClientError('InvalidHostResponse')
        number = int(text)
        if abs(number) <= SAFE_INTEGER:
            return number
        # Binary64's shortest JSON spelling can differ from its exact integer
        # value (for example 2**63). Accept that canonical spelling, while
        # retaining rejection of other integer lexemes that would be rounded.
        represented = float(number)
        if (not math.isfinite(represented) or int(represented) != number
                and rfc8785.dumps(represented) != text.encode('ascii')):
            raise ClientError('InvalidHostResponse')
        return represented
    try:
        decoded = json.loads(raw.decode('utf-8', 'strict'),
            object_pairs_hook=object_pairs, parse_constant=bad_constant, parse_int=integer)
        return _admit_value(decoded, _JSON_MAX_NODES, _JSON_MAX_DEPTH, measure_fresh=measure_fresh)
    except (UnicodeError, ValueError, OverflowError, RecursionError, ClientError):
        raise ClientError('InvalidHostResponse') from None


def decode_json(raw):
    value, _ = _decode_json(raw, measure_fresh=False)
    return value


def _decode_result_value(raw):
    """Return the original decoded value and its exact SDK retention charge."""
    return _decode_json(raw, measure_fresh=True)


class Observation(Mapping):
    """Immutable public data. Original-call custody is held separately by the SDK."""
    __slots__ = ('__data', '__weakref__')
    __hash__ = object.__hash__
    __eq__ = object.__eq__

    def __init__(self, value):
        object.__setattr__(self, '_Observation__data', freeze(snapshot(value)))

    def __setattr__(self, name, value):
        raise AttributeError('ImmutableObservation')

    def __getitem__(self, key):
        return self.__data[key]

    def __iter__(self):
        return iter(self.__data)

    def __len__(self):
        return len(self.__data)

    def to_dict(self):
        return thaw(self.__data)


def freeze(value):
    from types import MappingProxyType
    if type(value) is dict:
        return MappingProxyType({key: freeze(child) for key, child in value.items()})
    if type(value) is list:
        return tuple(freeze(child) for child in value)
    return value


def thaw(value):
    if isinstance(value, Mapping):
        return {key: thaw(child) for key, child in value.items()}
    if isinstance(value, (tuple, list)):
        return [thaw(child) for child in value]
    return value
