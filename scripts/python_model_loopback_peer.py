"""Fixture peer for the ordinary installed Python Model case.

The parent owns the fixture certificate, controlled key, and independent
expected Chat request/response. This counts the real peer-side cuts
without a replacement client resolver, transport, or TLS implementation.
"""
from contextlib import contextmanager
from dataclasses import dataclass
from hashlib import sha256
from hmac import compare_digest
from http.server import BaseHTTPRequestHandler, HTTPServer
from io import BufferedReader, RawIOBase
from select import select
from threading import Condition, Thread
from typing import Callable
import json
import ssl


@dataclass(frozen=True)
class Observation:
    tcp: int
    tls: int
    trust_alerts: int
    ambiguous_handshake_failures: int
    application_connections: int
    posts: int
    partial_responses: int
    request_hashes: tuple[str, ...]
    rejected: tuple[str, ...]


class Peer(HTTPServer):
    allow_reuse_address = False
    request_queue_size = 2

    def __init__(self, tls: ssl.SSLContext, check: Callable[[dict], None],
                 fixture_authorization: bytes, reply: bytes, *, lose_response: bool):
        self.tls_context = tls
        self.check = check
        self.fixture_authorization = fixture_authorization
        self.reply = reply
        self.lose_response = lose_response
        self.lock = Condition()
        self.tcp = self.tls = self.trust_alerts = self.ambiguous_handshake_failures = 0
        self.application_connections = self.posts = self.partial_responses = 0
        self.active = 0
        self.request_hashes: list[str] = []
        self.rejected: list[str] = []
        super().__init__(('127.0.0.1', 0), Handler)

    def observe(self) -> Observation:
        # The parent takes a snapshot after its selected child exits. An
        # accepted-but-unserved or still-open connection is not a zero event.
        with self.lock:
            def retired():
                return not self.active and not select((self.socket,), (), (), 0)[0]
            if not self.lock.wait_for(retired, timeout=3):
                raise RuntimeError('controlled Model peer has pending connections')
            return Observation(self.tcp, self.tls, self.trust_alerts,
                               self.ambiguous_handshake_failures, self.application_connections,
                               self.posts, self.partial_responses, tuple(self.request_hashes),
                               tuple(self.rejected))

    def get_request(self):
        with self.lock:
            raw, address = self.socket.accept()
            self.tcp += 1
            self.active += 1
        try:
            raw.settimeout(2)
            accepted = self.tls_context.wrap_socket(raw, server_side=True)
        except BaseException as failure:
            # Timeout, raw EOF, reset, and other local I/O are distinct from
            # an actual received certificate alert. The parent separately
            # checks the original client's typed failure.
            observed_alert = isinstance(failure, ssl.SSLError) and failure.reason in (
                'TLSV1_ALERT_UNKNOWN_CA', 'SSLV3_ALERT_BAD_CERTIFICATE',
                'SSLV3_ALERT_CERTIFICATE_UNKNOWN')
            try:
                raw.close()
            finally:
                with self.lock:
                    if observed_alert:
                        self.trust_alerts += 1
                    else:
                        self.ambiguous_handshake_failures += 1
                    self.active -= 1
                    self.lock.notify_all()
            raise
        with self.lock:
            self.tls += 1
        return accepted, address

    def close_request(self, request):
        super().close_request(request)
        with self.lock:
            self.active -= 1
            self.lock.notify_all()

    def handle_error(self, request, client_address):
        # The original installed consumer owns its own primary. Never print
        # a peer stack, headers, fixture secret or full request.
        with self.lock:
            self.rejected.append('peer_io')


class _ObserveApplicationRead(RawIOBase):
    def __init__(self, source, peer: Peer):
        super().__init__()
        self.source = source
        self.peer = peer
        self.observed = False

    def readable(self):
        return True

    def readinto(self, buffer):
        received = self.source.readinto(buffer)
        if received and not self.observed:
            self.observed = True
            # Only a count leaves the direct TLS read. Record before any
            # request line, complete header, or JSON decode can be required.
            with self.peer.lock:
                self.peer.application_connections += 1
        return received

    def close(self):
        if not self.closed:
            try:
                self.source.close()
            finally:
                super().close()


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        super().setup()
        self.rfile.close()  # Created by Base, still unused.
        raw = self.connection.makefile('rb', buffering=0)
        self.rfile = BufferedReader(_ObserveApplicationRead(raw, self.server), buffer_size=4096)

    def log_message(self, *args):
        pass

    def do_POST(self):
        peer = self.server
        self.close_connection = True
        with peer.lock:
            peer.posts += 1
            ordinal = peer.posts
        try:
            authorization = self.headers.get_all('Authorization', [])
            length = self.headers.get_all('Content-Length', [])
            if (self.path != '/v1/chat/completions' or ordinal != 1 or len(authorization) != 1
                    or not compare_digest(authorization[0].encode('ascii'), peer.fixture_authorization)
                    or len(length) != 1 or not length[0].isdecimal() or len(length[0]) > 6
                    or self.headers.get_all('Transfer-Encoding', [])):
                raise ValueError('selected request required')
            count = int(length[0])
            if not 0 < count <= 65536:
                raise ValueError('request bound')
            body = self.rfile.read(count)
            if len(body) != count:
                raise ValueError('request incomplete')
            request = json.loads(body, object_pairs_hook=unique_object)
            if type(request) is not dict:
                raise ValueError('request shape')
            peer.check(request)
        except Exception:
            with peer.lock:
                peer.rejected.append('request')
            self.send_error(400)
            return
        with peer.lock:
            peer.request_hashes.append(sha256(body).hexdigest())
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(peer.reply)))
        self.send_header('Connection', 'close')
        self.end_headers()
        if peer.lose_response:
            self.wfile.write(peer.reply[:len(peer.reply) // 2])
            self.wfile.flush()
            with peer.lock:
                peer.partial_responses += 1
        else:
            self.wfile.write(peer.reply)
            self.wfile.flush()


def unique_object(entries):
    result = {}
    for key, value in entries:
        if key in result:
            raise ValueError('duplicate field')
        result[key] = value
    return result


@contextmanager
def controlled_model_peer(context: ssl.SSLContext, check: Callable[[dict], None],
                          fixture_authorization: bytes, reply: bytes, *,
                          lose_response: bool = False):
    if (type(context) is not ssl.SSLContext or not callable(check)
            or type(fixture_authorization) is not bytes
            or not fixture_authorization.startswith(b'Bearer ')
            or len(fixture_authorization) > 4096
            or type(reply) is not bytes or not 2 <= len(reply) <= 65536
            or type(lose_response) is not bool):
        raise ValueError('invalid bounded controlled Model peer')
    with Peer(context, check, fixture_authorization, reply, lose_response=lose_response) as peer:
        thread = Thread(target=peer.serve_forever, args=(0.05,))
        thread.start()
        try:
            yield f'https://127.0.0.1:{peer.server_port}/v1/chat/completions', peer.observe
        finally:
            if thread.is_alive():
                peer.shutdown()
            thread.join(3)
            if thread.is_alive():
                raise RuntimeError('original controlled fixture peer retirement is pending')
