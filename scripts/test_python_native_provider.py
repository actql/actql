"""Recipe and consumer-object checks; no provider execution or library loading."""
import importlib.util
import hashlib
import subprocess
import sys
import json
from pathlib import Path
import tempfile
import os
import shlex
import re
from types import SimpleNamespace
from unittest.mock import patch
import unittest


SPEC = importlib.util.spec_from_file_location('native_provider',
    Path(__file__).with_name('produce-python-native-provider.py'))
assert SPEC is not None and SPEC.loader is not None
PRODUCER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRODUCER)


class NativeProviderRecipeTests(unittest.TestCase):
    def setUp(self):
        self.lines = ['moonc build-package original.mbt -pkg ' + name
                      + " -target native -o original.core -std-path '$MOON_HOME/lib/core'"
                      + ' -all-pkgs absent-debug-registry.json'
                      for name in sorted(PRODUCER.PACKAGES)]
        self.lines.append('moonc link-core original.core -target native -o entry.c'
                          + ' -all-pkgs absent-debug-registry.json')

    def parse(self, lines=None):
        return PRODUCER.emission_commands('\n'.join(lines or self.lines), Path('/selected/moon'))

    def test_original_closure_and_one_placeholder_only(self):
        commands = self.parse()
        self.assertEqual(len(commands), len(PRODUCER.PACKAGES) + 1)
        self.assertTrue(all(command[0] == '/selected/moon/bin/moonc' for command in commands))
        self.assertEqual(commands[0][commands[0].index('-std-path') + 1], '/selected/moon/lib/core')
        self.assertTrue(all(command[command.index('-all-pkgs') + 1]
                            == 'absent-debug-registry.json' for command in commands))

    def test_other_build_commands_are_not_executed(self):
        self.lines += ['/usr/bin/cc -c original.c', '/usr/bin/cc -o entry.exe original.c']
        self.assertEqual(len(self.parse()), len(PRODUCER.PACKAGES) + 1)

    def test_missing_duplicate_and_foreign_package_are_refused(self):
        for lines in (self.lines[:-2] + self.lines[-1:],
                      [self.lines[0]] + self.lines,
                      [self.lines[0].replace('actql/actql/', 'foreign/')] + self.lines[1:]):
            with self.subTest(lines=lines):
                with self.assertRaisesRegex(ValueError, 'inventory|closure'):
                    self.parse(lines)

    def test_shared_source_publication_owner_is_a_required_selected_dependency(self):
        package = 'actql/actql/client_source_publication'
        self.assertIn(package, PRODUCER.PACKAGES)
        caller = PRODUCER.ROOT / 'src/client_local_host/moon.pkg'
        self.assertIn('"actql/actql/client_source_publication" @source_publication',
                      caller.read_text())
        without_publication = [line for line in self.lines
                               if '-pkg ' + package + ' ' not in line]
        with self.assertRaisesRegex(ValueError, 'inventory'):
            self.parse(without_publication)
        foreign = [line.replace('-pkg ' + package + ' ',
                               '-pkg actql/actql/foreign_source_publication ')
                   for line in self.lines]
        with self.assertRaisesRegex(ValueError, 'closure'):
            self.parse(foreign)

    def test_original_preparation_owner_is_a_required_selected_dependency(self):
        package = 'actql/actql/client_local_preparation'
        self.assertIn(package, PRODUCER.PACKAGES)
        caller = PRODUCER.ROOT / 'src/client_local_host/moon.pkg'
        self.assertIn('"actql/actql/client_local_preparation"', caller.read_text())
        missing = [line for line in self.lines if '-pkg ' + package + ' ' not in line]
        with self.assertRaisesRegex(ValueError, 'inventory'):
            self.parse(missing)
        foreign = [line.replace('-pkg ' + package + ' ',
                               '-pkg actql/actql/foreign_preparation ')
                   for line in self.lines]
        with self.assertRaisesRegex(ValueError, 'closure'):
            self.parse(foreign)

    def test_original_process_owner_is_a_required_selected_dependency(self):
        package = 'actql/actql/platform_native/executor_slot'
        self.assertIn(package, PRODUCER.PACKAGES)
        without_process = [line for line in self.lines if '-pkg ' + package + ' ' not in line]
        with self.assertRaisesRegex(ValueError, 'inventory'):
            self.parse(without_process)
        foreign = [line.replace('-pkg ' + package + ' ',
                               '-pkg actql/actql/foreign_executor_slot ')
                   for line in self.lines]
        with self.assertRaisesRegex(ValueError, 'closure'):
            self.parse(foreign)

    def test_same_process_owner_foreign_c_input_is_selected_once(self):
        selected = ('platform_native/executor_slot/executor_slot_stub.c', 'executor-slot')
        self.assertEqual(PRODUCER.FOREIGN_SOURCES.count(selected), 1)

    def test_ordinary_entry_links_each_real_registration_shim_without_python_initializer(self):
        entry = PRODUCER.ROOT / PRODUCER.ENTRY
        package = (entry / 'moon.pkg').read_text()
        declared = re.search(r'"native-stub"\s*:\s*\[([^]]+)\]', package)
        self.assertIsNotNone(declared)
        ordinary = re.findall(r'"([^\"]+\.c)"', declared.group(1))
        sources = PRODUCER.provider_c_sources(Path('/emitted.c'), Path('/moon'), None,
                                             python_initial_control=False)
        private = [path.name for path, _ in sources if path.parent == entry]
        self.assertEqual(len(private), len(set(private)))
        self.assertEqual(private.count('runtime_initialization_shim.c'), 1)
        self.assertEqual(ordinary, [name for name in private
                                   if name != 'runtime_initialization_shim.c'])
        registrations = re.findall(r'=\s*"(actql_native_control_register_[^\"]+)"',
                                   (entry / 'main_native.mbt').read_text())
        self.assertTrue(registrations)
        for name in registrations:
            definitions = sum(len(re.findall(r'^void ' + re.escape(name) + r'\(',
                                             (entry / path).read_text(), re.MULTILINE))
                              for path in ordinary)
            self.assertEqual(definitions, 1, name)

    def test_private_emission_does_not_duplicate_ordinary_native_stub_commands(self):
        ordinary = 'cc -c src/platform_native/installed_arena_entry/control_shim.c -o /control.o'
        self.assertEqual(self.parse([ordinary] + self.lines), self.parse(self.lines))

    def test_image_adapter_is_separate_in_the_same_single_provider_recipe(self):
        image = PRODUCER.ROOT / 'packages/python-local-runtime/native/pre-root/owned_image.c'
        bootstrap = PRODUCER.ROOT / 'src/platform_native/host_bootstrap/bootstrap_stub.c'
        moon = Path('/selected/moon')
        for allocator in (None, Path('/selected/scoped')):
            for initial in (False, True):
                with self.subTest(allocator=allocator, initial=initial):
                    sources = PRODUCER.provider_c_sources(Path('/emitted.c'), moon,
                        allocator, python_initial_control=initial)
                    self.assertEqual(sources.count((image, 'owned-image')), 1)
                    self.assertEqual(sources.count((bootstrap, 'bootstrap')), 1)
                    self.assertEqual(len({name for _, name in sources}), len(sources))
                    self.assertFalse(any(path.name == 'owned_capacity.c' for path, _ in sources))
                    runtime = allocator if allocator is not None else moon / 'lib/runtime'
                    self.assertEqual([path for path, name in sources if name.startswith('runtime-')],
                        [runtime / (name + '.c') for name in
                         ('backtrace', 'env', 'runtime', 'sync_io', 'utf')])
        self.assertNotIn('owned_image.c', bootstrap.read_text())
        self.assertNotIn('actql_native_owned_capture_image_fd', bootstrap.read_text())
        self.assertNotIn('#include "owned_capacity.c"', image.read_text())
        self.assertNotIn('_Thread_local', image.read_text())

    def test_bootstrap_source_pins_match_separated_adapter(self):
        root = PRODUCER.ROOT
        path = 'src/platform_native/host_bootstrap/bootstrap_stub.c'
        raw = (root / path).read_bytes()
        expected = {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
        manifest = json.loads((root / 'packages/python-local-runtime/native/pre-root/host-bootstrap-source.json').read_bytes())
        entry = next(item for item in manifest['inputs'] if item['path'] == path)
        self.assertEqual(entry, {'path': path, **expected})
        # The Python provider still needs image capture; do not drop its input.
        self.assertEqual(sum(item['path'].endswith('/owned_image.c')
                             for item in manifest['inputs']), 1)
        sqlite = json.loads((root / 'packages/python-local-runtime/native/sqlite-component/source.json').read_bytes())
        self.assertEqual(sqlite['provider_inputs'][path], expected)

    def test_foreign_target_and_unresolved_placeholder_are_refused(self):
        for line in (self.lines[0].replace('-target native', '-target js'),
                     self.lines[0] + ' -i $FOREIGN/original.mi'):
            with self.subTest(line=line):
                with self.assertRaisesRegex(ValueError, 'target|placeholder'):
                    self.parse([line] + self.lines[1:])

    def test_unexpected_compiler_operation_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'operation'):
            self.parse(self.lines + ['moonc run original.core'])

    def test_registry_argument_is_mandatory_for_transitive_traits(self):
        with self.assertRaisesRegex(ValueError, 'registry'):
            self.parse([line.replace(' -all-pkgs absent-debug-registry.json', '')
                        for line in self.lines])

    def test_actual_link_core_without_package_registry_is_preserved(self):
        lines = self.lines[:-1] + [self.lines[-1].replace(
            ' -all-pkgs absent-debug-registry.json', '')]
        commands = self.parse(lines)
        self.assertEqual(len(commands), 165)
        self.assertEqual(commands[-1][1], 'link-core')
        self.assertNotIn('-all-pkgs', commands[-1])
        self.assertTrue(all('-all-pkgs' in c for c in commands[:-1]))

    def registry(self):
        entries = []
        for package in sorted(PRODUCER.PACKAGES):
            rel = package.removeprefix('actql/actql/')
            entries.append({'root': 'actql/actql', 'rel': rel,
                            'artifact': '/metadata/check/' + rel + '/' + Path(rel).name + '.mi'})
        entries.append({'root': 'moonbitlang/core', 'rel': 'builtin',
                        'artifact': '/selected/moon/lib/core/_build/native/release/bundle/builtin/builtin.mi'})
        return {'packages': entries}

    def relocate(self, body):
        return PRODUCER.relocated_registry(json.dumps(body).encode(),
            Path('/metadata/check'), Path('/emission/build'), Path('/selected/moon'))

    def test_registry_relocates_exact_artifact_and_preserves_original_core(self):
        result = json.loads(self.relocate(self.registry()))['packages']
        source = next(p for p in result if p['rel'] == 'source_value')
        self.assertEqual(source['artifact'], '/emission/build/source_value/source_value.mi')
        self.assertEqual(result[-1], self.registry()['packages'][-1])

    def test_registry_refuses_foreign_or_aliased_artifact_and_duplicate(self):
        for patch in ('foreign-root', 'foreign-artifact', 'alias', 'duplicate'):
            body = self.registry()
            if patch == 'foreign-root': body['packages'][0]['root'] = 'foreign/module'
            elif patch == 'foreign-artifact': body['packages'][0]['artifact'] = '/foreign/original.mi'
            elif patch == 'alias': body['packages'][0]['rel'] = 'source_value/../source_value'
            else: body['packages'].append(body['packages'][0].copy())
            with self.subTest(patch=patch), self.assertRaisesRegex(ValueError, 'registry'):
                self.relocate(body)

    def test_registry_refuses_incomplete_selected_closure(self):
        body = self.registry(); body['packages'].pop(0)
        with self.assertRaisesRegex(ValueError, 'closure'):
            self.relocate(body)

    def test_sdk_alias_retains_requested_and_canonical_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            sdk = root / 'selected-sdk'; sdk.mkdir()
            header = sdk / 'real.h'; header.write_bytes(b'original header\n')
            alias = sdk / 'alias.h'; alias.symlink_to('real.h')
            self.assertEqual(PRODUCER.original_dependency(alias, sdk),
                             {'requested_path': str(alias), **PRODUCER.original(header)})
            other = root / 'foreign.h'; other.write_bytes(b'foreign header\n')
            alias.unlink(); alias.symlink_to(other)
            with self.assertRaisesRegex(ValueError, 'escapes original SDK'):
                PRODUCER.original_dependency(alias, sdk)

    def test_non_sdk_source_alias_is_not_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            original = root / 'source.c'; original.write_bytes(b'original source\n')
            alias = root / 'alias.c'; alias.symlink_to(original)
            with self.assertRaisesRegex(ValueError, 'unavailable'):
                PRODUCER.original_dependency(alias, root / 'selected-sdk')


