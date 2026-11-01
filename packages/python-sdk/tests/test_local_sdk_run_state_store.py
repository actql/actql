"""Actual same-Store metadata CAS with a scalar Core protocol fixture.

No actual Wasm, physical payload availability, installed Host or wheel result.
The portable Owner cases separately validate state/key/counter semantics.
"""
from contextlib import nullcontext
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_product import InstalledLocalHost
from actql_sdk._local_storage import LocalStorageCommitUnknown
from actql_sdk._values import wire_bytes
import test_local_public_run_observation as fixture
import test_local_submission_append as submission_fixture
from local_abi_declaration_fixture import original_byte_fixture_port

SAVED_STATE = b'{"opaque":"same original Core saved state","revision":0}'


class SDKRunStateStoreTests(unittest.IsolatedAsyncioTestCase):
    async def test_confirmed_response_guard_and_transfer_share_original_read_frame(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            original = core._call
            entered = []
            confirmed = []
            def guarded(family, name, *args):
                if family == 'publication_commit_export' and name == 'confirm_sdk_run_state':
                    confirmed.append(core._journal_callbacks(host._configuration.current.ticket).reader)
                if family == 'publication' and name == 'validate_run':
                    callbacks = core._journal_callbacks(host._configuration.current.ticket)
                    if callbacks.check_current() != 0:
                        return -41
                    entered.append(callbacks.reader)
                return original(family, name, *args)
            core._call = original_byte_fixture_port(guarded)
            states = []
            def consume(raw):
                core.validate_publication_run(
                    host._commit_projections[0]._publication,
                    run.handle, host._configuration.handle)
                self.assertEqual(calls.count('confirm_sdk_run_state'), 1)
                self.assertFalse(host.close())
                self.assertFalse(host._closing)
                states.append(raw)
            observe(consume)
            self.assertEqual(states, [wire_bytes(fixture.STATE)])
            self.assertEqual(store.read(key).payload, SAVED_STATE)
            self.assertEqual(len(confirmed), 1)
            self.assertIsNot(entered[0], confirmed[0])
            self.assertIs(entered[-1], confirmed[0])
            self.assertIsNone(core._journal_callbacks(host._configuration.current.ticket).reader)
            with self.assertRaises(ValueError):
                entered[-1].current()
            await client.aclose()
            self.assertTrue(core._closed)

    async def test_final_original_run_guard_refusal_does_not_publish_confirmed_bytes(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            original = core._call
            def refuse(family, name, *args):
                if (family == 'publication' and name == 'validate_run'
                        and calls.count('confirm_sdk_run_state') == 1):
                    callbacks = core._journal_callbacks(host._configuration.current.ticket)
                    self.assertEqual(callbacks.check_current(), 0)
                    return -2
                return original(family, name, *args)
            core._call = original_byte_fixture_port(refuse)
            states = []
            def consume(raw):
                core.validate_publication_run(host._commit_projections[0]._publication,
                    run.handle, host._configuration.handle)
                states.append(raw)
            with self.assertRaises(LocalCoreError):
                observe(consume)
            self.assertEqual(states, [])
            self.assertEqual(calls.count('confirm_sdk_run_state'), 1)
            self.assertEqual(store.read(key).payload, SAVED_STATE)
            held = host._run_state_custody[run.handle]
            self.assertTrue(held.write_attempted)
            self.assertIs(core._loans[held.output.ticket], held.output)
            await client.aclose()
            self.assertTrue(core._closed)

    async def bridge(self, directory):
        case = fixture.PublicRunObservationTests()
        self.addCleanup(case.doCleanups)
        host, core, _, _ = case.host(Path(directory))
        client, execution = await case.start(host)
        self.addAsyncCleanup(client.aclose)
        run, projection, _, _ = case.publication(host, core, execution)
        def current():
            self.assertIsNotNone(core._journal_callbacks(host._configuration.current.ticket).reader)
        observation = SimpleNamespace(_projection=projection, _facts=(), _originals=(),
            _serialized_facts=nullcontext, _before_lookup=current, _validate_facts=lambda: None)
        host._store_observations[projection._publication.ticket] = observation
        store = host._installation._store
        key = store.namespaced_key('client_submitted_intents', submission_fixture.REQUEST)
        previous = core._call
        outputs, packets, calls, codes = {}, {}, [], {}
        def actual():
            callbacks = core._journal_callbacks(host._configuration.current.ticket)
            self.assertIsNotNone(callbacks.reader)
            rows = []
            callbacks.reader.read('client_submitted_intents', submission_fixture.REQUEST,
                                  lambda row: rows.append(row[1]))
            return rows[0]
        def call(family, name, *args):
            if family == 'publication' and name in ('retire_observation', 'retire_lookup'):
                self.assertEqual(args, (projection._publication.handle,))
                self.assertTrue(all(ticket not in core._loans for ticket in outputs.values()))
                return 0
            if family == 'publication_commit_export' and name == 'reserve':
                self.assertEqual(args[0], projection._publication.handle)
                handle = 4000000 + args[1]
                outputs[handle] = args[1]
                return handle
            if family == 'publication_commit_export' and args[0] in outputs:
                handle = args[0]
                calls.append(name)
                if name == 'produce_sdk_run_state':
                    self.assertEqual((args[1], args[3]), (run.handle, host._configuration.handle))
                    if 'during_produce' in codes:
                        codes['during_produce']()
                    row = actual()
                    packets[handle] = wire_bytes({'kind': 'retained' if row.payload == SAVED_STATE else 'replace',
                        'key': submission_fixture.REQUEST, 'revision': str(row.generation),
                        'body': SAVED_STATE.decode(), 'state': wire_bytes(fixture.STATE).decode()})
                    return codes.get(name, 0)
                if name == 'validate_sdk_run_state':
                    actual()
                    return codes.get(name, 0)
                if name == 'confirm_sdk_run_state':
                    row = actual()
                    return codes.get(name, 0) if row.payload == SAVED_STATE else -35
                if name == 'length': return len(packets[handle])
                if name == 'close': return core._cleanup(outputs[handle])
            if family == 'buffer' and name == 'byte' and args[0] in packets:
                return packets[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        def observe(consume):
            InstalledLocalHost._project_original_sdk_run_state(host, run, projection, consume)
        return host, core, client, run, store, key, calls, codes, observe

    async def test_commit_confirm_and_same_original_reobservation_do_not_rewrite(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            before = store.read(key)
            states = []
            observe(lambda raw: states.append(json.loads(raw)))
            saved = store.read(key)
            self.assertEqual((saved.payload, saved.generation), (SAVED_STATE, before.generation + 1))
            self.assertEqual(states, [fixture.STATE])
            self.assertFalse(host._run_state_custody)
            observe(lambda raw: states.append(json.loads(raw)))
            self.assertEqual(store.read(key), saved)
            self.assertEqual(states, [fixture.STATE, fixture.STATE])
            self.assertEqual(calls.count('produce_sdk_run_state'), 2)
            self.assertEqual(calls.count('validate_sdk_run_state'), 1)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 2)
            self.assertIs(host._runs._runs[run.handle], run)
            await client.aclose()
            self.assertTrue(core._closed)

    async def test_lost_commit_reply_keeps_same_output_for_lookup_without_second_write(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            original = store.compare_exchange_many_inspected
            def lose(*args, **kwargs):
                original(*args, **kwargs)
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose) as write:
                with self.assertRaises(LocalStorageCommitUnknown): observe(lambda _: self.fail('Unknown state escaped'))
            held = host._run_state_custody[run.handle]
            self.assertTrue(held.write_attempted)
            self.assertIs(core._loans[held.output.ticket], held.output)
            committed = store.read(key)
            states = []
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=AssertionError('Metadata write replay')):
                observe(lambda raw: states.append(json.loads(raw)))
            self.assertEqual(store.read(key), committed)
            self.assertEqual(states, [fixture.STATE])
            self.assertEqual(write.call_count, 1)
            self.assertEqual(calls.count('produce_sdk_run_state'), 1)
            self.assertFalse(host._run_state_custody)
            await client.aclose()

    async def test_prior_row_refusal_keeps_original_without_write_or_replay(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, codes, observe = await self.bridge(directory)
            before = store.read(key)
            codes['validate_sdk_run_state'] = -35
            with self.assertRaises(LocalCoreError): observe(lambda _: self.fail('Refused state escaped'))
            held = host._run_state_custody[run.handle]
            source, output = held.source, held.output
            self.assertEqual(store.read(key), before)
            codes.clear()
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=AssertionError('Metadata write replay')):
                with self.assertRaises(LocalCoreError): observe(lambda _: self.fail('Uncommitted state escaped'))
            self.assertIs(host._run_state_custody[run.handle], held)
            self.assertIs(core._loans[source.ticket], source)
            self.assertIs(core._loans[output.ticket], output)
            self.assertEqual(calls.count('produce_sdk_run_state'), 1)
            await client.aclose()
            self.assertTrue(core._closed)

    async def test_confirm_refusal_retries_only_same_committed_observation(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, codes, observe = await self.bridge(directory)
            codes['confirm_sdk_run_state'] = -35
            with self.assertRaises(LocalCoreError): observe(lambda _: self.fail('Unconfirmed state escaped'))
            held = host._run_state_custody[run.handle]
            committed = store.read(key)
            self.assertIs(core._loans[held.output.ticket], held.output)
            codes.clear()
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=AssertionError('Metadata write replay')):
                observe(lambda _: None)
            self.assertEqual(store.read(key), committed)
            self.assertEqual(calls.count('produce_sdk_run_state'), 1)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 2)
            await client.aclose()

    async def test_same_callback_cannot_close_parent_during_actual_state_operation(self):
        with TemporaryDirectory() as directory:
            host, core, client, _, _, _, _, codes, observe = await self.bridge(directory)
            results = []
            def reenter():
                results.append(host.close())
                self.assertFalse(host._closing)
                self.assertTrue(host._state_observing)
            codes['during_produce'] = reenter
            observe(lambda _: None)
            self.assertEqual(results, [False])
            self.assertFalse(host._state_observing)
            self.assertFalse(host._run_state_custody)
            await client.aclose()
            self.assertTrue(core._closed)

    async def test_retained_state_at_maximum_sql_generation_needs_no_successor(self):
        with TemporaryDirectory() as directory:
            _, _, client, _, store, key, calls, _, observe = await self.bridge(directory)
            store._connection.execute('UPDATE core_bytes SET generation=?,payload=? WHERE key=?',
                                      (2**63 - 1, SAVED_STATE, key))
            before = store.read(key)
            states = []
            with patch.object(store, 'compare_exchange_many_inspected',
                              side_effect=AssertionError('Retained metadata was rewritten')):
                observe(lambda raw: states.append(json.loads(raw)))
            self.assertEqual(store.read(key), before)
            self.assertEqual(states, [fixture.STATE])
            self.assertNotIn('validate_sdk_run_state', calls)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 1)
            await client.aclose()

    async def test_original_observation_callback_cannot_close_parent_before_produce(self):
        with TemporaryDirectory() as directory:
            host, core, client, _, _, _, _, _, observe = await self.bridge(directory)
            original = host._original_sdk_read_observation
            results = []
            def inspect(*args):
                results.append(host.close())
                self.assertTrue(host._state_observing)
                self.assertFalse(host._closing)
                return original(*args)
            with patch.object(host, '_original_sdk_read_observation', side_effect=inspect):
                observe(lambda _: None)
            self.assertEqual(results, [False])
            self.assertFalse(host._state_observing)
            await client.aclose()
            self.assertTrue(core._closed)


if __name__ == '__main__':
    unittest.main()
