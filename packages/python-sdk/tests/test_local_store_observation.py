"""Original nominal scalar facade with mocked Core, not physical Store ACK."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _Output


class StoreObservationFacadeTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        parent = _Output(core._identity, 7, 23, 1048576, 'publication')
        response = _Input(core._identity, 8, 41, 97)
        publisher = _Output(core._identity, 6, 17, 8192, 'publisher')
        output = _Output(core._identity, 9, 43, 1048576, 'publication_commit_export')
        core._loans = {6: publisher, 7: parent, 8: response, 9: output}
        state = {'prepare': 0, 'advance': 0, 'ready': 1, 'work': 3,
                 'finish': 4, 'retire': -9, 'produce': 0}
        calls = []
        def call(family, name, *args):
            calls.append((family, name, args))
            if name == 'observation_progress':
                return state['ready' if args[1] == 0 else 'work']
            return state[{'prepare_observation': 'prepare', 'advance_observation': 'advance',
                          'finish_observation': 'finish', 'retire_observation': 'retire',
                          'produce_observed_index': 'produce'}[name]]
        core._call = call
        return core, parent, response, publisher, output, calls, state

    def test_original_response_and_publisher_forwarded_without_scope_or_decision_reconstruction(self):
        core, parent, response, publisher, _, calls, _ = self.bridge()
        core.prepare_publication_observation(parent, response, publisher, 31)
        self.assertEqual(calls, [('publication', 'prepare_observation', (23, 41, 17, 31))])
        self.assertIs(core._loans[7], parent)
        self.assertIs(core._loans[8], response)
        self.assertIs(core._loans[6], publisher)

    def test_copied_foreign_wrong_family_and_revision_refuse_before_io(self):
        core, parent, response, publisher, output, calls, _ = self.bridge()
        for action in (
            lambda: core.prepare_publication_observation(copy.copy(parent), response, publisher, 31),
            lambda: core.prepare_publication_observation(parent, copy.copy(response), publisher, 31),
            lambda: core.prepare_publication_observation(parent, response, copy.copy(publisher), 31),
            lambda: core.prepare_publication_observation(parent, response, output, 31),
            lambda: core.prepare_publication_observation(parent, response, publisher, True),
            lambda: core.prepare_publication_observation(parent, response, publisher, 0),
            lambda: core.prepare_publication_observation(parent, response, publisher, 2**31),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(calls, [])

    def test_parse_denial_unknown_and_failed_validation_keep_original_loans(self):
        for code in (-32, -35, -36, -9):
            with self.subTest(code=code):
                core, parent, response, publisher, _, calls, state = self.bridge()
                state['prepare'] = code
                with self.assertRaises(LocalCoreError) as error:
                    core.prepare_publication_observation(parent, response, publisher, 31)
                self.assertEqual(error.exception.code, code)
                self.assertIs(core._loans[8], response)
                self.assertIs(core._loans[7], parent)
                self.assertEqual(len(calls), 1)

    def test_observation_progress_is_original_core_work_and_bad_scalars_are_rejected(self):
        core, parent, _, _, _, calls, state = self.bridge()
        self.assertEqual(core.advance_publication_observation(parent, 31, 7).work, 3)
        self.assertIn(('publication', 'advance_observation', (23, 31, 7)), calls)
        for ready, work in ((True, 0), (1, True), (2, 0), (0, -1), (1, 8), (1.0, 0)):
            state['ready'], state['work'] = ready, work
            with self.assertRaises(LocalCoreError):
                core.advance_publication_observation(parent, 31, 7)
        for quantum in (True, 0, -1, 2**31):
            with self.assertRaises(ValueError):
                core.advance_publication_observation(parent, 31, quantum)

    def test_owner_actions_distinguish_unknown_record_requirement_not_found_and_validated_stored_chain(self):
        core, parent, response, _, _, calls, state = self.bridge()
        for code, expected in ((1, 'append_unknown'), (3, 'confirm_uncommitted_failure'), (4, 'adopt_committed_index')):
            state['finish'] = code
            self.assertEqual(core.finish_publication_observation(parent, 31), expected)
        self.assertEqual(calls, [('publication', 'finish_observation', (23, 31))] * 3)
        self.assertIs(core._loans[8], response)
        self.assertFalse(any(name in ('finish_commit', 'prepare_commit', 'reserve') for _, name, _ in calls))

    def test_boolean_invalid_action_and_owner_failure_never_become_a_commit_ack(self):
        core, parent, response, _, _, _, state = self.bridge()
        for code in (False, True, 0, 2, 5, 1.0, None, -35, -36, -32):
            state['finish'] = code
            with self.assertRaises(LocalCoreError) as error:
                core.finish_publication_observation(parent, 31)
            self.assertEqual(error.exception.code, code if type(code) is int and code < 0 else -33)
            self.assertIs(core._loans[8], response)

    def test_cleanup_failure_retries_same_response_borrow_without_replaying_store_operation(self):
        core, parent, response, _, _, calls, state = self.bridge()
        core._closing = True
        self.assertFalse(core.retire_publication_observation(parent))
        self.assertIs(core._loans[8], response)
        state['retire'] = 0
        self.assertTrue(core.retire_publication_observation(parent))
        self.assertIs(core._loans[8], response)
        self.assertIs(core._loans[7], parent)
        self.assertEqual(calls, [('publication', 'retire_observation', (23,))] * 2)

    def test_actual_stored_index_projection_keeps_field_and_original_output_identity(self):
        core, parent, _, _, output, calls, state = self.bridge()
        core.produce_publication_observed_index(output, 31, field='identity')
        self.assertEqual(calls, [('publication_commit_export', 'produce_observed_index', (43, 31, 3))])
        for action in (
            lambda: core.produce_publication_observed_index(copy.copy(output), 31),
            lambda: core.produce_publication_observed_index(parent, 31),
            lambda: core.produce_publication_observed_index(output, True),
            lambda: core.produce_publication_observed_index(output, 31, field='committed'),
        ):
            with self.assertRaises(ValueError):
                action()
        state['produce'] = -36
        with self.assertRaises(LocalCoreError):
            core.produce_publication_observed_index(output, 31)
        self.assertIs(core._loans[9], output)
