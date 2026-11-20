"""Actual raw-fixture oracle with explicit exit ports; no Core/Run/thread start."""
from concurrent.futures import Future
from contextlib import redirect_stderr
import importlib.util
import io
import json
from pathlib import Path
from types import SimpleNamespace
import unittest

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_product import _OriginalExecution
from actql_sdk._local_work import OriginalLocalWork

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('cancellation_worker_fixture',
    ROOT / 'scripts/fixtures/python-local-public-cancellation-abi.py')
FIXTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURE)


class CancellationWorkerOracleTests(unittest.TestCase):
    def worker(self, *, failure=None, stop=True):
        host, run = object(), object()
        original = _OriginalExecution(host, run)
        if stop:
            original.stop_interest = object()  # Explicit consumed-stop DATA port only.
        work = OriginalLocalWork(original, owner=run)
        work._future = Future()
        if failure is None:
            work._future.set_result(None)
        else:
            work._future.set_exception(failure)
        return host, original, work

    def check(self, work, host, *, precommit=False):
        output = io.StringIO()
        with redirect_stderr(output):
            FIXTURE.assert_original_cancellation_worker(work, host, precommit=precommit)
        return json.loads(output.getvalue())

    def test_same_original_managed_stop_accepts_only_a_successful_physical_exit(self):
        host, original, work = self.worker()
        actual = self.check(work, host)['managedCancellationObservation']
        self.assertEqual(actual, {'workerSucceeded': True, 'workerFailureType': None,
                                  'sameOriginalStopInterest': True})
        self.assertFalse(work._invoked)
        self.assertFalse(work.stopped)

    def test_genuine_worker_errors_remain_errors_even_after_managed_stop_interest(self):
        for failure in [LocalCoreError('task_drive', -35), LocalCoreError('task_drive', -33),
                        RuntimeError('explicit fixture failure')]:
            with self.subTest(error=type(failure).__name__):
                host, original, work = self.worker(failure=failure)
                with redirect_stderr(io.StringIO()), self.assertRaises(AssertionError):
                    FIXTURE.assert_original_cancellation_worker(work, host, precommit=False)
                self.assertIs(work._future.exception(), failure)

    def test_missing_or_foreign_original_stop_cannot_satisfy_the_managed_oracle(self):
        host, original, work = self.worker(stop=False)
        with redirect_stderr(io.StringIO()), self.assertRaises(AssertionError):
            FIXTURE.assert_original_cancellation_worker(work, host, precommit=False)
        host, original, work = self.worker()
        for foreign in [SimpleNamespace(_invoke=original), object()]:
            with redirect_stderr(io.StringIO()), self.assertRaises(AssertionError):
                FIXTURE.assert_original_cancellation_worker(work, foreign, precommit=False)
        work._owner = object()
        with redirect_stderr(io.StringIO()), self.assertRaises(AssertionError):
            FIXTURE.assert_original_cancellation_worker(work, host, precommit=False)

    def test_precommit_preserves_the_original_publication_refusal(self):
        failure = LocalCoreError('produce_original_commit', -35)
        host, original, work = self.worker(failure=failure, stop=False)
        actual = self.check(work, host, precommit=True)['latePublicationObservation']
        self.assertEqual((actual['operation'], actual['code']), ('produce_original_commit', -35))
        for cause in [None, LocalCoreError('produce_original_commit', -33)]:
            host, original, work = self.worker(failure=cause, stop=False)
            with redirect_stderr(io.StringIO()), self.assertRaises(AssertionError):
                FIXTURE.assert_original_cancellation_worker(work, host, precommit=True)