class NativeProviderRegistryCallerTests(unittest.TestCase):
    """Reach the actual build caller before input capture; no compiler runs."""

    def exercise(self, spelling, *, python_initial=False):
        class ReachedInputCapture(Exception):
            pass
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            moon, sdk, destination = root / 'moon', root / 'sdk', root / 'output'
            moon.mkdir(); sdk.mkdir()
            pin = {'moonc': 'selected-compiler', 'moon': 'selected-builder'}
            (root / 'toolchain.json').write_text(json.dumps(pin))
            (moon / 'installed.json').write_text(json.dumps({'pin': pin, 'platform': 'darwin-arm64'}))
            first = root / 'src' / sorted(PRODUCER.PACKAGES)[0].removeprefix('actql/actql/')
            first.mkdir(parents=True); (first / 'original.mbt').write_text('fixture source\n')
            source = '1' * 40
            observed_commands = []
            def command(args, **kwargs):
                observed_commands.append(args)
                output = ''
                if args[:3] == ['git', 'rev-parse', 'HEAD']: output = source + '\n'
                elif args[:2] == ['git', 'status']: pass
                elif args[0] == str(moon / 'bin/moonc'): output = pin['moonc'] + '\n'
                elif args[1] == 'version': output = 'moon ' + pin['moon'] + '\n'
                elif args[1] == 'check' and args[0] == str(moon / 'bin/moon'):
                    check = destination / 'metadata/native/debug/check'
                    check.mkdir(parents=True)
                    entries = []
                    for package in sorted(PRODUCER.PACKAGES):
                        rel = package.removeprefix('actql/actql/')
                        entries.append({'root': 'actql/actql', 'rel': rel,
                            'artifact': str(check / rel / (Path(rel).name + '.mi'))})
                    (check / 'all_pkgs.json').write_text(json.dumps({'packages': entries}))
                elif args[1] == 'build' and args[0] == str(moon / 'bin/moon'):
                    registry = destination / 'emission/native/debug/build/all_pkgs.json'
                    selected = str(registry) if spelling == 'absolute' else os.path.relpath(registry, root)
                    if spelling == 'foreign': selected = str(root / 'foreign/all_pkgs.json')
                    lines = ['moonc build-package original.mbt -pkg ' + package
                        + ' -target native -o original.core -all-pkgs ' + shlex.quote(selected)
                        for package in sorted(PRODUCER.PACKAGES)]
                    lines.append('moonc link-core original.core -target native -o entry.c')
                    output = '\n'.join(lines)
                return SimpleNamespace(stdout=output, stderr='', returncode=0)
            with patch.object(PRODUCER, 'ROOT', root), \
                 patch.object(PRODUCER.platform, 'system', return_value='Darwin'), \
                 patch.object(PRODUCER.platform, 'machine', return_value='arm64'), \
                 patch.object(PRODUCER.subprocess, 'run', side_effect=command), \
                 patch.object(PRODUCER, 'prepare_allocator_source', return_value=(None, {})), \
                 patch.object(PRODUCER, 'prepare_python_initial_component', return_value={
                     'include': '/selected/include', 'sha256': '2' * 64,
                     'runtime': '/selected/derived-runtime.o'}) as initial, \
                 patch.object(PRODUCER, 'original', side_effect=ReachedInputCapture), \
                 patch.object(PRODUCER, 'require_emission_registry', wraps=PRODUCER.require_emission_registry) as gate:
                expected = ValueError if spelling == 'foreign' else ReachedInputCapture
                with self.assertRaises(expected):
                    PRODUCER.build(source, moon, Path('/selected/clang'), sdk, destination, 30,
                                   python_initial_control=python_initial)
                gate.assert_called_once()
                selected_checks = [args for args in observed_commands
                                   if '--python-initial' in args]
                if python_initial:
                    self.assertEqual(len(selected_checks), 1)
                    self.assertEqual(selected_checks[0][-2:], ['--python-initial', '--check'])
                    initial.assert_called_once_with(source, moon, destination)
                else:
                    self.assertEqual(selected_checks, [])
                    initial.assert_not_called()

    def test_actual_builder_accepts_ordinary_relative_registry(self):
        self.exercise('relative')

    def test_actual_builder_preserves_absolute_registry(self):
        self.exercise('absolute')

    def test_actual_builder_refuses_foreign_registry_before_input_capture(self):
        self.exercise('foreign')

    def test_selected_builder_requires_initial_abi_without_changing_default_entrance(self):
        self.exercise('relative', python_initial=True)


