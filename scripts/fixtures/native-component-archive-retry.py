"""Exercise the actual CI inline downloader with private, pinned input fixtures."""
import hashlib
import io
import json
import os
from pathlib import Path
import ssl
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request

COMMAND = sys.stdin.read()
PAYLOADS = [b'original sqlite archive', b'original development package', b'original license package']
URLS = ['https://fixture.invalid/' + name for name in ('sqlite.zip', 'dev.deb', 'license.deb')]


class DownloadControls(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / 'runner/native-cli-linux-local/inputs'
        self.originals = [dict(url=url, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
                          for url, raw in zip(URLS, PAYLOADS)]
        base = self.root / 'packages/python-local-runtime/native'
        for name, body in [('sqlite-component', {'upstream': self.originals[0]}),
                           ('crypto-component', {'source_targets': {'x86_64-unknown-linux-gnu': {
                               'package': self.originals[1], 'license': {'package': self.originals[2]}}}})]:
            path = base / name
            path.mkdir(parents=True)
            (path / 'source.json').write_text(json.dumps(body))

    def response(self, url, **_):
        return io.BytesIO(PAYLOADS[URLS.index(url)])

    def run_command(self, open_url, *, clock=lambda: 100.0, sleep=None):
        # Only this isolated fixture process changes its private working directory.
        previous = Path.cwd()
        os.chdir(self.root)
        try:
            with patch.dict(os.environ, {'RUNNER_TEMP': str(self.root / 'runner')}), \
                    patch.object(urllib.request, 'urlopen', side_effect=open_url) as opened, \
                    patch.object(time, 'monotonic', side_effect=clock), \
                    patch.object(time, 'sleep', side_effect=sleep) as slept:
                self.opened, self.slept = opened, slept
                exec(compile(COMMAND, 'CI Retain exact official component archives', 'exec'), {})
        finally:
            os.chdir(previous)

    def assert_originals(self):
        for name, raw in zip(('sqlite.zip', 'libssl-dev.deb', 'libssl3t64.deb'), PAYLOADS):
            self.assertEqual((self.output / name).read_bytes(), raw)

    def test_success_keeps_same_three_urls_pins_and_exclusive_outputs(self):
        self.run_command(self.response)
        self.assert_originals()
        self.assertEqual([call.args[0] for call in self.opened.call_args_list], URLS)
        self.assertTrue(all(0 < call.kwargs['timeout'] <= 60 for call in self.opened.call_args_list))
        self.slept.assert_not_called()

    def test_wrapped_tls_reset_retries_only_same_original_get(self):
        failure = urllib.error.URLError(ConnectionResetError(104, 'reset during TLS handshake'))
        def opened(url, **args):
            if self.opened.call_count == 1:
                raise failure
            self.assertFalse((self.output / 'sqlite.zip').exists() if url == URLS[0] else False)
            return self.response(url, **args)
        self.run_command(opened)
        self.assert_originals()
        self.assertEqual([call.args[0] for call in self.opened.call_args_list], [URLS[0], *URLS])
        self.slept.assert_called_once_with(1)

    def test_partial_read_timeout_discards_bytes_and_closes_before_retry(self):
        class Partial(io.BytesIO):
            def read(self, bound):
                self.bound = bound
                super().read(3)
                raise TimeoutError('original transfer timed out')
        partial = Partial(PAYLOADS[0])
        def opened(url, **args):
            if self.opened.call_count == 1:
                return partial
            self.assertTrue(partial.closed)
            self.assertFalse((self.output / 'sqlite.zip').exists() if url == URLS[0] else False)
            return self.response(url, **args)
        self.run_command(opened)
        self.assertEqual(partial.bound, len(PAYLOADS[0]) + 1)
        self.assert_originals()

    def test_exhaustion_keeps_last_original_failure_and_creates_no_archive(self):
        failures = [urllib.error.URLError(ConnectionResetError(104, str(i))) for i in range(3)]
        with self.assertRaises(urllib.error.URLError) as observed:
            self.run_command(lambda *_args, **_kwargs: (_ for _ in ()).throw(failures[self.opened.call_count - 1]))
        self.assertIs(observed.exception, failures[-1])
        self.assertEqual(self.opened.call_count, 3)
        self.assertEqual([call.args[0] for call in self.opened.call_args_list], [URLS[0]] * 3)
        self.assertEqual([call.args[0] for call in self.slept.call_args_list], [1, 2])
        self.assertEqual(list(self.output.iterdir()), [])

    def test_permanent_http_refusal_is_not_a_transport_retry(self):
        failure = urllib.error.HTTPError(URLS[0], 404, 'original missing', {}, None)
        with self.assertRaises(urllib.error.HTTPError) as observed:
            self.run_command(lambda *_args, **_kwargs: (_ for _ in ()).throw(failure))
        self.assertIs(observed.exception, failure)
        self.assertEqual(self.opened.call_count, 1)
        self.slept.assert_not_called()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_integrity_or_extent_mismatch_never_retries_or_writes(self):
        # The SHA pin is independently authored above; a same-length wrong body
        # cannot become a replacement input through a transport retry.
        self.originals[0]['sha256'] = '0' * 64
        path = self.root / 'packages/python-local-runtime/native/sqlite-component/source.json'
        path.write_text(json.dumps({'upstream': self.originals[0]}))
        with self.assertRaises(AssertionError):
            self.run_command(self.response)
        self.assertEqual(self.opened.call_count, 1)
        self.slept.assert_not_called()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_short_body_never_retries_or_leaves_partial_file(self):
        with self.assertRaises(AssertionError):
            self.run_command(lambda *_args, **_kwargs: io.BytesIO(PAYLOADS[0][:-1]))
        self.assertEqual(self.opened.call_count, 1)
        self.slept.assert_not_called()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_existing_output_is_not_overwritten_or_retried(self):
        def opened(url, **args):
            (self.output / 'sqlite.zip').write_bytes(b'existing original')
            return self.response(url, **args)
        with self.assertRaises(FileExistsError):
            self.run_command(opened)
        self.assertEqual((self.output / 'sqlite.zip').read_bytes(), b'existing original')
        self.assertEqual(self.opened.call_count, 1)
        self.slept.assert_not_called()

    def test_original_deadline_refuses_a_retry_that_does_not_fit(self):
        failure = urllib.error.URLError(ConnectionResetError(104, 'original reset'))
        values = iter([0.0, 0.0, 59.5])
        with self.assertRaises(urllib.error.URLError) as observed:
            self.run_command(lambda *_args, **_kwargs: (_ for _ in ()).throw(failure), clock=lambda: next(values))
        self.assertIs(observed.exception, failure)
        self.assertEqual(self.opened.call_count, 1)
        self.slept.assert_not_called()

    def test_certificate_failure_never_weakens_trust_or_retries(self):
        failure = urllib.error.URLError(ssl.SSLCertVerificationError('original trust refusal'))
        with self.assertRaises(urllib.error.URLError) as observed:
            self.run_command(lambda *_args, **_kwargs: (_ for _ in ()).throw(failure))
        self.assertIs(observed.exception, failure)
        self.assertEqual(self.opened.call_count, 1)
        self.slept.assert_not_called()


suite = unittest.defaultTestLoader.loadTestsFromTestCase(DownloadControls)
assert suite.countTestCases() == 10
result = unittest.TextTestRunner(verbosity=2).run(suite)
if not result.wasSuccessful() or result.testsRun != 10 or result.skipped:
    raise SystemExit(1)
print('Pinned component archive controls: 10/10')
