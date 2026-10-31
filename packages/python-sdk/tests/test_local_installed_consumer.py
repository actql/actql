"""Public-call consumer spies and actual receipt I/O; no installed product execution."""
import asyncio
from contextlib import redirect_stdout
import importlib.util
from io import StringIO
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
from types import MappingProxyType, SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('installed_consumer', ROOT / 'scripts/fixtures/python-product-installed.py')
consumer = importlib.util.module_from_spec(spec); spec.loader.exec_module(consumer)
SUBMISSION = {'epoch': MappingProxyType({'epoch': 'original epoch'}), 'nonce': 'original nonce'}
RUN = {'run_id': 'original run', 'authority': 'original authority'}


class ClientSpy:
    def __init__(self, events, *, resume=False, observed=None):
        self.events, self.resume = events, resume
        self.observed = {'kind': 'ready', 'admission': {'ref': RUN}} if observed is None else observed
    def open(self): self.events.append(('open',)); return self
    def __enter__(self): return self
    def __exit__(self, *exc): self.events.append(('close',))
    def new_submission(self):
        if self.resume: raise AssertionError('Resume created a new submission')
        self.events.append(('new',)); return MappingProxyType(SUBMISSION)
    def start_source(self, text, **options):
        if self.resume: raise AssertionError('Resume resubmitted the Program')
        self.events.append(('start', text, options)); return RunSpy(self.events)
    def lookup_submission(self, reference):
        self.events.append(('lookup', reference)); return self.observed
    def attach(self, reference):
        self.events.append(('attach', reference)); return RunSpy(self.events)


class RunSpy:
    ref = MappingProxyType(RUN)
    def __init__(self, events): self.events = events
    def wait(self): self.events.append(('wait',)); return {'status': 'succeeded'}
    def result(self, name):
        self.events.append(('result', name)); return self
    def all(self, **limits): self.events.append(('all', limits)); return [{'n': 1}]


class AsyncClientSpy(ClientSpy):
    async def open(self): return super().open()
    async def __aenter__(self): return self
    async def __aexit__(self, *exc): self.events.append(('close',))
    async def start_source(self, text, **options):
        super().start_source(text, **options); return AsyncRunSpy(self.events)
    async def lookup_submission(self, reference): return super().lookup_submission(reference)
    async def attach(self, reference):
        super().attach(reference); return AsyncRunSpy(self.events)


class AsyncRunSpy(RunSpy):
    async def wait(self): return super().wait()
    async def all(self, **limits): return super().all(**limits)


