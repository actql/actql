"""Public SDK wire caller with actual SQLite and opaque scalar observations.

No actual Wasm execution, Store ACK, installed factory or wheel acceptance.
"""
import asyncio
import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk import AsyncClient, Client, ClientError
from actql_sdk._local_core import _Output, _PhysicalInput
from actql_sdk._local_commit_projection import OriginalCommitProjection
from actql_sdk._values import wire_bytes
import test_local_product_operation_port as operation_fixture

STATE = {'version': 'actql-run-state/0.1', 'run_id': 'original-owned-run', 'revision': 0,
    'status': 'succeeded', 'updated_at': '2026-09-17T00:00:03.000Z',
    'next_action': {'kind': 'refresh_availability', 'results': ['answer']},
    'result_available': False, 'result_availability': {'answer': {
        'state': 'unknown', 'observed_at': '2026-09-17T00:00:03.000Z',
        'reason': 'verification_pending'}}}


class PublicRunObservationTests(unittest.IsolatedAsyncioTestCase):
    def host(self, path):
        fixture = operation_fixture.LocalOperationPortTests()
        self.addCleanup(fixture.doCleanups)
        return fixture.host(path)

    def publication(self, host, core, execution):
        run = host._run_loans[0]
        ticket = core._next_ticket
        core._next_ticket += 1
        publication = _Output(core._identity, ticket, 990001, 1048576, 'publication')
        core._inputs[ticket] = _PhysicalInput(b'', lambda: True, lambda _: True)
        core._loans[ticket] = publication
        host._publications.append(publication)
        host._run_publications.append((run, publication))
        projection = OriginalCommitProjection(core, publication, host._configuration.handle, cleanup=lambda: True)
        host._commit_projections.append(projection)
        previous = core._call
        calls = []
        supplied = {'wire': wire_bytes(STATE), 'bind': 0}
        def call(family, name, *args):
            if family == 'publication' and name == 'validate_run':
                calls.append((family, name, args))
                self.assertEqual(args, (publication.handle, run.handle, host._configuration.handle))
                return supplied['bind']
            if family == 'publication' and name == 'close':
                self.assertEqual(args, (publication.handle,))
                return core._cleanup(ticket)
            return previous(family, name, *args)
        core._call = call
        def project(candidate, consume):
            self.assertIs(candidate, projection)
            calls.append(('opaque_fixture', 'state', ()))
            consume(supplied['wire'])
        selected = patch.object(host, '_project_original_run_state', side_effect=project)
        selected.start()
        self.addCleanup(selected.stop)
        # This public-wire fixture supplies opaque Core state only. The real
        # same-Store lookup/custody path is exercised by the separate caller
        # fixtures, rather than pretending this fabricated publication is Done.
        def ensure(candidate):
            self.assertIs(candidate, projection)
            calls.append(('opaque_fixture', 'lookup', ()))
        observation = patch.object(host, '_ensure_original_publication_observation', side_effect=ensure)
        observation.start()
        self.addCleanup(observation.stop)
        return run, projection, calls, supplied

    async def start(self, host):
        client = await AsyncClient._connect_local(host)
        original = json.loads(operation_fixture.PORT_INTENT)
        execution = await client.start_source(original['input']['text'], format='sql',
            parameters=original['parameters'], submission_ref=client.new_submission(nonce='original'),
            attempt_id='original-invocation')
        return client, execution

    async def test_async_status_and_wait_reobserve_original_rows_without_dispatch_or_state_calculation(self):
        with TemporaryDirectory() as directory:
            host, core, events, _ = self.host(Path(directory))
            client, execution = await self.start(host)
            run, _, calls, _ = self.publication(host, core, execution)
            before = len(events)
            self.assertEqual((await execution.status()).to_dict(), STATE)
            self.assertEqual((await execution.wait()).to_dict(), STATE)
            self.assertEqual((await execution.wait(until='terminal')).to_dict(), STATE)
            self.assertEqual(sum(name == 'inspect' for _, name in events[before:]), 3)
            self.assertEqual(sum(name == 'validate_run' for _, name, _ in calls), 6)
            self.assertEqual(sum(name == 'lookup' for _, name, _ in calls), 3)
            self.assertIs(host._run_loans[0], run)
            self.assertFalse(host._response_streams)
            self.assertFalse(any(family in ('source', 'task', 'compute') for family, _ in events[before:]))
            await client.aclose()
            self.assertTrue(core._closed)
            self.assertFalse(any(name == 'cancel' for _, name in events))

    async def test_unknown_owner_observation_is_not_replaced_by_succeeded_or_unavailable(self):
        with TemporaryDirectory() as directory:
            host, core, _, _ = self.host(Path(directory))
            client, execution = await self.start(host)
            _, _, _, supplied = self.publication(host, core, execution)
            unknown = STATE | {'status': 'needs_reconciliation',
                'next_action': {'kind': 'reconcile_run', 'reason': 'execution_unknown'}}
            supplied['wire'] = wire_bytes(unknown)
            self.assertEqual((await execution.status()).to_dict(), unknown)
            await client.aclose()

    async def test_foreign_scope_namespace_definition_and_unknown_field_refuse_without_projection(self):
        with TemporaryDirectory() as directory:
            host, core, _, _ = self.host(Path(directory))
            client, execution = await self.start(host)
            _, _, calls, _ = self.publication(host, core, execution)
            original = dict(execution.ref)
            for changed in (original | {'namespaceId': 'foreign'},
                            original | {'authorityScopeCid': 'sha256:' + 'c' * 64},
                            original | {'runDefinitionCid': 'sha256:' + 'd' * 64},
                            original | {'unknown': None}):
                before = len(calls)
                with self.assertRaises((ValueError, ClientError)):
                    await client._request('status', {'ref': changed})
                self.assertEqual(calls[before:], [])
            await client.aclose()

    async def test_core_foreign_run_refusal_and_bad_state_never_publish_success(self):
        with TemporaryDirectory() as directory:
            host, core, _, _ = self.host(Path(directory))
            client, execution = await self.start(host)
            _, _, calls, supplied = self.publication(host, core, execution)
            supplied['bind'] = -2
            with self.assertRaises(ClientError):
                await execution.status()
            self.assertFalse(any(family == 'opaque_fixture' for family, _, _ in calls))
            supplied['bind'] = 0
            supplied['wire'] = wire_bytes(STATE | {'unknown': True})
            with self.assertRaises(ClientError) as error:
                await execution.status()
            self.assertEqual(error.exception.code, 'InvalidHostRunState')
            self.assertFalse(host._response_streams)
            await client.aclose()

    async def test_saved_admission_failure_and_copied_host_preserve_original_loans(self):
        with TemporaryDirectory() as directory:
            host, core, _, _ = self.host(Path(directory))
            client, execution = await self.start(host)
            run, _, calls, _ = self.publication(host, core, execution)
            before = len(calls)
            with patch.object(host, '_read_original_saved_admission', side_effect=RuntimeError('Original lookup failed')):
                with self.assertRaises(ClientError):
                    await execution.status()
            self.assertEqual(calls[before:], [])
            with self.assertRaises(ValueError):
                copy.copy(host)._select_original_run(execution.ref)
            self.assertIs(host._run_loans[0], run)
            await client.aclose()


class SyncPublicRunObservationTests(unittest.TestCase):
    def test_sync_uses_same_original_status_and_wait_shape(self):
        with TemporaryDirectory() as directory:
            fixture = PublicRunObservationTests()
            self.addCleanup(fixture.doCleanups)
            host, core, _, _ = fixture.host(Path(directory))
            runner = asyncio.Runner()
            client = Client(runner, runner.run(AsyncClient._connect_local(host)))
            original = json.loads(operation_fixture.PORT_INTENT)
            with client:
                execution = client.start_source(original['input']['text'], format='sql',
                    parameters=original['parameters'], submission_ref=client.new_submission(nonce='original'),
                    attempt_id='original-invocation')
                fixture.publication(host, core, execution._execution)
                self.assertEqual(execution.status().to_dict(), STATE)
                self.assertEqual(execution.wait().to_dict(), STATE)
                self.assertEqual(execution.wait(until='terminal').to_dict(), STATE)
            self.assertTrue(core._closed)
