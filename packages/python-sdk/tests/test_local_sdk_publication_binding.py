"""Same-Store wrapper custody with scalar Core; not physical Wasm admission."""
import copy
import unittest

from actql_sdk._local_core import LocalCoreError, _MATERIAL_SIGNATURES
import test_local_host_current as current_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


WIRE = b'{"kind":"publication","key":"original","revision":"0","body":"e\xcc\x81/~\\r\\n"}'


class SDKPublicationBindingCustodyTests(unittest.TestCase):
    def bridge(self):
        fixture = current_fixture.LocalHostCurrentTests()
        self.addCleanup(fixture.doCleanups)
        core, _, current, store, calls, _, _ = fixture.bridge()
        previous = core._call
        statuses = {}

        def call(family, name, *args):
            if family == 'material':
                calls.append((family, name, args))
                if name == 'reserve':
                    self.assertEqual(args[:2], (7, 9))
                    self.assertGreaterEqual(args[3], 2 * 1048576)
                    return 30
                if name in statuses:
                    result = statuses[name]
                    if isinstance(result, BaseException):
                        raise result
                    return result
                if name in ('validate_sdk_publication', 'confirm_sdk_publication'):
                    self.assertIsNotNone(core._journal_callbacks(current.ticket).reader)
                    return 0
                if name == 'length':
                    return len(WIRE)
                if name in ('retire_output', 'close'):
                    return core._cleanup(3)
                return 0
            if family == 'buffer' and name == 'byte' and args[0] == 30:
                return WIRE[args[1]]
            return previous(family, name, *args)

        core._call = original_byte_fixture_port(call)
        material = core.reserve_material(7, 9, cleanup=lambda: True)

        def inside(action):
            def inspect(reader):
                with core.host_current_frame(current, reader):
                    core.bind_host_current(current)
                    action()
            fixture.inside(store, inspect)
        return core, current, material, calls, statuses, inside

    def test_original_candidate_and_confirmation_delegate_in_same_store_frame(self):
        core, current, material, calls, _, inside = self.bridge()
        result = []
        inside(lambda: result.append(core.read_sdk_publication_binding(material, current)))
        self.assertEqual(result, [WIRE])
        inside(lambda: core.confirm_sdk_publication_binding(material, current))
        self.assertTrue(any(name == 'confirm_sdk_publication' for _, name, _ in calls))
        self.assertFalse(any(family in ('run', 'compute', 'publication') for family, _, _ in calls))
        self.assertEqual(_MATERIAL_SIGNATURES['confirm_sdk_publication'], ('i64 i32', 'i32'))
        self.assertTrue(core.close_material(material))

    def test_cached_bytes_remain_subordinate_to_fresh_owner_check(self):
        core, current, material, _, statuses, inside = self.bridge()
        inside(lambda: core.read_sdk_publication_binding(material, current))
        statuses['validate_sdk_publication'] = -32
        with self.assertRaises(LocalCoreError) as failure:
            inside(lambda: core.read_sdk_publication_binding(material, current))
        self.assertEqual(failure.exception.code, -32)
        self.assertIs(core._loans[material.ticket], material)

    def test_unknown_confirmation_preserves_original_loan_without_retry(self):
        core, current, material, calls, statuses, inside = self.bridge()
        statuses['confirm_sdk_publication'] = -41
        with self.assertRaises(LocalCoreError) as failure:
            inside(lambda: core.confirm_sdk_publication_binding(material, current))
        self.assertEqual(failure.exception.code, -41)
        self.assertEqual(sum(name == 'confirm_sdk_publication' for _, name, _ in calls), 1)
        self.assertIs(core._loans[material.ticket], material)
        self.assertFalse(any(name == 'produce' for _, name, _ in calls))

    def test_copied_material_or_unbound_current_refuses_before_core_io(self):
        core, current, material, calls, _, inside = self.bridge()
        before = len(calls)
        with self.assertRaises(ValueError):
            core.read_sdk_publication_binding(material, current)
        self.assertEqual(len(calls), before)
        with self.assertRaises(ValueError):
            inside(lambda: core.confirm_sdk_publication_binding(copy.copy(material), current))
        self.assertFalse(any(name == 'confirm_sdk_publication' for _, name, _ in calls))

    def test_cleanup_failure_keeps_same_ticket_then_retirement_blocks_read(self):
        core, current, material, _, statuses, inside = self.bridge()
        statuses['retire_output'] = -9
        self.assertFalse(core.retire_material_output(material))
        self.assertIs(core._loans[material.ticket], material)
        self.assertIn(material.ticket, core._inputs)
        del statuses['retire_output']
        self.assertTrue(core.retire_material_output(material))
        self.assertIs(core._loans[material.ticket], material)
        self.assertNotIn(material.ticket, core._inputs)
        with self.assertRaisesRegex(RuntimeError, 'cleanup has completed'):
            inside(lambda: core.read_sdk_publication_binding(material, current))


    def test_pre_current_callback_close_refuses_before_confirmation_io(self):
        core, current, material, calls, _, inside = self.bridge()
        callbacks = core._journal_callbacks(current.ticket)
        state = {'active': False}
        original = callbacks.current

        def observe():
            original()
            if state['active']:
                state['active'] = False
                self.assertTrue(core.close_material(material))

        callbacks.current = observe

        def confirm():
            state['active'] = True
            with self.assertRaisesRegex(ValueError, 'Foreign or released'):
                core.confirm_sdk_publication_binding(material, current)

        inside(confirm)
        self.assertNotIn(material.ticket, core._loans)
        self.assertFalse(any(name == 'confirm_sdk_publication' for _, name, _ in calls))

    def test_post_current_callback_close_cannot_confirm_released_material(self):
        core, current, material, calls, _, inside = self.bridge()
        callbacks = core._journal_callbacks(current.ticket)
        state = {'active': False, 'calls': 0}
        original = callbacks.current

        def observe():
            original()
            if state['active']:
                state['calls'] += 1
                if state['calls'] == 2:
                    self.assertTrue(core.close_material(material))

        callbacks.current = observe

        def confirm():
            state['active'] = True
            with self.assertRaisesRegex(ValueError, 'Foreign or released'):
                core.confirm_sdk_publication_binding(material, current)
            state['active'] = False

        inside(confirm)
        self.assertEqual(state['calls'], 2)
        self.assertNotIn(material.ticket, core._loans)
        self.assertEqual(sum(name == 'confirm_sdk_publication' for _, name, _ in calls), 1)
        self.assertFalse(any(family in ('run', 'compute', 'publication') for family, _, _ in calls))

    def test_current_close_pending_preserves_same_reader_and_material_loans(self):
        core, current, material, calls, _, inside = self.bridge()
        callbacks = core._journal_callbacks(current.ticket)
        state = {'active': False, 'calls': 0}
        closes = []
        original = callbacks.current

        def observe():
            original()
            if state['active']:
                state['calls'] += 1
                if state['calls'] == 2:
                    closes.append(core.close_host_current(current))

        callbacks.current = observe

        def confirm():
            state['active'] = True
            core.confirm_sdk_publication_binding(material, current)
            state['active'] = False

        inside(confirm)
        self.assertEqual(closes, [False])
        self.assertIs(core._loans[current.ticket], current)
        self.assertIs(core._loans[material.ticket], material)
        self.assertIn(current.ticket, core._inputs)
        self.assertEqual(sum(name == 'confirm_sdk_publication' for _, name, _ in calls), 1)
        self.assertTrue(core.close_host_current(current))


if __name__ == '__main__':
    unittest.main()