@unittest.skipUnless(sys.platform.startswith('linux') and os.environ.get('MOON_HOME'),
                     'Requires Linux tools and an explicit pinned MOON_HOME')
class BootstrapConsumerObjectTests(unittest.TestCase):
    """Actual import object, not selected-provider or installed-runtime acceptance."""

    def test_import_object_has_no_provider_state_and_requires_real_provider(self):
        root = PRODUCER.ROOT
        pre = root / 'packages/python-local-runtime/native/pre-root'
        manifest = json.loads((pre / 'scoped-read-source.json').read_bytes())
        patch_bytes = (pre / manifest['patch']['path']).read_bytes()
        self.assertEqual(hashlib.sha256(patch_bytes).hexdigest(), manifest['patch']['sha256'])
        moon = Path(os.environ['MOON_HOME'])
        selected = next(item for item in manifest['inputs']
                        if item['root'] == 'moonbit' and item['path'] == 'include/moonbit.h')
        self.assertEqual(hashlib.sha256((moon / selected['path']).read_bytes()).hexdigest(),
                         selected['sha256'])
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            # Only declarations are extracted; no target binary/allocator closure
            # is staged, and this does not qualify Linux x86_64 as a provider.
            result = subprocess.run(['git', 'apply', '--no-index', '--include=scoped_read.h', '-'],
                input=patch_bytes, cwd=stage, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            header = (stage / 'scoped_read.h').read_bytes()
            self.assertEqual({'bytes': len(header), 'sha256': hashlib.sha256(header).hexdigest()},
                             manifest['outputs']['scoped_read.h'])
            obj = stage / 'bootstrap.o'
            result = subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-D_GNU_SOURCE',
                '-DACTQL_BOOTSTRAP_IMPORT_PROVIDER', '-DACTQL_SCOPED_READ_ALLOCATOR',
                '-I' + str(moon / 'include'), '-I' + str(stage), '-I' + str(pre), '-fPIC', '-c',
                str(root / 'src/platform_native/host_bootstrap/bootstrap_stub.c'), '-o', str(obj)],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            symbols = subprocess.run(['nm', str(obj)], capture_output=True, text=True,
                                     check=True, timeout=10).stdout
            self.assertIn(' T actql_bootstrap_acquire', symbols)
            self.assertIn(' U actql_native_owned_current', symbols)
            self.assertIn(' U actql_read_context_current', symbols)
            self.assertNotIn('actql_native_owned_capture_image_fd', symbols)
            self.assertNotIn('ordinary_scope', symbols)
            self.assertNotIn('read_current', {line.split()[-1] for line in symbols.splitlines()})
            for line in symbols.splitlines():
                if 'actql_native_owned_' in line or 'actql_read_context_' in line:
                    self.assertEqual(line.split()[0], 'U', line)
            sections = subprocess.run(['readelf', '-SW', str(obj)], capture_output=True,
                                      text=True, check=True, timeout=10).stdout
            self.assertNotIn('.tbss', sections)
            self.assertNotIn('.tdata', sections)
            # No success stub or alternate allocator may satisfy the imports.
            result = subprocess.run([os.environ.get('CC', 'cc'), '-shared',
                '-Wl,--no-undefined', str(obj), '-o', str(stage / 'missing-provider.so')],
                capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('actql_native_owned_current', result.stderr)


if __name__ == '__main__':
    unittest.main()
