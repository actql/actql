"""Nominal scalar transport only; actual ABI43 Wasm consumption is unverified."""
import copy
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _Output
import test_local_store_observation as observation_fixture


class IndexObservationLoanTests(unittest.TestCase):
    def bridge(self):
        core, parent, response, publisher, output, calls, state = observation_fixture.StoreObservationFacadeTests.bridge(self)
        state.update(lookup=0, lookup_retire=-9, reference=0)
        original_call = core._call
        def call(family, name, *args):
            if name in ('prepare_lookup', 'retire_lookup', 'produce_lookup_reference'):
                calls.append((family, name, args))
                return state[{'prepare_lookup': 'lookup', 'retire_lookup': 'lookup_retire',
                              'produce_lookup_reference': 'reference'}[name]]
            return original_call(family, name, *args)
        core._call = call
        return core, parent, response, publisher, output, calls, state

    def test_original_index_loan_and_publisher_forwarded_without_scope_or_acceptance(self):
        core, parent, response, publisher, _, calls, _ = self.bridge()
        core.prepare_publication_lookup(parent, response, publisher, 31)
        self.assertEqual(calls, [('publication', 'prepare_lookup', (23, 41, 17, 31))])
        self.assertIs(core._loans[7], parent)
        self.assertIs(core._loans[8], response)
        self.assertIs(core._loans[6], publisher)
        self.assertFalse(any(name in ('finish_commit', 'finish_observation', 'reserve') for _, name, _ in calls))

    def test_copies_foreign_family_and_revision_refuse_before_io(self):
        core, parent, response, publisher, output, calls, _ = self.bridge()
        foreign, _, other_input, other_publisher, _, _, _ = self.bridge()
        for action in (
            lambda: core.prepare_publication_lookup(copy.copy(parent), response, publisher, 31),
            lambda: core.prepare_publication_lookup(parent, copy.copy(response), publisher, 31),
            lambda: core.prepare_publication_lookup(parent, response, copy.copy(publisher), 31),
            lambda: core.prepare_publication_lookup(parent, other_input, publisher, 31),
            lambda: core.prepare_publication_lookup(parent, response, other_publisher, 31),
            lambda: core.prepare_publication_lookup(parent, response, output, 31),
            lambda: foreign.prepare_publication_lookup(parent, response, publisher, 31),
            lambda: core.prepare_publication_lookup(parent, response, publisher, True),
            lambda: core.prepare_publication_lookup(parent, response, publisher, 0),
            lambda: core.prepare_publication_lookup(parent, response, publisher, 2**31),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(calls, [])

    def test_bad_index_scope_denial_unknown_and_failed_borrow_keep_original_loans(self):
        for code in (-32, -35, -36, -5, -9, -33):
            with self.subTest(code=code):
                core, parent, response, publisher, _, calls, state = self.bridge()
                state['lookup'] = code
                with self.assertRaises(LocalCoreError) as error:
                    core.prepare_publication_lookup(parent, response, publisher, 31)
                self.assertEqual(error.exception.code, code)
                self.assertIs(core._loans[8], response)
                self.assertIs(core._loans[7], parent)
                self.assertIs(core._loans[6], publisher)
                self.assertEqual(len(calls), 1)

    def test_request_and_actual_attempt_reference_selection_uses_existing_output(self):
        core, parent, response, _, output, calls, state = self.bridge()
        for field, ordinal in (('request', 0), ('attempt', 1)):
            core.produce_publication_lookup_reference(output, 31, field=field)
            self.assertEqual(calls[-1], ('publication_commit_export', 'produce_lookup_reference',
                                        (43, 31, ordinal)))
        for value, current, field in ((copy.copy(output), 31, 'request'),
                                      (parent, 31, 'attempt'),
                                      (output, True, 'request'), (output, 0, 'request'),
                                      (output, 31, 'identity'), (output, 31, True)):
            before = len(calls)
            with self.assertRaises(ValueError):
                core.produce_publication_lookup_reference(value, current, field=field)
            self.assertEqual(len(calls), before)
        for code in (-32, -35, -36, -9, -5):
            state['reference'] = code
            with self.assertRaises(LocalCoreError):
                core.produce_publication_lookup_reference(output, 31, field='attempt')
            self.assertIs(core._loans[9], output)
            self.assertIs(core._loans[8], response)

    def test_query_failure_after_index_retains_both_loans_and_unknown_needs_durable_record(self):
        core, parent, response, publisher, _, calls, state = self.bridge()
        dependent = _Input(core._identity, 10, 47, 23)
        core._loans[10] = dependent
        core.prepare_publication_lookup(parent, response, publisher, 31)
        core.prepare_publication_observation(parent, dependent, publisher, 31)
        state['finish'] = 1
        self.assertEqual(core.finish_publication_observation(parent, 31), 'append_unknown')
        self.assertIs(core._loans[8], response)
        self.assertIs(core._loans[10], dependent)
        self.assertFalse(core.retire_publication_lookup(parent))
        self.assertIs(core._loans[8], response)
        self.assertFalse(any(name in ('finish_commit', 'prepare_commit', 'reserve') for _, name, _ in calls))

    def test_retirement_retries_same_parent_without_closing_original_input_or_run(self):
        core, parent, response, publisher, _, calls, state = self.bridge()
        core._closing = True
        self.assertFalse(core.retire_publication_lookup(parent))
        self.assertIs(core._loans[8], response)
        state['lookup_retire'] = 0
        self.assertTrue(core.retire_publication_lookup(parent))
        self.assertEqual(calls, [('publication', 'retire_lookup', (23,))] * 2)
        self.assertIs(core._loans[7], parent)
        self.assertIs(core._loans[8], response)
        self.assertIs(core._loans[6], publisher)
        with self.assertRaises(ValueError):
            core.retire_publication_lookup(copy.copy(parent))

    def test_actual_scalar_call_rejects_bool_and_traps_without_losing_nominal_custody(self):
        for scalar in (False, True, None, 0.0):
            with self.subTest(scalar=scalar):
                core, parent, response, publisher, _, _, _ = self.bridge()
                del core._call
                core._closed = core._retired = core._invoking = False
                core._store, core._nonce = object(), 19
                core._exports = {'actql_publication_prepare_lookup': lambda *args: scalar}
                with self.assertRaisesRegex(RuntimeError, 'scalar response'):
                    core.prepare_publication_lookup(parent, response, publisher, 31)
                self.assertIs(core._loans[8], response)
                self.assertFalse(core._invoking)
        core, parent, response, publisher, _, _, _ = self.bridge()
        del core._call
        core._closed = core._retired = core._invoking = False
        core._store, core._nonce = object(), 19
        def trap(*_):
            raise OSError('Original Core export observation unknown')
        core._exports = {'actql_publication_prepare_lookup': trap}
        with self.assertRaises(OSError):
            core.prepare_publication_lookup(parent, response, publisher, 31)
        self.assertTrue(core._closing)
        self.assertFalse(core._invoking)
        self.assertIs(core._loans[8], response)


if __name__ == '__main__':
    unittest.main()
