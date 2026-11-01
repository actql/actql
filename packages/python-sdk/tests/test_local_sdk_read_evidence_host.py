"""Installed Host custody with real File/SQLite, scalar Core only."""
import copy
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_check import OriginalLocalCheck
from actql_sdk._local_preparation import LocalPreparation
from actql_sdk._local_product import InstalledLocalHost
from actql_sdk._local_run import LocalRunCustody
from actql_sdk._local_sdk_read_storage import SDKReadEvidenceCleanupPending
import test_local_reader_facts as file_fixture
import test_local_sdk_read_storage as evidence_fixture


class SDKReadEvidenceHostTests(unittest.TestCase):
    def host(self, root, reader):
        fixture = evidence_fixture.SDKReadEvidenceStoreTests()
        fixture.addCleanup = self.addCleanup
        values = fixture.bridge(root, reader)
        holder, store, core, binding, observation, request, _, _, codes, _ = values
        self.assertTrue(holder.close())
        previous = core._call
        def call(family, name, *args):
            if family == 'program' and name == 'install_environment': return 1001
            if family == 'program' and name == 'reserve_preparation': return 1002
            if family == 'run' and name == 'install_sdk_configuration': return 31
            if family == 'run' and name == 'reserve': return 37
            return previous(family, name, *args)
        core._call = call
        preparation = LocalPreparation(core)
        environment = preparation.install_environment(request, profile='source-free')
        prepared = preparation.reserve(environment, request, format='text')
        runs = LocalRunCustody(core, preparation)
        configurations = []
        binding.inspect(lambda _: configurations.append(runs.install_sdk_configuration(binding._current, request)))
        configuration = configurations[0]
        run = runs.reserve(configuration, prepared, request)
        host = InstalledLocalHost.__new__(InstalledLocalHost)
        host._original, host._core, host._closing = host, core, False
        host._installation = SimpleNamespace(binding=binding, _store=store)
        host._configuration, host._runs = configuration, runs
        host._run_loans, host._commit_projections = [run], [observation._projection]
        host._store_observations = {observation._projection._publication.ticket: observation}
        host._sdk_read_evidence = {}
        host._sdk_deliveries = {}
        host._physical_work, host._response_streams = [], set()
        host._uncertain_ticket = None
        # Match the original constructor's empty retirement holders. No Check
        # operation or saved Run is issued by this scalar fixture.
        host._state_observing = False
        host._run_state_custody = {}
        host._saved_result_reads = []
        host._client_check = OriginalLocalCheck(host)
        return host, run, values

    def test_original_holder_is_reused_but_foreign_or_revoked_custody_is_not(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            host, run, values = self.host(root, helper.transfer_ready(root, final))
            _, store, core, _, observation, request, _, _, codes, _ = values
            projection = observation._projection
            holder = host._original_sdk_read_evidence(run, projection)
            ticket = core._next_ticket
            self.assertIs(host._original_sdk_read_evidence(run, projection), holder)
            self.assertEqual(core._next_ticket, ticket)
            for foreign in (copy.copy(run),):
                with self.assertRaises(ValueError): host._original_sdk_read_evidence(foreign, projection)
            host._persist_original_sdk_read_evidence(run, projection, request)
            grants = []
            host._project_original_sdk_read_grant(run, projection, request, lambda write: grants.append(write))
            self.assertEqual(grants[0].payload, b'opaque-issued-grant')
            before = store._connection.total_changes
            codes['current', 'bind'] = -35
            with self.assertRaises(LocalCoreError): host._original_sdk_read_evidence(run, projection)
            self.assertEqual(store._connection.total_changes, before)
            self.assertIs(host._sdk_read_evidence[projection._publication.ticket], holder)
            self.assertTrue(holder.close())

    def test_workspace_refusal_is_registered_before_escape_and_not_reconstructed(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            host, run, values = self.host(root, helper.transfer_ready(root, final))
            _, _, core, _, observation, request, _, producers, codes, _ = values
            codes['workspace', 'reserve'] = -4
            with self.assertRaises(SDKReadEvidenceCleanupPending) as failure:
                host._original_sdk_read_evidence(run, observation._projection)
            original = failure.exception.cleanup_evidence
            self.assertIs(host._sdk_read_evidence[observation._projection._publication.ticket], original)
            before = core._next_ticket
            with self.assertRaises(RuntimeError):
                host._persist_original_sdk_read_evidence(run, observation._projection, request)
            self.assertEqual(core._next_ticket, before)
            self.assertEqual(producers, [])
            self.assertTrue(original.close())

    def test_post_current_reentry_cannot_return_a_cached_holder(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            host, run, values = self.host(root, helper.transfer_ready(root, final))
            _, _, core, _, observation, _, _, _, _, _ = values
            holder = host._original_sdk_read_evidence(run, observation._projection)
            original = core._call
            def call(family, name, *args):
                result = original(family, name, *args)
                if family == 'publication' and name == 'validate_run': host._closing = True
                return result
            core._call = call
            before = core._next_ticket
            with self.assertRaises(ValueError): host._original_sdk_read_evidence(run, observation._projection)
            self.assertEqual(core._next_ticket, before)
            self.assertIs(host._sdk_read_evidence[observation._projection._publication.ticket], holder)
            self.assertTrue(holder.close())

    def test_failed_child_cleanup_retains_observation_and_original_run_until_retry(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            host, run, values = self.host(root, helper.transfer_ready(root, final))
            _, _, core, _, observation, _, _, _, _, _ = values
            holder = host._original_sdk_read_evidence(run, observation._projection)
            workspace = holder._workspace
            events = []
            with patch.object(observation._projection, 'close', side_effect=lambda: events.append('projection') or True), \
                    patch.object(core, 'close_workspace', return_value=False) as close, \
                    patch.object(core, 'retire_publication_observation', return_value=False) as retire:
                self.assertFalse(host.close())
                self.assertEqual(events, ['projection'])
                close.assert_called_once_with(workspace)
                retire.assert_not_called()
                self.assertIs(core._loans[workspace.ticket], workspace)
                self.assertIs(host._store_observations[observation._projection._publication.ticket], observation)
                self.assertIs(host._runs._runs[run.handle], run)
            with patch.object(core, 'retire_publication_observation', return_value=False) as retire:
                self.assertFalse(host.close())
                retire.assert_called_once_with(observation._projection._publication)
            self.assertFalse(host._sdk_read_evidence)
            self.assertNotIn(workspace.ticket, core._loans)
            self.assertIs(host._runs._runs[run.handle], run)