class InstalledConsumerTests(unittest.TestCase):
    def setUp(self):
        directory = TemporaryDirectory(); self.addCleanup(directory.cleanup)
        self.receipt = Path(directory.name) / 'original.json'

    def saved(self):
        # Different-PID scalar fixture; not an actual engine/restart receipt.
        consumer._record(self.receipt, version='cohort', facade='sync', submission=SUBMISSION, run=RUN)
        body = json.loads(self.receipt.read_bytes()); body['producer_pid'] = os.getpid() + 1
        self.receipt.write_text(json.dumps(body)); return body

    def test_sync_and_async_initial_share_exact_public_calls_and_close_before_receipt(self):
        expected = None
        for facade in ('sync', 'async'):
            events = []; client = (ClientSpy if facade == 'sync' else AsyncClientSpy)(events)
            receipt = self.receipt.with_name(facade + '.json')
            with patch.dict('sys.modules', {'actql': SimpleNamespace(Client=client, AsyncClient=client)}):
                if facade == 'sync': consumer._sync('cohort', 'initial', receipt)
                else: asyncio.run(consumer._async('cohort', 'initial', receipt))
            body = json.loads(receipt.read_bytes())
            self.assertEqual(body['submission'], {'epoch': {'epoch': 'original epoch'}, 'nonce': 'original nonce'})
            self.assertEqual(body['run'], RUN); self.assertEqual(body['producer_facade'], facade)
            self.assertEqual(receipt.stat().st_mode & 0o777, 0o600)
            self.assertEqual([item[0] for item in events],
                ['open', 'new', 'start', 'wait', 'result', 'all', 'result', 'all', 'close'])
            self.assertEqual(events[2][1], 'SELECT 1 AS n')
            self.assertEqual(events[2][2]['format'], 'sql')
            self.assertEqual(events[5][1], {'max_rows': 1})
            if expected is None: expected = events
            else: self.assertEqual(events, expected)

    def test_resume_only_looks_up_and_attaches_original_without_submit_for_both_facades(self):
        self.saved(); before = self.receipt.read_bytes()
        for facade in ('sync', 'async'):
            events = []; client = (ClientSpy if facade == 'sync' else AsyncClientSpy)(events, resume=True)
            with patch.dict('sys.modules', {'actql': SimpleNamespace(Client=client, AsyncClient=client)}):
                if facade == 'sync': consumer._sync('cohort', 'resume', self.receipt)
                else: asyncio.run(consumer._async('cohort', 'resume', self.receipt))
            self.assertEqual([item[0] for item in events],
                ['open', 'lookup', 'attach', 'wait', 'result', 'all', 'result', 'all', 'close'])
            self.assertEqual(events[2][1], RUN); self.assertEqual(self.receipt.read_bytes(), before)

    def test_same_process_duplicate_unknown_or_wrong_cohort_receipt_refuses_before_open(self):
        consumer._record(self.receipt, version='cohort', facade='sync', submission=SUBMISSION, run=RUN)
        original = self.receipt.read_bytes()
        invalid = [original, original.replace(b'"cohort"', b'"other"'),
            b'{"version":"cohort",' + original[1:], b'{}']
        for body in invalid:
            self.receipt.write_bytes(body)
            with patch.dict('sys.modules', {'actql': SimpleNamespace(Client=None)}):
                with self.assertRaises(AssertionError): consumer._sync('cohort', 'resume', self.receipt)

    def test_receipt_symlink_public_permissions_and_oversize_are_not_restore_inputs(self):
        self.saved(); target = self.receipt.with_name('link.json'); target.symlink_to(self.receipt)
        with self.assertRaises(OSError): consumer._saved(target, 'cohort')
        self.receipt.chmod(0o644)
        with self.assertRaises(AssertionError): consumer._saved(self.receipt, 'cohort')
        self.receipt.chmod(0o600); self.receipt.write_bytes(b' ' * 65537)
        with self.assertRaises(AssertionError): consumer._saved(self.receipt, 'cohort')

    def test_missing_or_wrong_lookup_never_attaches_replacement_or_resubmits(self):
        self.saved()
        for observed in ({'kind': 'missing'}, {'kind': 'ready', 'admission': {'ref': {'run_id': 'foreign'}}}):
            events = []; client = ClientSpy(events, resume=True, observed=observed)
            with patch.dict('sys.modules', {'actql': SimpleNamespace(Client=client)}):
                with self.assertRaises(AssertionError): consumer._sync('cohort', 'resume', self.receipt)
            self.assertEqual([item[0] for item in events], ['open', 'lookup', 'close'])

    def test_boolean_float_extra_or_wrong_rows_are_not_expected_integer_result(self):
        consumer._rows([{'n': 1}])
        for value in ([{'n': True}], [{'n': 1.0}], [{'n': 2}], [{'n': 1, 'extra': 0}], [], [{'n': 1}, {'n': 1}]):
            with self.subTest(value=value), self.assertRaises(AssertionError): consumer._rows(value)

    def test_repeat_initial_receipt_is_rejected_before_open_not_replaced_by_new_run(self):
        self.saved(); before = self.receipt.read_bytes()
        with patch.object(consumer.metadata, 'version', return_value='cohort'), \
                patch.object(consumer, '_sync', side_effect=AssertionError('No new execution')) as start:
            with self.assertRaisesRegex(AssertionError, 'fresh receipt'):
                consumer.installed('cohort', 'local', facade='sync', phase='initial', receipt=self.receipt)
        self.assertEqual(start.call_count, 0); self.assertEqual(self.receipt.read_bytes(), before)

    def test_cleanup_failure_does_not_emit_success_or_retry_a_new_client(self):
        events = []
        class FailingClose(ClientSpy):
            def __exit__(self, *exc):
                super().__exit__(*exc)
                raise RuntimeError('original cleanup remains pending')
        client = FailingClose(events); output = StringIO()
        with patch.dict('sys.modules', {'actql': SimpleNamespace(Client=client)}), \
                patch.object(consumer.metadata, 'version', return_value='cohort'), redirect_stdout(output):
            with self.assertRaisesRegex(RuntimeError, 'cleanup remains pending'):
                consumer.installed('cohort', 'local', facade='sync', phase='initial', receipt=self.receipt)
        self.assertFalse(self.receipt.exists()); self.assertEqual(output.getvalue(), '')
        self.assertEqual(sum(event[0] == 'open' for event in events), 1)
        self.assertEqual(sum(event[0] == 'start' for event in events), 1)

    def test_failed_wait_keeps_original_ref_before_wait_without_a_success_receipt_or_repeat(self):
        events = []
        class FailedWait(RunSpy):
            def wait(inner):
                pending = json.loads(self.receipt.with_name(self.receipt.name + '.submitted').read_bytes())
                self.assertEqual(pending['run'], RUN)
                raise RuntimeError('original wait failed')
        client = ClientSpy(events)
        with patch.object(client, 'start_source', return_value=FailedWait(events)), \
                patch.dict('sys.modules', {'actql': SimpleNamespace(Client=client)}):
            with self.assertRaisesRegex(RuntimeError, 'original wait failed'):
                consumer._sync('cohort', 'initial', self.receipt)
        self.assertFalse(self.receipt.exists())
        with patch.object(consumer.metadata, 'version', return_value='cohort'), \
                patch.object(consumer, '_sync') as repeated:
            with self.assertRaisesRegex(AssertionError, 'fresh receipt'):
                consumer.installed('cohort', 'local', facade='sync', phase='initial', receipt=self.receipt)
        repeated.assert_not_called()

    def test_close_observer_requires_the_original_process_ack_after_observation(self):
        output = StringIO()
        with patch.object(consumer.sys, 'stdin', StringIO('observed\n')), redirect_stdout(output):
            consumer._observe_closed()
        rows = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([row['stage'] for row in rows], ['closed', 'close-observation-ack'])
        self.assertTrue(all(row['pid'] == os.getpid() for row in rows))
        output = StringIO()
        with patch.object(consumer.sys, 'stdin', StringIO('unobserved\n')), redirect_stdout(output):
            with self.assertRaisesRegex(RuntimeError, 'observation incomplete'): consumer._observe_closed()
        self.assertEqual(len(output.getvalue().splitlines()), 1)
