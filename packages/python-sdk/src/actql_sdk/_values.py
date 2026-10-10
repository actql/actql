"""Exact opaque JSON values and the existing canonical identity domains."""
from collections.abc import Mapping
import hashlib
import json
import math
import unicodedata
import rfc8785
from ._errors import ClientError

SAFE_INTEGER = 9007199254740991


def snapshot(value, *, max_nodes=100000, max_depth=64):
    nodes = 0
    active = set()

    def visit(item, depth):
        nonlocal nodes
        nodes += 1
        if nodes > max_nodes or depth > max_depth:
            raise ClientError('ClientValueLimit')
        if item is None or type(item) is bool:
            return item
        if type(item) is int:
            if abs(item) > SAFE_INTEGER:
                raise ClientError('UnrepresentableClientNumber')
            return item
        if type(item) is float:
            if not math.isfinite(item) or item == 0 and math.copysign(1, item) < 0:
                raise ClientError('UnrepresentableClientNumber')
            return item
        if type(item) is str:
            try:
                item.encode('utf-8', 'strict')
            except UnicodeError:
                raise ClientError('InvalidClientText') from None
            return item
        if type(item) not in (list, dict):
            raise ClientError('InvalidClientValue')
        if id(item) in active:
            raise ClientError('InvalidClientValue')
        active.add(id(item))
        try:
            if type(item) is list:
                return [visit(child, depth + 1) for child in item]
            if any(type(key) is not str for key in item):
                raise ClientError('InvalidClientValue')
            return {visit(key, depth + 1): visit(child, depth + 1) for key, child in item.items()}
        finally:
            active.remove(id(item))

    return visit(value, 0)


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


def content_cid(value, *, data_keys=False):
    return 'sha256:' + hashlib.sha256(canonical_bytes(value, data_keys=data_keys)).hexdigest()


def wire_bytes(value):
    # Wire order follows the caller's captured insertion order. Only identities sort keys.
    captured = snapshot(value)
    def encode(item):
        if type(item) is dict:
            # ECMAScript Object.keys orders array-index properties first.
            indices = sorted((key for key in item if key.isascii() and key.isdecimal()
                              and str(int(key)) == key and int(key) < 4294967295), key=int)
            keys = indices + [key for key in item if key not in set(indices)]
            return b'{' + b','.join(rfc8785.dumps(key) + b':' + encode(item[key]) for key in keys) + b'}'
        if type(item) is list:
            return b'[' + b','.join(encode(child) for child in item) + b']'
        return rfc8785.dumps(item)
    return encode(captured)


def decode_json(raw):
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
        # Opaque values use binary64; never silently round an integer lexeme.
        represented = float(number)
        if not math.isfinite(represented) or int(represented) != number:
            raise ClientError('InvalidHostResponse')
        return represented
    try:
        return snapshot(json.loads(raw.decode('utf-8', 'strict'),
            object_pairs_hook=object_pairs, parse_constant=bad_constant, parse_int=integer))
    except (UnicodeError, ValueError, OverflowError, RecursionError, ClientError):
        raise ClientError('InvalidHostResponse') from None


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
