"""Explicit header custody only; synthetic files are not compiled evidence."""
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('linux_headers',
    Path(__file__).with_name('linux_component_headers.py'))
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class LinuxSystemHeaderTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.include, self.extra = self.root / 'include', self.root / 'uapi'
        self.include.mkdir(); self.extra.mkdir()
        self.header = self.extra / 'types.h'
        self.header.write_bytes(b'Independent original header\n')
        (self.include / 'asm').mkdir()
        self.alias = self.include / 'asm/types.h'
        self.alias.symlink_to('../../uapi/types.h')
        for name, value in [('SYSTEM_INCLUDE', self.include), ('ADDITIONAL_ROOTS', frozenset((self.extra,)))]:
            controller = patch.object(P, name, value)
            controller.start(); self.addCleanup(controller.stop)

    def test_default_does_not_select_available_extra_root_or_fallback(self):
        selected = P.LinuxSystemHeaders()
        self.assertEqual(set(selected.roots), {str(self.include)})
        with self.assertRaisesRegex(ValueError, 'escapes selected roots'):
            selected.capture(self.alias)
        self.assertEqual(selected.aliases, {})

    def test_explicit_root_records_original_alias_target_and_root(self):
        selected = P.LinuxSystemHeaders((self.extra,))
        observed = selected.capture(self.alias)
        self.assertEqual(observed, {'resolved_path': str(self.header), 'bytes': 28,
            'sha256': hashlib.sha256(b'Independent original header\n').hexdigest()})
        receipt = selected.receipt()
        self.assertEqual(set(receipt['roots']), {str(self.include), str(self.extra)})
        original = receipt['aliases'][str(self.alias)]
        self.assertEqual(original['links'][str(self.alias)]['target'], '../../uapi/types.h')
        self.assertEqual(original['target_identity']['st_ino'], str(self.header.stat().st_ino))
        self.assertEqual(receipt['roots'][str(self.extra)]['st_ino'], str(self.extra.stat().st_ino))

    def test_unknown_duplicate_relative_and_broad_roots_refuse(self):
        for roots in ((self.root,), (Path('/'),), (Path('uapi'),), (self.extra, self.extra)):
            with self.subTest(roots=roots), self.assertRaisesRegex(ValueError, 'Unknown or duplicate'):
                P.LinuxSystemHeaders(roots)

    def test_symlink_root_refuses_even_if_selected_name_is_recognized(self):
        original = self.root / 'original'
        self.extra.rename(original); self.extra.symlink_to(original, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'original canonical directory'):
            P.LinuxSystemHeaders((self.extra,))

    def test_root_replacement_after_selection_refuses(self):
        selected = P.LinuxSystemHeaders((self.extra,)); selected.capture(self.alias)
        self.extra.rename(self.root / 'old-root'); self.extra.mkdir()
        (self.extra / 'types.h').write_bytes(b'Independent original header\n')
        with self.assertRaisesRegex(ValueError, 'root changed'):
            selected.receipt()

    def test_alias_retarget_to_equal_bytes_is_not_original(self):
        second = self.extra / 'same.h'; second.write_bytes(self.header.read_bytes())
        selected = P.LinuxSystemHeaders((self.extra,)); selected.capture(self.alias)
        self.alias.unlink(); self.alias.symlink_to('../../uapi/same.h')
        with self.assertRaisesRegex(ValueError, 'header or alias changed'):
            selected.receipt()

    def test_target_replacement_with_equal_bytes_is_not_original(self):
        replacement = self.extra / 'replacement.h'; replacement.write_bytes(self.header.read_bytes())
        selected = P.LinuxSystemHeaders((self.extra,)); selected.capture(self.alias)
        os.replace(replacement, self.header)
        with self.assertRaises(ValueError): selected.receipt()

    def test_target_change_refuses(self):
        selected = P.LinuxSystemHeaders((self.extra,)); selected.capture(self.alias)
        self.header.write_bytes(b'Changed original header\n')
        with self.assertRaisesRegex(ValueError, 'header or alias changed'):
            selected.receipt()

    def test_selected_root_does_not_allow_escaping_or_foreign_alias_spellings(self):
        outside = self.root / 'foreign.h'; outside.write_bytes(b'foreign\n')
        self.alias.unlink(); self.alias.symlink_to(outside)
        selected = P.LinuxSystemHeaders((self.extra,))
        with self.assertRaisesRegex(ValueError, 'escapes selected roots'): selected.capture(self.alias)
        with self.assertRaisesRegex(ValueError, 'Unselected.*spelling'): selected.capture(self.header)

    def test_nested_aliases_are_recorded_and_reverified(self):
        nested = self.include / 'nested'; nested.symlink_to(self.extra, target_is_directory=True)
        selected = P.LinuxSystemHeaders((self.extra,)); selected.capture(nested / 'types.h')
        self.assertEqual(set(selected.receipt()['aliases'][str(nested / 'types.h')]['links']), {str(nested)})
        nested.unlink(); nested.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises((ValueError, FileNotFoundError)): selected.receipt()

    def test_target_side_intermediate_alias_identity_is_retained(self):
        target_directory = self.extra / 'asm'; target_directory.mkdir()
        target_link = target_directory / 'original.h'; target_link.symlink_to('../types.h')
        self.alias.unlink(); self.alias.symlink_to('../../uapi/asm/original.h')
        selected = P.LinuxSystemHeaders((self.extra,)); selected.capture(self.alias)
        original = selected.receipt()['aliases'][str(self.alias)]
        self.assertEqual(set(original['links']), {str(self.alias), str(target_link)})
        self.assertEqual(original['resolved_path'], str(self.header))
        # The final file, bytes and link text stay unchanged, but this is a
        # replacement intermediate link rather than the retained original.
        target_link.unlink(); target_link.symlink_to('../types.h')
        with self.assertRaisesRegex(ValueError, 'header or alias changed'): selected.receipt()

    def test_target_side_escape_cannot_return_via_an_unselected_root(self):
        outside = self.root / 'return.h'; outside.symlink_to(self.header)
        intermediate = self.extra / 'intermediate.h'; intermediate.symlink_to(outside)
        self.alias.unlink(); self.alias.symlink_to(intermediate)
        selected = P.LinuxSystemHeaders((self.extra,))
        with self.assertRaisesRegex(ValueError, 'escapes selected roots'): selected.capture(self.alias)

    def test_target_side_cycle_refuses_boundedly(self):
        first, second = self.extra / 'first.h', self.extra / 'second.h'
        first.symlink_to('second.h'); second.symlink_to('first.h')
        self.alias.unlink(); self.alias.symlink_to(first)
        selected = P.LinuxSystemHeaders((self.extra,))
        with self.assertRaisesRegex(ValueError, 'Cyclic or excessive'): selected.capture(self.alias)

    def test_parent_after_link_cannot_hide_an_outside_kernel_target(self):
        outside = self.root / 'outside'; (outside / 'subdir').mkdir(parents=True)
        unsafe = outside / 'safe.h'; unsafe.write_bytes(b'outside kernel target\n')
        lexical = self.alias.parent / 'safe.h'; lexical.write_bytes(b'local lexical decoy\n')
        pivot = self.alias.parent / 'pivot'; pivot.symlink_to(outside / 'subdir', target_is_directory=True)
        self.alias.unlink(); self.alias.symlink_to('pivot/../safe.h')
        # Independent filesystem oracles, not this recorder's normalization.
        self.assertEqual(self.alias.resolve(strict=True), unsafe)
        self.assertEqual(self.alias.read_bytes(), b'outside kernel target\n')
        selected = P.LinuxSystemHeaders((self.extra,))
        with self.assertRaisesRegex(ValueError, 'escapes selected roots'): selected.capture(self.alias)

    def test_parent_after_selected_link_follows_kernel_order_and_keeps_link(self):
        directory = self.extra / 'deep'; (directory / 'subdir').mkdir(parents=True)
        actual = directory / 'safe.h'; actual.write_bytes(b'selected kernel target\n')
        (self.alias.parent / 'safe.h').write_bytes(b'local lexical decoy\n')
        pivot = self.alias.parent / 'pivot'; pivot.symlink_to(directory / 'subdir', target_is_directory=True)
        self.alias.unlink(); self.alias.symlink_to('pivot/../safe.h')
        self.assertEqual(self.alias.resolve(strict=True), actual)
        self.assertEqual(self.alias.read_bytes(), b'selected kernel target\n')
        selected = P.LinuxSystemHeaders((self.extra,))
        captured = selected.capture(self.alias)
        self.assertEqual(captured['resolved_path'], str(actual))
        self.assertEqual(captured['sha256'], hashlib.sha256(self.alias.read_bytes()).hexdigest())
        self.assertEqual(set(selected.receipt()['aliases'][str(self.alias)]['links']), {str(self.alias), str(pivot)})

    def test_parent_after_regular_file_is_not_a_directory_traversal(self):
        file = self.alias.parent / 'file'; file.write_bytes(b'not a directory\n')
        self.alias.unlink(); self.alias.symlink_to('file/../safe.h')
        with self.assertRaises(NotADirectoryError): self.alias.read_bytes()
        selected = P.LinuxSystemHeaders((self.extra,))
        with self.assertRaisesRegex(ValueError, 'non-directory'): selected.capture(self.alias)

    def test_empty_nonregular_oversized_and_missing_targets_refuse(self):
        selected = P.LinuxSystemHeaders((self.extra,))
        for kind in ('empty', 'directory', 'fifo', 'oversized', 'missing'):
            target = self.extra / kind
            if kind == 'empty': target.touch()
            elif kind == 'directory': target.mkdir()
            elif kind == 'fifo': os.mkfifo(target)
            elif kind == 'oversized':
                with target.open('wb') as output: output.truncate(P.MAXIMUM_HEADER_BYTES + 1)
            alias = self.include / kind; alias.symlink_to(target)
            with self.subTest(kind=kind), self.assertRaises((ValueError, OSError)):
                selected.capture(alias)

    def test_regular_target_with_trailing_slash_or_dot_is_not_a_directory(self):
        for ending in ('/', '/.', '//', '/./'):
            self.alias.unlink(); self.alias.symlink_to('../../uapi/types.h' + ending)
            # Path normalization would erase these directory requirements.
            # The actual kernel open independently rejects every spelling.
            with self.subTest(ending=ending):
                with self.assertRaises(NotADirectoryError): self.alias.read_bytes()
                with self.assertRaisesRegex(ValueError, 'non-directory'):
                    P.LinuxSystemHeaders((self.extra,)).capture(self.alias)

    def test_ordinary_default_header_and_internal_alias_remain_supported(self):
        target = self.include / 'local.h'; target.write_bytes(b'local\n')
        alias = self.include / 'local-alias.h'; alias.symlink_to('local.h')
        selected = P.LinuxSystemHeaders()
        self.assertEqual(selected.capture(alias)['resolved_path'], str(target))
        self.assertEqual(selected.capture(target)['bytes'], 6)
        selected.receipt()


class LinuxHeaderArgumentTests(unittest.TestCase):
    def test_darwin_producers_reject_linux_header_selection_before_build(self):
        scripts = Path(__file__).resolve().parent
        for script, arguments in (
            ('produce-native-crypto-component.py', ['--output', '/unused', '--clang', '/unused']),
            ('produce-python-sqlite-component.py', ['--source', 'a' * 40, '--archive', '/unused',
                '--process-provider', '--clang', '/unused', '--destination', '/unused']),
        ):
            with self.subTest(script=script):
                result = subprocess.run([sys.executable, '-B', str(scripts / script), *arguments,
                    '--system-header-root', '/usr/lib/linux/uapi'], capture_output=True, text=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Additional system-header roots require a Linux', result.stderr)


if __name__ == '__main__':
    unittest.main()
