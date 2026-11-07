"""Independent declaration mutations fail at the named source boundary."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


WASM = load('wasm_binding', ROOT / 'scripts/generate-local-wasm-abi.py')
NATIVE = load('native_binding', ROOT / 'scripts/generate-local-native-runtime-binding.py')


class BindingMutationTests(unittest.TestCase):
    def test_scalar_width_and_same_type_order_change_generated_binding(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in [ROOT / 'src/client_host_wasm/moon.pkg',
                         *sorted((ROOT / 'src/client_host_wasm').glob('*.mbt')),
                         ROOT / 'src/physical_resources/imported_child_ledger_wasm.mbt',
                         ROOT / 'src/physical_resources/platform_vm_capacity_wasm.mbt']:
                target = root / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
            path = root / 'src/client_host_wasm/buffers.mbt'
            old = path.read_text()
            baseline = WASM.render(root)
            self.assertEqual(baseline, WASM.render())
            for before, after in [('start : Int, count : Int', 'count : Int, start : Int'),
                                  ('start : Int, count : Int', 'start : Int64, count : Int')]:
                self.assertIn(before, old)
                path.write_text(old.replace(before, after, 1))
                self.assertNotEqual(WASM.render(root), baseline)
            path.write_text(old.replace('start : Int, count : Int', 'start : String, count : Int', 1))
            with self.assertRaisesRegex(ValueError, 'parameter declaration'):
                WASM.render(root)

    def test_journal_buffer_imports_require_complete_original_borrow_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in [ROOT / 'src/client_host_wasm/moon.pkg',
                         *sorted((ROOT / 'src/client_host_wasm').glob('*.mbt')),
                         ROOT / 'src/physical_resources/imported_child_ledger_wasm.mbt',
                         ROOT / 'src/physical_resources/platform_vm_capacity_wasm.mbt']:
                target = root / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
            path = root / 'src/client_host_wasm/journal_observation.mbt'
            original = path.read_text()
            baseline = WASM.render(root)
            self.assertEqual(baseline, WASM.render())
            borrow = '#borrow(namespace_buffer, key_buffer, header_buffer)'
            self.assertEqual(original.count(borrow), 1)
            mutations = [
                ('missing', original.replace(borrow, '', 1)),
                ('partial', original.replace(borrow, '#borrow(namespace_buffer, key_buffer)', 1)),
                ('wrong-name', original.replace(borrow, '#borrow(namespace_buffer, key_buffer, other)', 1)),
                ('duplicate-name', original.replace(borrow,
                    '#borrow(namespace_buffer, key_buffer, header_buffer, header_buffer)', 1)),
                ('duplicate-annotation', original.replace(borrow, borrow + '\n' + borrow, 1)),
                ('comment', original.replace(borrow, '// ' + borrow, 1)),
                ('block-comment', original.replace(borrow, '/* ' + borrow + ' */', 1)),
                ('raw-literal', original.replace(borrow, 'let fake_borrow =\n  #|' + borrow, 1)),
                ('quoted-literal', original.replace(borrow, 'let fake_borrow = "' + borrow + '"', 1)),
                ('missing-layout-declaration', original.replace('#unsafe_skip_stub_check', '', 1)),
                ('wrong-element', original.replace('header_buffer : FixedArray[Byte]',
                                                   'header_buffer : FixedArray[Int]', 1)),
                ('immutable-output', original.replace('header_buffer : FixedArray[Byte]',
                                                      'header_buffer : Bytes', 1)),
                ('wrong-local-symbol', original.replace('fn physical_journal_query_header(',
                                                        'fn foreign_journal_query_header(', 1)),
                ('unknown-import', original.replace('"actql_host" "journal_query_header"',
                                                    '"actql_host" "foreign_query_header"', 1)),
                ('copy-borrow-missing', original.replace('#borrow(key_buffer, body_buffer)', '', 1)),
                ('copy-borrow-partial', original.replace('#borrow(key_buffer, body_buffer)',
                                                        '#borrow(key_buffer)', 1)),
                # The exact old bug must fail even if every machine scalar
                # signature still matches and annotations name those scalars.
                ('all-buffers-reverted-to-int', original
                    .replace('namespace_buffer : Bytes', 'namespace_buffer : Int')
                    .replace('key_buffer : Bytes', 'key_buffer : Int')
                    .replace('header_buffer : FixedArray[Byte]', 'header_buffer : Int')
                    .replace('key_buffer : FixedArray[Byte]', 'key_buffer : Int')
                    .replace('body_buffer : FixedArray[Byte]', 'body_buffer : Int')),
                ('typed-arbitrary-import', original.replace(
                    'fn physical_journal_current(ticket : Int)',
                    'fn physical_journal_current(ticket : Bytes)', 1)),
                ('typed-export', original.replace('physical_ticket : Int,',
                                                  'physical_ticket : Bytes,', 1)),
            ]
            for name, modified in mutations:
                with self.subTest(name=name):
                    self.assertNotEqual(modified, original)
                    path.write_text(modified)
                    with self.assertRaisesRegex(ValueError, 'borrowed ABI|scalar ABI parameter'):
                        WASM.render(root)
            path.write_text(original)
            moved = path.with_name('foreign_journal_observation.mbt')
            path.rename(moved)
            with self.assertRaisesRegex(ValueError, 'Foreign original borrowed ABI'):
                WASM.render(root)
            moved.rename(path)
            self.assertEqual(WASM.render(root), baseline)
            self.assertIn("'journal_query_header': ('i32 i32 i32 i32 i32 i32 i32', 'i32')", baseline)
            self.assertIn("'journal_copy_row': ('i32 i32 i32 i32 i32', 'i32')", baseline)

    def test_export_map_matches_actual_public_declarations(self):
        declared = WASM.package_wasm_exports(ROOT / 'src/client_host_wasm/moon.pkg')
        self.assertEqual(len(declared), len(set(declared.values())))
        self.assertEqual(declared['host_abi_version'], 'actql_host_abi_version')
        self.assertTrue(all(symbol.startswith('actql_') for symbol in declared.values()))
        self.assertEqual(WASM.render(), WASM.OUTPUT.read_text())

    def test_export_map_rejects_ambiguous_or_executable_configuration(self):
        valid = 'options(link: {"wasm": {"exports": ["entry:actql_entry"]}})\n'
        cases = [
            valid.replace('["entry:actql_entry"]', '[]'),
            valid.replace('["entry:actql_entry"]', '["entry:actql_entry", "entry:actql_other"]'),
            valid.replace('["entry:actql_entry"]', '["entry:actql_entry", "other:actql_entry"]'),
            valid.replace('["entry:actql_entry"]', '["entry"]'),
            valid.replace('["entry:actql_entry"]', '[load_exports()]'),
            valid.replace('["entry:actql_entry"]', '["entry:actql_entry"] + extra()'),
            valid.replace('"exports": [', '"exports": [], "exports": ['),
            valid + valid,
            'other(' + valid.strip() + ')',
            'fn invalid() { ' + valid.strip() + ' }',
            '/* ' + valid + ' */\n',
            'let decoy = ' + __import__('json').dumps(valid) + '\n',
            valid.replace('"wasm"', '"js"'),
        ]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'moon.pkg'
            for text in cases:
                with self.subTest(text=text):
                    path.write_text(text)
                    with self.assertRaises(ValueError):
                        WASM.package_wasm_exports(path)
            path.write_text('// options(fake())\n/* nested /* options() */ comment */\n' + valid)
            self.assertEqual(WASM.package_wasm_exports(path), {'entry': 'actql_entry'})

    def test_export_map_requires_bijection_and_preserves_alias_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in [ROOT / 'src/client_host_wasm/moon.pkg',
                         *sorted((ROOT / 'src/client_host_wasm').glob('*.mbt')),
                         ROOT / 'src/physical_resources/imported_child_ledger_wasm.mbt',
                         ROOT / 'src/physical_resources/platform_vm_capacity_wasm.mbt']:
                target = root / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
            path = root / 'src/client_host_wasm/moon.pkg'
            original = path.read_text()
            entry = '"host_abi_version:actql_host_abi_version",'
            self.assertEqual(original.count(entry), 1)
            for modified in [original.replace(entry, ''),
                             original.replace('host_abi_version:actql_host_abi_version',
                                              'missing_function:actql_host_abi_version')]:
                path.write_text(modified)
                with self.assertRaisesRegex(ValueError, 'declaration'):
                    WASM.render(root)
            # The name is part of the independent ABI, not an interchangeable
            # integer signature. A different symbol cannot remain fresh.
            path.write_text(original.replace('host_abi_version:actql_host_abi_version',
                                             'host_abi_version:actql_buffer_foreign_alias'))
            self.assertNotEqual(WASM.render(root), WASM.render())

    def test_export_declarations_cannot_be_supplied_by_comments_or_literals(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in [ROOT / 'src/client_host_wasm/moon.pkg',
                         *sorted((ROOT / 'src/client_host_wasm').glob('*.mbt')),
                         ROOT / 'src/physical_resources/imported_child_ledger_wasm.mbt',
                         ROOT / 'src/physical_resources/platform_vm_capacity_wasm.mbt']:
                target = root / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
            path = root / 'src/client_host_wasm/version.mbt'
            original = path.read_text()
            for fake in ['/*' + original + '*/',
                         '// absent real version declaration\n' + '\n'.join('#|' + line for line in original.splitlines()),
                         'let decoy : String = ' + __import__('json').dumps(original.replace('\n', ' '))]:
                path.write_text(fake)
                with self.assertRaisesRegex(ValueError, 'Missing ABI export declarations'):
                    WASM.render(root)
            path.write_text(original)
            self.assertEqual(WASM.render(root), WASM.render())

    def test_reserve_wrapper_keeps_real_cleanup_after_shared_admission(self):
        source = (ROOT / 'src/client_host_wasm/buffers.mbt').read_text()
        expected = '''{
  guard selected(nonce) is Some(value) else { return -1 }
  let admission = reserve_input_admission(value, physical_input)
  if admission != 0 {
    return admission
  }
  match @buffers.reserve_buffer(value.pool, wire_bytes, physical_copy_bytes, () => {
    physical_input_cleanup(physical_input) == 0
  }) {
    Err(issue) => issue_code(issue)
    Ok(slot) => {
      let handle = value.next_handle
      value.next_handle += 1
      value.copies[handle] = (slot, physical_input)
      handle
    }
  }
}'''
        def body(text, anchor="pub fn reserve("):
            code = WASM.declaration_source(text)
            self.assertEqual(code.count(anchor), 1)
            begin = code.index('{', code.index(anchor))
            depth = 0
            for end in range(begin, len(code)):
                depth += (code[end] == '{') - (code[end] == '}')
                if depth == 0:
                    return ''.join(code[begin:end + 1].split())
            self.fail('Unclosed reserve wrapper')
        self.assertEqual(body(source), ''.join(expected.split()))
        start = source.index('pub fn reserve(')
        end = source.index('\n///|', start)
        wrapper = source[start:end]
        for before, after in [
            ('reserve_input_admission(value, physical_input)', 'reserve_input_admission(value, 1)'),
            ('selected(nonce)', 'selected(1L)'),
            ('if admission != 0', 'if false'),
            ('physical_input_cleanup(physical_input)', 'physical_input_cleanup(1)'),
            ('physical_input_cleanup(physical_input) == 0', 'true'),
            ('let admission = reserve_input_admission',
             'physical_input_cleanup(physical_input) |> ignore\n  let admission = reserve_input_admission'),
            ('value.copies[handle] = (slot, physical_input)', 'value.copies[handle] = (slot, 1)'),
        ]:
            with self.subTest(before=before):
                self.assertEqual(wrapper.count(before), 1)
                mutated = source[:start] + wrapper.replace(before, after, 1) + source[end:]
                self.assertNotEqual(body(mutated), ''.join(expected.split()))
        code = WASM.declaration_source(source)
        self.assertNotIn('pub fn reserve_input_admission', code)
        admission_expected = '''{
  if value.closing { return -5 }
  if physical_input <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_input) ||
    value.native_commands.values().any(command => command.physical_ticket == physical_input) ||
    value.result_chunks.values().any(chunk => chunk.physical_ticket == physical_input) ||
    value.workspaces.values().any(pair => pair.0 == physical_input) {
    return -3
  }
  0
}'''
        admission_anchor = 'fn reserve_input_admission('
        self.assertEqual(body(source, admission_anchor), ''.join(admission_expected.split()))
        for before, after in [('value.closing', 'false'),
                              ('physical_input <= 0', 'false'),
                              ('value.next_handle == 2147483647', 'false'),
                              ('pair.1 == physical_input', 'false'),
                              ('return -5', 'return -3')]:
            begin = source.index(admission_anchor)
            end = source.index('\n///|', begin)
            admission = source[begin:end]
            self.assertEqual(admission.count(before), 1)
            mutated = source[:begin] + admission.replace(before, after, 1) + source[end:]
            self.assertNotEqual(body(mutated, admission_anchor), ''.join(admission_expected.split()))

    def test_native_shim_same_type_output_swap_is_not_fresh(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in [NATIVE.DECLARATION, NATIVE.ENTRY / 'main_native.mbt',
                         NATIVE.ENTRY / 'packaged_runtime_shim.c']:
                target = root / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
            baseline = NATIVE.outputs(root)
            self.assertEqual(baseline, NATIVE.outputs())
            path = root / 'src/platform_native/installed_arena_entry/packaged_runtime_shim.c'
            old = path.read_text()
            # Both inputs are uint16 pointer/count pairs; width checks alone
            # cannot distinguish these independently meaningful roles.
            before = 'const uint16_t *source, int32_t source_units,\n    const uint16_t *platform, int32_t platform_units'
            self.assertIn(before, old)
            path.write_text(old.replace(before, 'const uint16_t *platform, int32_t platform_units,\n    const uint16_t *source, int32_t source_units', 1))
            with self.assertRaisesRegex(ValueError, 'parameter binding changed'):
                NATIVE.outputs(root)

    def test_original_moon_callback_mismatch_refuses(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in [NATIVE.DECLARATION, NATIVE.ENTRY / 'main_native.mbt',
                         NATIVE.ENTRY / 'packaged_runtime_shim.c']:
                target = root / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
            path = root / 'src/platform_native/installed_arena_entry/main_native.mbt'
            path.write_text(path.read_text().replace('register_original_packaged_runtime_roots(',
                                                     'foreign_runtime_roots(', 1))
            with self.assertRaisesRegex(ValueError, 'MoonBit Runtime callback'):
                NATIVE.outputs(root)


if __name__ == '__main__':
    unittest.main()
