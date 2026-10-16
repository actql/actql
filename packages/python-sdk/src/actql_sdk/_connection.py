"""Remote connection-string projection; no discovery or authorization Owner.

Responsibility: project the existing Workspace connection-string contract.
Inputs: original URI, separate credential selection and optional asserted target.
Identity: preserve one decoded Workspace and the original credential choice.
Ownership: the existing Client retains credentials; no raw URI is retained.
Synchronization: pure admission precedes credential callbacks and transport.
Failure: invalid input has a fixed error with no borrowed parser cause.
Cancellation: parsing creates no task, exchange, retry or cleanup obligation.
Resources: original 16384/8192/256 UTF-16 bounds apply before transport.
Extension: no daemon, Local fallback, DNS discovery or grant is issued.
Verification: independent connection vectors and actual Remote consumer cases.
"""
import ipaddress
import re
from urllib.parse import unquote_to_bytes

import httpx

from ._errors import ClientError

NO_TOKEN = object()
_COMPONENT = re.compile(r"(?:[A-Za-z0-9._~!$&'()*+,;=:@-]|%[0-9A-Fa-f]{2})+", re.ASCII)
_CREDENTIAL = re.compile(r"(?:[A-Za-z0-9._~!$&'()*+,;=-]|%[0-9A-Fa-f]{2})+", re.ASCII)


def _units(value):
    return len(value.encode('utf-16-le')) // 2


def valid_dsn_credential(value):
    return (type(value) is str and 0 < len(value) <= 8192
            and all(0x21 <= ord(character) <= 0xff and ord(character) != 0x7f
                    for character in value))


def _ipv4(host):
    # Match the standard URL numeric-host interpretation before the HTTP
    # library can treat a shortened or hexadecimal address as a DNS name.
    parts = host.split('.')
    if len(parts) > 1 and parts[-1] == '':
        parts.pop()
    def number(part):
        radix = 10
        if part.lower().startswith('0x'):
            radix, part = 16, part[2:]
        elif len(part) >= 2 and part.startswith('0'):
            radix, part = 8, part[1:]
        if not part:
            return 0
        alphabet = {8: r'[0-7]+', 10: r'[0-9]+', 16: r'[0-9a-fA-F]+'}[radix]
        if re.fullmatch(alphabet, part) is None:
            raise ValueError('Invalid numeric Host')
        return int(part, radix)
    last = parts[-1]
    try:
        number(last)
        numeric = True
    except ValueError:
        numeric = bool(re.fullmatch(r'[0-9]+', last))
    if not numeric:
        return host
    if len(parts) > 4:
        raise ValueError('Invalid numeric Host')
    values = [number(part) for part in parts]
    if any(value > 255 for value in values[:-1]) or values[-1] >= 256 ** (5 - len(values)):
        raise ValueError('Invalid numeric Host')
    total = values[-1] + sum(value * 256 ** (3 - index)
                             for index, value in enumerate(values[:-1]))
    return str(ipaddress.IPv4Address(total))


def _parse(input):
    if (type(input) is not str or _units(input) > 16384
            or re.search(r'[\x00-\x20\x7f\\]', input)):
        raise ValueError('Invalid URI')
    match = re.fullmatch(r'actql://([^/?#]+)/([^/?#]+)(?:\?([^#]*))?', input, re.I | re.ASCII)
    if match is None:
        raise ValueError('Invalid URI')
    authority, encoded_workspace, query = match.groups()
    if query not in (None, 'transport=http') or _COMPONENT.fullmatch(encoded_workspace) is None:
        raise ValueError('Invalid URI')
    workspace = unquote_to_bytes(encoded_workspace).decode('utf-8', errors='strict')
    if (not workspace or _units(workspace) > 256 or workspace in ('.', '..')
            or re.search(r'[\x00-\x1f\x7f/\\]', workspace)):
        raise ValueError('Invalid Workspace')
    target, credential = authority, NO_TOKEN
    if '@' in authority:
        if authority.count('@') != 1:
            raise ValueError('Invalid credential')
        userinfo, target = authority.split('@')
        if not userinfo.startswith('token:') or _CREDENTIAL.fullmatch(userinfo[6:]) is None:
            raise ValueError('Invalid credential')
        credential = unquote_to_bytes(userinfo[6:]).decode('utf-8', errors='strict')
        if not valid_dsn_credential(credential):
            raise ValueError('Invalid credential')
    if not target or '%' in target:
        raise ValueError('Invalid authority')
    if target.startswith('['):
        end = target.index(']')
        host = str(ipaddress.IPv6Address(target[1:end]))
        loopback = host == '::1'
        tail = target[end + 1:]
        if tail and not tail.startswith(':'):
            raise ValueError('Invalid authority')
        port_text = tail[1:] if tail else ''
    else:
        host, separator, port_text = target.partition(':')
        if not separator:
            port_text = ''
        loopback = host.lower() == 'localhost' or (
            re.fullmatch(r'127(?:\.(?:0|[1-9][0-9]{0,2})){3}', host, re.ASCII) is not None
            and all(int(part) <= 255 for part in host.split('.')))
        host = _ipv4(host.lower())
    if re.fullmatch(r'[0-9]*', port_text, re.ASCII) is None:
        raise ValueError('Invalid port')
    port = int(port_text) if port_text else None
    if port is not None and port > 65535:
        raise ValueError('Invalid port')
    url = httpx.URL(scheme='https', host=host, port=port, path='/')
    if (not url.host or url.userinfo or url.raw_path != b'/' or url.query or url.fragment):
        raise ValueError('Invalid authority')
    host = url.raw_host.decode('ascii')
    if ':' in host:
        host = str(ipaddress.IPv6Address(host))
    else:
        host = _ipv4(host.lower())
    endpoint = str(url.copy_with(host=host))
    if query is not None:
        if not loopback or port == 0:
            raise ValueError('Invalid loopback target')
        # This adopted opt-in uses a private Node-only transport. Python does
        # not silently replace its TLS boundary or invoke Node to consume it.
        return endpoint, workspace, credential, True
    return endpoint, workspace, credential, False


def remote_connection(endpoint, token, workspace_id):
    """Return only admitted transport inputs, never a credential-bearing error."""
    if type(endpoint) is not str or not endpoint.lower().startswith('actql:'):
        return endpoint, token, workspace_id, False
    parsed = None
    try:
        parsed = _parse(endpoint)
    except (ValueError, TypeError, UnicodeError, OverflowError, httpx.InvalidURL):
        pass
    # Raise outside the parser exception handler: even __context__ must not
    # retain a lower-level error containing borrowed credential material.
    if parsed is None:
        raise ClientError('InvalidConnectionString')
    origin, workspace, embedded, unavailable = parsed
    if workspace_id is not None:
        raise ClientError('ConflictingConnectionWorkspace')
    if embedded is not NO_TOKEN and token is not NO_TOKEN:
        raise ClientError('ConflictingConnectionCredentials')
    if unavailable:
        raise ClientError('LoopbackHttpUnavailable')
    return origin, embedded if embedded is not NO_TOKEN else token, workspace, True
