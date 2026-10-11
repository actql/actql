"""Fixture cleanup ordering only; not actual Wasm or public Run acceptance."""
import ast
from pathlib import Path
import unittest


class NativeFixtureInputCustodyTests(unittest.TestCase):
    def bridge(self):
        path = Path(__file__).resolve().parents[3] / 'scripts/fixtures/python-local-native-result-abi.py'
        tree = ast.parse(path.read_text())
        functions = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'call']
        self.assertEqual(len(functions), 1)
        calls = []
        state = {'reserve': 23, 'owner_close': 0, 'input_close': 0}

        class Fixture:
            store = object()
            nonce = 7

            def __init__(self):
                self.exports = {}
                for family, reserve, close in (
                        ('source_publication', 'reserve', 'close'),
                        ('publication', 'reserve', 'close'),
                        ('run', 'install_configuration', 'close_configuration')):
                    self.exports['actql_' + family + '_' + reserve] = self.reserve
                    self.exports['actql_' + family + '_' + close] = self.close

            def reserve(self, store, nonce, *args):
                calls.append(('reserve', args))
                return state['reserve']

            def close(self, store, nonce, *args):
                calls.append(('owner_close', args))
                return state['owner_close']

            def call(self, name, handle):
                calls.append(('input_close', (handle,)))
                return state['input_close']

        namespace = {'fixture': Fixture(), 'projection_inputs': {}}
        exec(compile(ast.Module(body=functions, type_ignores=[]), str(path), 'exec'), namespace)
        return namespace['call'], namespace['projection_inputs'], calls, state

    def test_each_original_owner_closes_before_its_exact_input(self):
        for family, reserve, close, args in (
                ('source_publication', 'reserve', 'close', (17, 11, 9, 131200)),
                ('publication', 'reserve', 'close', (17, 11, 9, 2097200)),
                ('run', 'install_configuration', 'close_configuration', (11,))):
            call, inputs, calls, _ = self.bridge()
            self.assertEqual(call(family, reserve, *args), 23)
            self.assertEqual(inputs, {(family, 23): 11})
            self.assertEqual(call(family, close, 23), 0)
            self.assertEqual(calls[-2:], [('owner_close', (23,)), ('input_close', (11,))])
            self.assertEqual(inputs, {})

    def test_pending_parent_keeps_input_without_cleanup_or_new_admission(self):
        call, inputs, calls, state = self.bridge()
        call('publication', 'reserve', 17, 11, 9, 2097200)
        for code in (-9, -33, -2):
            state['owner_close'] = code
            self.assertEqual(call('publication', 'close', 23), code)
            self.assertEqual(inputs, {('publication', 23): 11})
        self.assertFalse(any(name == 'input_close' for name, _ in calls))
        self.assertEqual(sum(name == 'reserve' for name, _ in calls), 1)

    def test_input_cleanup_failure_is_not_reported_as_success(self):
        call, inputs, _, state = self.bridge()
        call('source_publication', 'reserve', 17, 11, 9, 131200)
        state['input_close'] = -9
        with self.assertRaisesRegex(AssertionError, 'Fixture input cleanup'):
            call('source_publication', 'close', 23)
        self.assertEqual(inputs, {('source_publication', 23): 11})

    def test_failed_reservation_cannot_create_cleanup_custody(self):
        call, inputs, calls, state = self.bridge()
        state['reserve'] = -4
        self.assertEqual(call('publication', 'reserve', 17, 11, 9, 2097200), -4)
        self.assertEqual(inputs, {})
        self.assertFalse(any(name == 'input_close' for name, _ in calls))
