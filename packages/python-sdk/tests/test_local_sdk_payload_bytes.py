"""Strict owned scalar port; actual Wasm, file, sink and Store ACK are absent."""
import copy
import unittest

from actql_sdk._local_core import (
    LocalCoreError, _Input, _Output, _PUBLICATION_COMMIT_EXPORT_SIGNATURES,
)
import test_local_sdk_read_original as fixture


class SDKPayloadBytePortTests(unittest.TestCase):
    def bridge(self):
        core, clock, first, calls, status = fixture.SDKReadOriginalTests.bridge(self)
        chunk = _Input(core._identity, 5, 29, 9)
        output = _Output(core._identity, 6, 31, 1048576, 'publication_commit_export')
        core._loans.update({5: chunk, 6: output})
        return core, first, chunk, clock, output, calls, status

    def test_closed_signatures_and_exact_original_loans_forward_without_ack(self):
        self.assertEqual({name: _PUBLICATION_COMMIT_EXPORT_SIGNATURES[name]
                          for name in ('prepare_sdk_payload_input', 'produce_sdk_payload_chunk',
                                       'confirm_sdk_payload_chunk', 'produce_sdk_payload_receipt')}, {
            'prepare_sdk_payload_input': ('i64 i32 i32 i32', 'i32'),
            'produce_sdk_payload_chunk': ('i64 i32 i32 i32 i32 i32 i32', 'i32'),
            'confirm_sdk_payload_chunk': ('i64 i32', 'i64'),
            'produce_sdk_payload_receipt': ('i64 i32 i32 i32 i32', 'i32'),
        })
        core, first, chunk, clock, output, calls, status = self.bridge()
        core.prepare_publication_sdk_payload_input(first, clock, 23)
        core.produce_publication_sdk_payload_chunk(output, first, chunk, clock, 23, eof=True)
        status[0] = 8
        self.assertEqual(core.confirm_publication_sdk_payload_chunk(output), 8)
        status[0] = 0
        core.produce_publication_sdk_payload_receipt(output, first, clock, 23)
        self.assertEqual(calls, [
            ('publication_commit_export', 'prepare_sdk_payload_input', (19, 17, 23)),
            ('publication_commit_export', 'produce_sdk_payload_chunk', (31, 19, 29, 17, 1, 23)),
            ('publication_commit_export', 'confirm_sdk_payload_chunk', (31,)),
            ('publication_commit_export', 'produce_sdk_payload_receipt', (31, 19, 17, 23)),
        ])
        self.assertEqual(len(core._loans), 4)

    def test_copies_foreign_inputs_invalid_eof_and_capacity_refuse_before_core(self):
        core, first, chunk, clock, output, calls, _ = self.bridge()
        large = _Input(core._identity, 7, 41, 65537)
        core._loans[7] = large
        for result, original, raw, tick, current, eof in (
            (copy.copy(output), first, chunk, clock, 23, True),
            (output, copy.copy(first), chunk, clock, 23, True),
            (output, first, copy.copy(chunk), clock, 23, True),
            (output, first, chunk, copy.copy(clock), 23, True),
            (first, first, chunk, clock, 23, True),
            (output, first, large, clock, 23, True),
            (output, first, chunk, clock, True, True),
            (output, first, chunk, clock, 0, True),
            (output, first, chunk, clock, 23, 1),
        ):
            with self.assertRaises(ValueError):
                core.produce_publication_sdk_payload_chunk(result, original, raw, tick,
                                                           current, eof=eof)
        self.assertEqual(calls, [])

    def test_denial_expiry_unknown_cleanup_and_boolean_keep_original_custody(self):
        core, first, chunk, clock, output, calls, status = self.bridge()
        operations = (
            lambda: core.prepare_publication_sdk_payload_input(first, clock, 23),
            lambda: core.produce_publication_sdk_payload_chunk(output, first, chunk, clock,
                                                              23, eof=False),
            lambda: core.produce_publication_sdk_payload_receipt(output, first, clock, 23),
        )
        originals = dict(core._loans)
        for operation in operations:
            for code in (-35, -42, -41, -32, -4, -9, -33, 1):
                status[0] = code
                with self.assertRaises(LocalCoreError) as error:
                    operation()
                self.assertEqual(error.exception.code, code)
                self.assertEqual(core._loans, originals)
            for code in (True, False, None, 0.0):
                status[0] = code
                with self.assertRaisesRegex(RuntimeError, 'payload status'):
                    operation()
                self.assertEqual(core._loans, originals)
        self.assertFalse(any(family != 'publication_commit_export' for family, _, _ in calls))

    def test_chunk_confirmation_is_bounded_fact_and_never_permission_or_cancellation(self):
        core, _, _, _, output, calls, status = self.bridge()
        core._closing = True
        for count in (0, 8, 65536, 2**63 - 1):
            status[0] = count
            self.assertEqual(core.confirm_publication_sdk_payload_chunk(output), count)
        for count in (True, False, None, 8.0, 2**63):
            status[0] = count
            with self.assertRaisesRegex(RuntimeError, 'confirmed byte count'):
                core.confirm_publication_sdk_payload_chunk(output)
        status[0] = -9
        with self.assertRaises(LocalCoreError) as error:
            core.confirm_publication_sdk_payload_chunk(output)
        self.assertEqual(error.exception.code, -9)
        self.assertIs(core._loans[output.ticket], output)
        self.assertTrue(all(name == 'confirm_sdk_payload_chunk' for _, name, _ in calls))

    def test_callback_reentry_releasing_original_loan_cannot_return_success(self):
        for target in ('first', 'output', 'chunk', 'clock'):
            core, first, chunk, clock, output, calls, _ = self.bridge()
            original = {'first': first, 'output': output, 'chunk': chunk, 'clock': clock}[target]
            def close_reentry(family, name, *args):
                calls.append((family, name, args))
                del core._loans[original.ticket]
                return 0
            core._call = close_reentry
            with self.assertRaises(ValueError):
                core.produce_publication_sdk_payload_chunk(output, first, chunk, clock,
                                                           23, eof=False)
            self.assertEqual(len(calls), 1)

    def test_multiple_chunk_confirmation_preserves_cumulative_count_and_original_loans(self):
        core, _, _, _, first_output, calls, status = self.bridge()
        second_output = _Output(core._identity, 7, 41, 1048576, 'publication_commit_export')
        core._loans[7] = second_output
        originals = dict(core._loans)
        # The existing sink returns cumulative accepted bytes: a 64 KiB chunk
        # followed by one byte. Input chunk limits do not bound this total.
        status[0] = 65536
        self.assertEqual(core.confirm_publication_sdk_payload_chunk(first_output), 65536)
        status[0] = 65537
        self.assertEqual(core.confirm_publication_sdk_payload_chunk(second_output), 65537)
        self.assertEqual(calls, [
            ('publication_commit_export', 'confirm_sdk_payload_chunk', (31,)),
            ('publication_commit_export', 'confirm_sdk_payload_chunk', (41,)),
        ])
        self.assertEqual(core._loans, originals)
