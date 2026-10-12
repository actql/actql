"""Private physical transport, not public admission or publisher authority."""
import copy
import json
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _Output, _PUBLISHER_LIMIT


class PublisherTransportTests(unittest.TestCase):
    def bridge(self, current=lambda: True, authorize=lambda _: True):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        core._inputs = {}
        core._released = set()
        core._next_ticket = 8
        preflight = _Output(core._identity, 6, 21, 1048576, 'publication_preflight')
        request = _Input(core._identity, 7, 23, 89)
        core._loans = {6: preflight, 7: request}
        state = {'reserve': 29, 'install': 0, 'authorize': 0, 'close': -9, 'ready': False}
        calls = []

        def call(family, name, *args):
            calls.append((family, name, args))
            self.assertEqual(family, 'publisher')
            if name == 'reserve':
                self.assertEqual(args[:3], (21, 23, state.get('expected_ticket', 8)))
                self.assertGreaterEqual(args[3], 128 * _PUBLISHER_LIMIT)
            if name == 'close' and state['close'] == 0:
                return 0 if core._cleanup(8) == 0 else -9
            return state[name]

        core._call = call
        port = core.reserve_publisher(preflight, request, current=current,
                                      authorize=authorize, cleanup=lambda: state['ready'])
        return core, port, preflight, request, calls, state

    def wire(self, stage='request', namespace='e\u0301😀\r\n'):
        # Independent six-field fixture, not copied from the product encoder.
        return json.dumps({'stage': stage, 'namespace_id': namespace,
            'authority_scope_cid': 'cid:sha256:' + '3' * 64,
            'run_definition_cid': 'cid:sha256:' + '4' * 64,
            'publication_request_cid': 'cid:sha256:' + '5' * 64,
            'public_index_entry_cid': None if stage == 'request' else 'cid:sha256:' + '6' * 64},
            ensure_ascii=False).encode()

    def transfer(self, core, wire):
        self.assertEqual(core._publisher_begin(8, len(wire)), 0)
        for index, byte in enumerate(wire):
            self.assertEqual(core._publisher_byte(8, index, byte), 0)
        return core._publisher_finish(8)

    def test_original_six_facts_preserve_unicode_null_and_all_stages(self):
        facts = []
        core, _, _, _, _, _ = self.bridge(authorize=lambda fact: facts.append(fact) or True)
        for stage in ('request', 'commit', 'return_committed'):
            self.assertEqual(self.transfer(core, self.wire(stage)), 0)
        self.assertEqual([fact.stage for fact in facts], ['request', 'commit', 'return_committed'])
        self.assertEqual(facts[0].namespace_id, 'e\u0301😀\r\n')
        self.assertIsNone(facts[0].public_index_entry_cid)
        self.assertEqual(facts[2].public_index_entry_cid, 'cid:sha256:' + '6' * 64)
        self.assertEqual(set(facts[0].__dataclass_fields__), {'stage', 'namespace_id',
            'authority_scope_cid', 'run_definition_cid', 'publication_request_cid', 'public_index_entry_cid'})

    def test_current_is_not_a_cached_grant_and_unknown_is_not_denial(self):
        state = {'value': True}
        core, _, _, _, _, _ = self.bridge(current=lambda: state['value'])
        for value, code in ((True, 0), (False, -1), (1, -2), (None, -2)):
            state['value'] = value
            self.assertEqual(core._publisher_current(8), code)
        self.assertEqual(core._publisher_current(999), -2)

    def test_authority_false_truthy_and_exception_are_distinct(self):
        def raises(_):
            raise RuntimeError('independent Owner unavailable')
        for callback, code in ((lambda _: True, 0), (lambda _: False, -1),
                               (lambda _: 1, -2), (raises, -2)):
            core, _, _, _, _, _ = self.bridge(authorize=callback)
            self.assertEqual(self.transfer(core, self.wire()), code)
            self.assertEqual(core._publisher_finish(8), -2)
            self.assertIsNone(core._inputs[8].publisher.buffer)

    def test_current_exception_retains_original_custody(self):
        def raises():
            raise RuntimeError('current authority unknown')
        core, port, preflight, request, _, _ = self.bridge(current=raises)
        self.assertEqual(core._publisher_current(8), -2)
        self.assertIs(core._loans[8], port)
        self.assertIs(core._loans[6], preflight)
        self.assertIs(core._loans[7], request)

    def test_incomplete_reordered_replayed_and_over_budget_frames_never_authorize(self):
        facts = []
        core, _, _, _, _, _ = self.bridge(authorize=lambda fact: facts.append(fact) or True)
        for length in (0, -1, _PUBLISHER_LIMIT + 1, True):
            self.assertEqual(core._publisher_begin(8, length), -2)
        self.assertEqual(core._publisher_begin(8, 3), 0)
        self.assertEqual(core._publisher_byte(8, 1, 65), -2)
        self.assertEqual(core._publisher_byte(8, 0, 256), -2)
        self.assertEqual(core._publisher_byte(8, 0, 65), 0)
        self.assertEqual(core._publisher_byte(8, 0, 65), -2)
        self.assertEqual(core._publisher_begin(8, 3), -2)
        self.assertEqual(core._publisher_finish(8), -2)
        self.assertEqual(facts, [])
        self.assertIsNone(core._inputs[8].publisher.buffer)

    def test_closed_fields_duplicate_wrong_stage_index_and_invalid_utf8_are_unknown(self):
        facts = []
        core, _, _, _, _, _ = self.bridge(authorize=lambda fact: facts.append(fact) or True)
        original = self.wire()
        bad = [b'\xff', original[:-1] + b',"extra":true}',
               original[:-1] + b',"stage":"request"}',
               original.replace(b'"request"', b'"other"'),
               original.replace(b'"public_index_entry_cid": null', b'"public_index_entry_cid": true'),
               original.replace(b'"request"', b'"commit"')]
        for wire in bad:
            self.assertEqual(self.transfer(core, wire), -2)
        self.assertEqual(facts, [])

    def test_authorize_control_rejects_copies_foreign_inputs_and_missing_index_before_io(self):
        core, port, preflight, request, calls, _ = self.bridge()
        before = len(calls)
        for action in (lambda: core.install_publisher(copy.copy(port), 31),
                       lambda: core.install_publisher(port, True),
                       lambda: core.authorize_publisher(port, 31, stage='commit'),
                       lambda: core.authorize_publisher(port, 31, stage='request', publication=preflight),
                       lambda: core.reserve_publisher(copy.copy(preflight), request,
                           current=lambda: True, authorize=lambda _: True, cleanup=lambda: True),
                       lambda: core.reserve_publisher(preflight, copy.copy(request),
                           current=lambda: True, authorize=lambda _: True, cleanup=lambda: True)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_request_and_original_index_handle_only_use_owner_authorization(self):
        core, port, _, _, calls, _ = self.bridge()
        publication = _Output(core._identity, 9, 41, 1048576, 'publication')
        core._loans[9] = publication
        core.install_publisher(port, 31)
        core.authorize_publisher(port, 37, stage='request')
        core.authorize_publisher(port, 43, stage='commit', publication=publication)
        core.authorize_publisher(port, 47, stage='return_committed', publication=publication)
        self.assertEqual(calls[1:], [('publisher', 'install', (29, 31)),
            ('publisher', 'authorize', (29, 37, 0, 0)), ('publisher', 'authorize', (29, 43, 1, 41)),
            ('publisher', 'authorize', (29, 47, 2, 41))])
        self.assertFalse(any(family in ('run', 'source', 'task', 'publication') for family, _, _ in calls))

    def test_owner_unknown_and_denied_keep_the_same_handle_without_retry(self):
        core, port, _, _, calls, state = self.bridge()
        for code in (-36, -35, -32):
            state['authorize'] = code
            count = len(calls)
            with self.assertRaises(LocalCoreError) as caught:
                core.authorize_publisher(port, 31, stage='request')
            self.assertEqual(caught.exception.code, code)
            self.assertEqual(len(calls), count + 1)
            self.assertIs(core._loans[8], port)

    def test_cleanup_pending_and_failed_then_retry_retains_original_borrow_and_parents(self):
        core, port, preflight, request, _, state = self.bridge()
        core._closing = True
        self.assertFalse(core.close_publisher(port))
        state['close'] = 0
        self.assertFalse(core.close_publisher(port))
        self.assertIs(core._loans[8], port)
        self.assertIs(core._loans[6], preflight)
        self.assertIs(core._loans[7], request)
        state['ready'] = True
        self.assertTrue(core.close_publisher(port))
        self.assertEqual(core._publisher_current(8), -2)
        with self.assertRaises(ValueError):
            core.close_publisher(port)

    def test_capacity_refusal_retires_only_unadmitted_transport_ticket(self):
        core, _, preflight, request, calls, state = self.bridge()
        state['reserve'] = -4
        state['expected_ticket'] = 9
        with self.assertRaises(LocalCoreError):
            core.reserve_publisher(preflight, request, current=lambda: True,
                authorize=lambda _: True, cleanup=lambda: True)
        self.assertNotIn(9, core._inputs)
        self.assertIs(core._loans[6], preflight)
        self.assertIs(core._loans[7], request)
        self.assertEqual(calls[-1][0:2], ('publisher', 'reserve'))

    def test_closing_never_installs_or_authorizes_new_transport(self):
        core, port, preflight, request, calls, _ = self.bridge()
        core._closing = True
        before = len(calls)
        for action in (lambda: core.install_publisher(port, 31),
                       lambda: core.authorize_publisher(port, 31, stage='request'),
                       lambda: core.reserve_publisher(preflight, request, current=lambda: True,
                           authorize=lambda _: True, cleanup=lambda: True)):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(len(calls), before)


if __name__ == '__main__':
    unittest.main()
