"""Composition checks only; no compiler, runtime, allocation or capacity grant."""
import importlib.util
from pathlib import Path
import shlex
import json
import tempfile
import unittest
import subprocess
import sys
import os
import platform
import shutil

SPEC = importlib.util.spec_from_file_location('remote_build', Path(__file__).with_name('produce-native-remote-scoped-runtime.py'))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RemoteScopedComposition(unittest.TestCase):
    def setUp(self):
        self.home = Path('/selected/moon')
        self.emission = Path('/owned/emission')
        self.stage = Path('/owned/derived-read-source')
        self.clang = Path('/selected/clang')
        self.sdk = Path('/selected/sdk')
        self.source = 'a' * 40
        self.header = Path('/owned/resident-initial-control.h')
        self.core = self.emission / 'native/release/build/cmd/native_remote_resident_site/native_remote_resident_site.c'
        self.exe = self.core.with_suffix('.exe')
        self.commands = [
            ['moonc', 'build-package', '-target', 'native', '-pkg',
             'actql/actql/cmd/native_remote_resident_site', '-o', str(self.emission / 'entry.core')],
            ['moonc', 'link-core', '-target', 'native', '-o', str(self.core)],
            ['/usr/bin/cc', '-o', str(self.emission / 'bootstrap.o'), '-I$MOON_HOME/include',
             '-c', './src/platform_native/host_bootstrap/bootstrap_stub.c'],
            ['/usr/bin/cc', '-o', str(self.emission / 'entry.o'), '-I$MOON_HOME/include',
             '-c', './src/cmd/native_remote_resident_site/initial_control_stub.c'],
            *[['/usr/bin/cc', '-o', str(self.emission / (name + '.o')), '-I$MOON_HOME/include',
               '-c', '$MOON_HOME/lib/runtime/' + name + '.c'] for name in sorted(MODULE.RUNTIME_NAMES)],
            ['/usr/bin/cc', '-o', str(self.exe), '-I$MOON_HOME/include', str(self.core),
             '$MOON_HOME/lib/libmoonbitrun.o', '-lm'],
        ]

    def plan(self, commands=None):
        return MODULE.commands_for('\n'.join(shlex.join(c) for c in (self.commands if commands is None else commands)),
                                   self.home, self.emission, self.stage, self.clang, self.sdk,
                                   source_sha=self.source, resident_control_header=self.header)

    def test_resident_entry_is_required_once_and_pinned_in_its_original_c_step(self):
        plan = self.plan()
        selected = [c for c in plan if any(x.startswith('-DACTQL_RESIDENT_INITIAL_CONTROL_HEADER=') for x in c)]
        self.assertEqual(len(selected), 1)
        self.assertIn('./src/cmd/native_remote_resident_site/initial_control_stub.c', selected[0])
        self.assertIn('-DACTQL_RESIDENT_INITIAL_CONTROL_HEADER="' + str(self.header) + '"', selected[0])
        step = next(c for c in self.commands if './src/cmd/native_remote_resident_site/initial_control_stub.c' in c)
        for commands in ([c for c in self.commands if c is not step], self.commands + [step]):
            with self.subTest(commands=len(commands)), self.assertRaisesRegex(ValueError, 'Resident initial-control entrance'):
                self.plan(commands)

    def test_resident_recipe_requires_a_frozen_source_and_owned_header(self):
        output = '\n'.join(shlex.join(c) for c in self.commands)
        for source, header in ((None, self.header), ('not-a-source', self.header),
                               (self.source, None), (self.source, Path('/foreign/control.h'))):
            with self.subTest(source=source, header=header), self.assertRaisesRegex(ValueError, 'Resident source'):
                MODULE.commands_for(output, self.home, self.emission, self.stage,
                                    self.clang, self.sdk, source_sha=source,
                                    resident_control_header=header)

    def test_private_recipe_header_binds_source_and_exact_original_recipe(self):
        import hashlib
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'control.h'
            record = MODULE.resident_initial_control_header(self.source, path)
            self.assertEqual(record['source'], self.source)
            self.assertEqual(record['recipeSha256'], hashlib.sha256((MODULE.ROOT / MODULE.RESIDENT_RECIPE).read_bytes()).hexdigest())
            self.assertIn('#define ACTQL_RESIDENT_SOURCE_SHA "' + self.source + '"', path.read_text())
            self.assertFalse(record['permission'])
            self.assertFalse(record['physicalAcquired'])
            with self.assertRaises(FileExistsError):
                MODULE.resident_initial_control_header(self.source, path)

    def test_same_header_runtime_and_single_provider(self):
        planned = self.plan()
        c = [p for p in planned if p[0] == str(self.clang)]
        for command in c:
            self.assertLess(command.index('-I' + str(self.stage)), command.index('-I' + str(self.home / 'include')))
            self.assertIn('-DACTQL_SCOPED_READ_ALLOCATOR', command)
        provider = [p for p in c if any(x.startswith('-DACTQL_SCOPED_READ_PROVIDER=') for x in p)]
        self.assertEqual(len(provider), 1)
        self.assertIn('./src/platform_native/host_bootstrap/bootstrap_stub.c', provider[0])
        runtime = {Path(x).name for p in c for x in p if x.startswith(str(self.stage)) and x.endswith('.c')}
        self.assertEqual(runtime, {name + '.c' for name in MODULE.RUNTIME_NAMES})
        self.assertFalse(any(str(self.home / 'lib/runtime') in x for p in planned for x in p))
        exports = ['-Wl,-exported_symbol,_' + symbol
                   for symbol in MODULE.LOCAL_COMPONENT_PROVIDER_EXPORTS]
        self.assertEqual(planned[-1][-len(exports):], exports)
        self.assertEqual(planned[-1][:-len(exports)][-2:],
                         [str(self.home / 'lib/libmoonbitrun.o'), '-lm'])

    def test_original_debug_registry_and_compiler_arguments_are_preserved(self):
        commands = [c.copy() for c in self.commands]
        commands[0] += ['-g', '-O0', '-all-pkgs', str(self.emission / 'all_pkgs.json')]
        planned = self.plan(commands)
        self.assertEqual(planned[0][1:], commands[0][1:])

    def test_private_driver_selects_only_the_planned_c_boundary(self):
        driver = Path('/owned/bin/cc')
        commands = [[str(driver), *c[1:]] if c[0] == '/usr/bin/cc' else c for c in self.commands]
        output = '\n'.join(shlex.join(c) for c in commands)
        plan = MODULE.commands_for(output, self.home, self.emission, self.stage,
                                   self.clang, self.sdk, cc_driver=driver,
                                   source_sha=self.source, resident_control_header=self.header)
        self.assertEqual(plan, self.plan())

    def test_actual_moon_archive_flags_are_preserved(self):
        archive = ['/owned/bin/ar', '-r', '-c', '-s',
                   str(self.emission / 'liboriginal.a'), str(self.emission / 'original.o')]
        output = '\n'.join(shlex.join(c) for c in self.commands + [archive])
        plan = MODULE.commands_for(output, self.home, self.emission, self.stage,
                                   self.clang, self.sdk, ar_driver=Path('/owned/bin/ar'),
                                   source_sha=self.source, resident_control_header=self.header)
        self.assertEqual(plan[-1], archive)

    def release_archive_plan(self, archive):
        output = '\n'.join(shlex.join(c) for c in self.commands + [archive])
        return MODULE.commands_for(output, self.home, self.emission, self.stage,
                                   self.clang, self.sdk, ar_driver=Path('/owned/bin/ar'),
                                   source_sha=self.source, resident_control_header=self.header)

    def release_archive(self):
        return ['/owned/bin/ar', '-r', '-c', '-s',
                str(self.emission / 'native/release/build/libruntime-original.a'),
                *[str(self.emission / ('runtime-' + name + '.o'))
                  for name in sorted(MODULE.RUNTIME_NAMES)],
                str(self.home / 'lib/moonbit_simdutf.o'), str(self.home / 'lib/simdutf.o')]

    def test_release_runtime_keeps_the_original_pinned_utf_objects(self):
        archive = self.release_archive()
        self.assertEqual(self.release_archive_plan(archive)[-1], archive)

    def test_release_runtime_refuses_a_foreign_utf_object(self):
        archive = self.release_archive()
        archive[-1] = '/foreign/simdutf.o'
        with self.assertRaisesRegex(ValueError, 'Foreign archive input'):
            self.release_archive_plan(archive)

    def test_pinned_utf_objects_cannot_be_added_to_an_ffi_archive(self):
        archive = self.release_archive()
        archive[4] = str(self.emission / 'native/release/build/platform_native/sqlite/libsqlite.a')
        with self.assertRaisesRegex(ValueError, 'Foreign archive input'):
            self.release_archive_plan(archive)

    def test_release_runtime_refuses_missing_or_duplicate_utf_objects(self):
        original = self.release_archive()
        for archive in (original[:-1], original + [original[-1]]):
            with self.subTest(archive=archive), self.assertRaisesRegex(ValueError, 'Foreign archive input'):
                self.release_archive_plan(archive)

    def test_only_observed_source_path_absolutization_is_equivalent(self):
        relative = ['./src/platform_native/filesystem/filesystem_stub.c', '-o', './src/result.o', '-O0']
        absolute = [str(MODULE.ROOT / relative[0]), *relative[1:]]
        self.assertEqual(MODULE.canonical_c_arguments(relative), absolute)
        self.assertEqual(MODULE.canonical_c_arguments(['/foreign/input.c', '-O2']), ['/foreign/input.c', '-O2'])
        self.assertNotEqual(MODULE.canonical_c_arguments(relative),
                            MODULE.canonical_c_arguments([relative[0], '-o', './src/result.o', '-O2']))

    def test_inside_checkout_outputs_and_exact_drivers_keep_the_same_selection(self):
        original_root = MODULE.ROOT
        MODULE.ROOT = Path('/owned')
        self.addCleanup(setattr, MODULE, 'ROOT', original_root)
        driver = Path('/owned/bin/cc')
        commands = [[str(driver), *c[1:]] if c[0] == '/usr/bin/cc' else c
                    for c in self.commands]
        relative = [[p.replace('/owned/', './') if p.startswith('/owned/') else p
                     for p in command] for command in commands]
        selected = MODULE.commands_for('\n'.join(shlex.join(c) for c in relative),
            self.home, self.emission, self.stage, self.clang, self.sdk,
            cc_driver=driver, source_sha=self.source, resident_control_header=self.header)
        self.assertEqual(selected, self.plan())
        self.assertEqual(MODULE.canonical_c_arguments(
            ['-o', './emission/test.o', './src/original.c'], self.emission),
            ['-o', '/owned/emission/test.o', '/owned/src/original.c'])
        with self.assertRaisesRegex(ValueError, 'escapes'):
            self.plan([[*self.commands[0][:-1], './emission/../foreign.core'],
                       *self.commands[1:]])

    def test_private_c_port_rejects_unplanned_invocation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'plan.json'
            path.write_text(json.dumps({'steps': []}))
            with self.assertRaisesRegex(ValueError, 'Unplanned'):
                MODULE.compile_selected_c(path, ['--arbitrary'])

    def test_actual_private_cc_driver_import_needs_no_release_parser_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = root / 'plan.json'
            plan.write_text(json.dumps({'steps': []}))
            script = ('import importlib.util,sys\n'
                      'from pathlib import Path\n'
                      's=importlib.util.spec_from_file_location("selected_cc",sys.argv[1])\n'
                      'm=importlib.util.module_from_spec(s);s.loader.exec_module(m)\n'
                      'try:m.compile_selected_c(Path(sys.argv[2]),["--unplanned"])\n'
                      'except ValueError as e:print(str(e))\n')
            result = subprocess.run([sys.executable, '-I', '-c', script,
                                     str(Path(MODULE.__file__)), str(plan)],
                                    cwd=root, env={**os.environ, 'PYTHONPATH': ''},
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'Unplanned or ambiguous C compiler invocation')

    def test_private_c_port_rechecks_allocator_before_compiler(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            header = root / 'header.h'
            header.write_text('original')
            expected = MODULE.original(header)
            header.write_text('changed')
            path = root / 'plan.json'
            path.write_text(json.dumps({'steps': [{'original': ['expected']}],
                                        'allocator_inputs': [expected]}))
            with self.assertRaisesRegex(ValueError, 'changed'):
                MODULE.compile_selected_c(path, ['expected'])

    def test_second_core_cannot_split_owner_identity(self):
        with self.assertRaisesRegex(ValueError, 'composition'):
            self.plan(self.commands + [self.commands[1]])

    def test_missing_or_duplicate_provider_refuses(self):
        for commands in (self.commands[:2] + self.commands[3:], self.commands + [self.commands[2]]):
            with self.assertRaisesRegex(ValueError, 'composition'):
                self.plan(commands)

    def test_missing_or_duplicate_runtime_refuses(self):
        for commands in (self.commands[:3] + self.commands[4:], self.commands + [self.commands[3]]):
            with self.assertRaises(ValueError):
                self.plan(commands)

    def test_foreign_entry_refuses(self):
        commands = [c.copy() for c in self.commands]
        commands[1][-1] = str(self.emission / 'foreign.c')
        with self.assertRaisesRegex(ValueError, 'Core'):
            self.plan(commands)

    def test_output_escape_refuses(self):
        commands = [c.copy() for c in self.commands]
        commands[2][2] = '/foreign/output.o'
        with self.assertRaisesRegex(ValueError, 'escapes'):
            self.plan(commands)

    def test_unresolved_placeholder_and_foreign_ffi_refuse(self):
        commands = [c.copy() for c in self.commands]
        commands[2][-1] = '$UNSELECTED/source.c'
        with self.assertRaisesRegex(ValueError, 'placeholder'):
            self.plan(commands)
        commands[2][-1] = '/foreign/source.c'
        with self.assertRaisesRegex(ValueError, 'FFI'):
            self.plan(commands)

    def test_non_native_or_execution_command_refuses(self):
        commands = [c.copy() for c in self.commands]
        commands[0][3] = 'js'
        with self.assertRaisesRegex(ValueError, 'target'):
            self.plan(commands)
        commands = self.commands + [[str(self.exe), '-o', str(self.emission / 'not-a-build')]]
        with self.assertRaisesRegex(ValueError, 'tool'):
            self.plan(commands)


    def test_resident_component_header_keeps_the_original_arena(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'control.h'
            record = MODULE.resident_initial_control_header(self.source, path)
            text = path.read_text()
            self.assertIn('#define ACTQL_RESIDENT_SQLITE_HEAP 33554432\n', text)
            self.assertIn('#define ACTQL_RESIDENT_CRYPTO_HEAP 16777216\n', text)
            self.assertIn('#define ACTQL_RESIDENT_DIAGNOSTIC_BYTES 2048\n', text)
            self.assertEqual(record['selected']['capacityBytes'], 268435456)
            self.assertEqual(record['selected']['controlEnvelopeBytes'], 16777216)
            self.assertNotIn('ACTQL_BUNDLE_MANAGED_PAYLOAD', text)
            self.assertFalse(record['permission'])
            self.assertFalse(record['physicalAcquired'])

    def test_resident_component_selection_refuses_noncoexisting_or_unaligned_heaps(self):
        original_root = MODULE.ROOT
        recipe = json.loads((original_root / MODULE.ENTRY / 'initial_control_recipe.json').read_text())
        for changed in [dict(sqliteHeapBytes=recipe['capacityBytes']), dict(cryptoHeapBytes=1)]:
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                selected = root / MODULE.ENTRY / 'initial_control_recipe.json'
                selected.parent.mkdir(parents=True)
                selected.write_text(json.dumps({**recipe, **changed}))
                try:
                    MODULE.ROOT = root
                    with self.assertRaisesRegex(ValueError, 'cannot coexist'):
                        MODULE.command_initial_control_header(self.source, root / 'out.h', MODULE.ENTRY)
                    self.assertFalse((root / 'out.h').exists())
                finally:
                    MODULE.ROOT = original_root


class BundleInstallerComposition(unittest.TestCase):
    def setUp(self):
        # Same independently specified command forms as the existing Remote
        # composition fixture, now selecting the distinct installer entrance.
        previous = RemoteScopedComposition()
        previous.setUp()
        self.fixture = previous
        self.commands = [[arg.replace('native_remote_resident_site',
                                      'native_runtime_bundle') for arg in step]
                         for step in previous.commands]
        self.header = Path('/owned/bundle-initial-control.h')

    def plan(self, commands=None, **changes):
        f = self.fixture
        return MODULE.commands_for('\n'.join(shlex.join(c) for c in
                                   (self.commands if commands is None else commands)),
                                   f.home, f.emission, f.stage, f.clang, f.sdk,
                                   entry=MODULE.BUNDLE_ENTRY, source_sha=f.source,
                                   **{'bundle_control_header': self.header, **changes})

    def test_installer_has_one_own_header_entrance_without_changing_other_c_steps(self):
        planned = self.plan()
        selected = [c for c in planned if any(x.startswith('-DACTQL_BUNDLE_') for x in c)]
        self.assertEqual(len(selected), 1)
        self.assertIn('./src/cmd/native_runtime_bundle/initial_control_stub.c', selected[0])
        self.assertIn('-DACTQL_BUNDLE_INITIAL_CONTROL_HEADER="' + str(self.header) + '"', selected[0])
        self.assertFalse(any(x.startswith('-DACTQL_RESIDENT_') for c in planned for x in c))
        self.assertEqual(sum(any(x.startswith('-DACTQL_SCOPED_READ_PROVIDER=') for x in c)
                             for c in planned), 1)
        step = next(c for c in self.commands if './src/cmd/native_runtime_bundle/initial_control_stub.c' in c)
        for commands in ([c for c in self.commands if c is not step], self.commands + [step]):
            with self.subTest(steps=len(commands)), self.assertRaisesRegex(ValueError, 'installer initial-control entrance'):
                self.plan(commands)

    def test_installer_cannot_borrow_a_resident_or_foreign_header_selection(self):
        for header in (None, Path('/foreign/bundle-control.h')):
            with self.subTest(header=header), self.assertRaisesRegex(ValueError, 'Bundle installer source'):
                self.plan(bundle_control_header=header,
                          resident_control_header=self.fixture.header)
        commands = [c.copy() for c in self.commands]
        commands[3].append('-DACTQL_RESIDENT_SOURCE_SHA="' + self.fixture.source + '"')
        with self.assertRaisesRegex(ValueError, 'Duplicate Bundle installer'):
            self.plan(commands)

    def test_installer_private_recipe_is_distinct_and_exact(self):
        import hashlib
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'bundle.h'
            record = MODULE.command_initial_control_header(self.fixture.source, output, MODULE.BUNDLE_ENTRY)
            recipe = MODULE.ROOT / MODULE.BUNDLE_ENTRY / 'initial_control_recipe.json'
            self.assertEqual(record['recipe']['path'], str(recipe))
            self.assertEqual(record['recipeSha256'], hashlib.sha256(recipe.read_bytes()).hexdigest())
            self.assertEqual(record['selected']['kind'], 'private-runtime-bundle-command-initial-control')
            self.assertIn('#define ACTQL_BUNDLE_MANAGED_PAYLOAD 67108864\n', output.read_text())
            self.assertIn('#define ACTQL_BUNDLE_SQLITE_HEAP 33554432\n', output.read_text())
            self.assertIn('#define ACTQL_BUNDLE_CRYPTO_HEAP 16777216\n', output.read_text())
            self.assertIn('#define ACTQL_BUNDLE_DIAGNOSTIC_BYTES 2048\n', output.read_text())
            self.assertFalse(record['permission'])
            self.assertFalse(record['physicalAcquired'])

    def test_installer_exports_only_the_existing_component_provider_ports_at_final_link(self):
        for target, options, prefix in (
            ('darwin-arm64', {}, '-Wl,-exported_symbol,_'),
            ('linux-x64', {'stock_file_control_bytes': 4096}, '-Wl,--export-dynamic-symbol='),
        ):
            with self.subTest(target=target):
                planned = self.plan(target=target, **options)
                expected = {prefix + symbol for symbol in MODULE.LOCAL_COMPONENT_PROVIDER_EXPORTS}
                self.assertEqual({part for step in planned for part in step
                                  if part.startswith(prefix)}, expected)
                selected = [step for step in planned if any(part in expected for part in step)]
                self.assertEqual(len(selected), 1)
                self.assertNotIn('-c', selected[0])

    def test_installer_rejects_component_extents_that_cannot_coexist(self):
        original_root = MODULE.ROOT
        recipe = json.loads((original_root / MODULE.BUNDLE_ENTRY / 'initial_control_recipe.json').read_text())
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            selected = root / MODULE.BUNDLE_ENTRY / 'initial_control_recipe.json'
            selected.parent.mkdir(parents=True)
            recipe['sqliteHeapBytes'] = recipe['capacityBytes']
            selected.write_text(json.dumps(recipe))
            try:
                MODULE.ROOT = root
                with self.assertRaisesRegex(ValueError, 'cannot coexist'):
                    MODULE.command_initial_control_header(self.fixture.source, root / 'out.h', MODULE.BUNDLE_ENTRY)
                self.assertFalse((root / 'out.h').exists())
            finally:
                MODULE.ROOT = original_root

    def test_only_the_selected_original_entry_recipe_changes(self):
        f = self.fixture
        for entry, strip in ((MODULE.ENTRY, True), (MODULE.LOCAL_ENTRY, False),
                             (MODULE.BUNDLE_ENTRY, True)):
            with self.subTest(entry=entry):
                arguments = MODULE.moon_build_arguments(f.home, f.emission, entry)
                self.assertEqual(arguments[-1], entry)
                self.assertEqual('--strip' in arguments, strip)
                self.assertEqual(arguments.count('--release'), 1)




class HttpComponentRecipeControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('http_selected_component',
            Path(__file__).with_name('produce-native-http-component.py'))
        cls.http = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.http)

    def test_explicit_tls_targets_keep_the_original_configuration_and_no_foreign_sdk(self):
        select = self.http.TLS.command_profile
        darwin = select('darwin-arm64', Path('/cc'), Path('/sdk'), Path('/owned'))
        linux = select('linux-x64', Path('/cc'), None, Path('/owned'))
        self.assertEqual(darwin['configure'], 'darwin64-arm64-cc')
        self.assertEqual(darwin['environment']['MACOSX_DEPLOYMENT_TARGET'], '26.0')
        self.assertEqual(linux['configure'], 'linux-x86_64')
        self.assertNotIn('SDKROOT', linux['environment'])
        self.assertNotIn('-arch', linux['environment']['CFLAGS'])
        self.assertEqual(linux['compilerFlags'], ['-D_GNU_SOURCE'])
        for target, sdk in (('linux-arm64', None), ('linux-x64', Path('/sdk')), ('darwin-arm64', None)):
            with self.subTest(target=target, sdk=sdk), self.assertRaises(ValueError):
                select(target, Path('/cc'), sdk, Path('/owned'))

    def image(self, root):
        library = root / 'libcurl.so.4'
        header = bytearray(64)
        header[:7] = b'\x7fELF\x02\x01\x01'
        header[16:18] = (3).to_bytes(2, 'little')
        header[18:20] = (62).to_bytes(2, 'little')
        library.write_bytes(header)
        dynamic = '(NEEDED) Shared library: [libc.so.6]\n(SONAME) Library soname: [libcurl.so.4]\n'
        exports = '\n'.join('0000 T ' + name for name in
                            self.http.CURL_EXPORTS | {'curl_actql_native_tls_api_v3'})
        return library, dynamic, exports

    def test_macos11_profile_is_explicit_and_cannot_retag_original_26_tls(self):
        tls = self.http.TLS
        profile = tls.command_profile('darwin-arm64', Path('/cc'), Path('/sdk'), Path('/owned'), '11.0')
        self.assertEqual(profile['minimumMacOS'], '11.0')
        self.assertEqual(profile['environment']['MACOSX_DEPLOYMENT_TARGET'], '11.0')
        self.assertIn('-mmacosx-version-min=11.0', profile['environment']['CFLAGS'])
        self.assertIn('-mmacosx-version-min=11.0', profile['compilerFlags'])
        tls.validate_receipt_profile({}, 'darwin-arm64', '26.0')
        with self.assertRaisesRegex(ValueError, 'deployment profile differs'):
            tls.validate_receipt_profile({}, 'darwin-arm64', '11.0')
        tls.validate_receipt_profile({'target': 'darwin-arm64', 'minimumMacOS': '11.0'},
                                     'darwin-arm64', '11.0')
        for target, sdk, minimum in (('linux-x64', None, '11.0'),
                                     ('darwin-arm64', Path('/sdk'), '14.0')):
            with self.subTest(target=target, minimum=minimum), self.assertRaises(ValueError):
                tls.command_profile(target, Path('/cc'), sdk, Path('/owned'), minimum)

    def test_static_tls_archive_members_cannot_hide_a_newer_deployment_requirement(self):
        check = self.http.TLS.validate_archive_deployment
        old = 'cmd LC_BUILD_VERSION\ncmdsize 24\nplatform 1\nminos 11.0\nsdk 26.0\n'
        newer = 'cmd LC_BUILD_VERSION\ncmdsize 24\nplatform 1\nminos 26.0\nsdk 26.0\n'
        check(old, '11.0')
        check(old + newer, '26.0')
        check('cmd LC_VERSION_MIN_MACOSX\ncmdsize 16\nversion 11.0\nsdk 26.0\n', '11.0')
        for loads in (old + newer, old.replace('platform 1', 'platform 2'), ''):
            with self.subTest(loads=loads), self.assertRaisesRegex(ValueError, 'deployment requirement'):
                check(loads, '11.0')

    def test_linux_http_requires_the_existing_same_image_read_allocator_export(self):
        with tempfile.TemporaryDirectory() as temporary:
            library, dynamic, exports = self.image(Path(temporary))
            self.assertEqual(self.http.inspect_linux_component(library, dynamic, exports), ['libc.so.6'])
            with self.assertRaisesRegex(ValueError, 'cleanup or loader export'):
                self.http.inspect_linux_component(library, dynamic,
                    '\n'.join(line for line in exports.splitlines() if 'curl_actql_native_tls_api_v3' not in line))

    def test_linux_http_refuses_foreign_abi_dynamic_tls_and_ambient_loader_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            library, dynamic, exports = self.image(Path(temporary))
            for extra in ('(NEEDED) Shared library: [libssl.so.3]\n',
                          '(NEEDED) Shared library: [libcrypto.so.3]\n',
                          '(RUNPATH) Library runpath: [/foreign]\n'):
                with self.subTest(extra=extra), self.assertRaises(ValueError):
                    self.http.inspect_linux_component(library, dynamic + extra, exports)
            raw = bytearray(library.read_bytes());raw[18:20] = (183).to_bytes(2, 'little')
            library.write_bytes(raw)
            with self.assertRaisesRegex(ValueError, 'ELF64 little-endian x86-64'):
                self.http.inspect_linux_component(library, dynamic, exports)


class ResidentCaptureComponent(unittest.TestCase):
    def test_fixture_declares_its_own_stdio_without_capture_header_exports(self):
        compiler = shutil.which('cc')
        self.assertIsNotNone(compiler)
        with tempfile.TemporaryDirectory() as temporary:
            declarations = Path(temporary) / 'capture-contract.h'
            # Declaration-only header contract: compile the SAME actual fixture
            # without incidental Darwin stdio exports. No capture is fabricated
            # or executed, and the real target component below stays unchanged.
            declarations.write_text('''#include <stdbool.h>
typedef struct resident_entry resident_entry;
extern resident_entry original_entry;
bool selected_recipe(void);
bool capture_entry(resident_entry *);
bool entry_current(resident_entry *);
''')
            result = subprocess.run([compiler, '-std=c11', '-Wall', '-Wextra', '-Werror',
                '-fsyntax-only', '-DACTQL_RESIDENT_INITIAL_CONTROL_CAPTURE_H',
                '-include', str(declarations),
                str(MODULE.ROOT / 'scripts/fixtures/resident-initial-control.c')],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_actual_selected_original_and_refusals_without_a_managed_runtime(self):
        target = {('Darwin', 'arm64'): 'darwin-arm64',
                  ('Linux', 'x86_64'): 'linux-x64'}.get((platform.system(), platform.machine()))
        self.assertIsNotNone(target, 'Select an actual supported capture component target')
        compiler = shutil.which('cc')
        self.assertIsNotNone(compiler)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            header = root / 'initial.h'
            record = MODULE.command_initial_control_header('a' * 40, header, MODULE.ENTRY, target)
            selected = root / 'selected'
            unselected = root / 'unselected'
            source = MODULE.ROOT / 'scripts/fixtures/resident-initial-control.c'
            flags = (['-D_GNU_SOURCE', '-DACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY',
                      '-DACTQL_NATIVE_LINUX_X64_RESIDENT_ENTRY'] if target == 'linux-x64' else [])
            def compile_capture(arguments):
                result = subprocess.run(arguments, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
            # This component consumes capture only, not the header's other
            # private command-preparation helpers. Product flags stay unchanged.
            warnings = ['-Wall', '-Wextra', '-Werror', '-Wno-unused-function']
            compile_capture([compiler, '-std=c11', *warnings, '-pthread',
                *flags, '-DACTQL_RESIDENT_INITIAL_CONTROL_HEADER="' + str(header) + '"',
                str(source), '-o', str(selected)])
            for arguments, expected in (([], 'PASS same original;'),
                    (['loader-refusal'], 'PASS unsupported loader selection stays refused'),
                    (['x' * (record['selected']['maximumArgumentBytes'] + 1)],
                     'PASS argument bound checked before original copy')):
                result = subprocess.run([str(selected), *arguments], check=True,
                    capture_output=True, text=True, timeout=10,
                    env={'PATH': '/usr/bin:/bin', 'LANG': 'C'})
                self.assertTrue(result.stdout.startswith(expected), result.stdout)
            compile_capture([compiler, '-std=c11', *warnings, '-pthread',
                str(source), '-o', str(unselected)])
            result = subprocess.run([str(unselected)], check=True,
                capture_output=True, text=True, timeout=10,
                env={'PATH': '/usr/bin:/bin', 'LANG': 'C'})
            self.assertEqual(result.stdout, 'PASS unselected entry refuses without capture\n')


class ResidentFfiComponent(unittest.TestCase):
    def test_original_external_handle_retirement_uses_the_pinned_runtime_abi(self):
        target = {('Darwin', 'arm64'): 'darwin-arm64',
                  ('Linux', 'x86_64'): 'linux-x64'}.get((platform.system(), platform.machine()))
        self.assertIsNotNone(target, 'Select an actual supported FFI component target')
        self.assertIn('MOON_HOME', os.environ, 'Use the existing selected pinned toolchain')
        home = Path(os.environ['MOON_HOME']).resolve()
        self.assertEqual(json.loads((home / 'installed.json').read_bytes()),
                         {'pin': json.loads((MODULE.ROOT / 'toolchain.json').read_bytes()), 'platform': target})
        runtime = [home / 'lib/runtime' / (name + '.c') for name in sorted(MODULE.RUNTIME_NAMES)]
        original_inputs = [home / 'include/moonbit.h', home / 'include/moonbit_runtime.h',
                           home / 'lib/libmoonbitrun.o', home / 'lib/libbacktrace.a', *runtime]
        def identities():
            return [(path.stat().st_dev, path.stat().st_ino, path.stat().st_mode,
                     path.stat().st_mtime_ns, path.stat().st_size, path.read_bytes()) for path in original_inputs]
        before = identities()
        compiler = shutil.which('cc')
        self.assertIsNotNone(compiler)
        parent = MODULE.ROOT / '_build/native-resident-control-ffi'
        parent.mkdir(parents=True, exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix='original-', dir=parent))
        print('Retained original Resident FFI component: ' + str(directory))
        header = directory / 'initial.h'
        MODULE.command_initial_control_header('a' * 40, header, MODULE.ENTRY, target)
        flags = (['-D_GNU_SOURCE', '-DACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY',
                  '-DACTQL_NATIVE_LINUX_X64_RESIDENT_ENTRY'] if target == 'linux-x64' else [])
        for selected in (True, False):
            executable = directory / ('selected' if selected else 'unselected-recipe')
            arguments = [compiler, '-std=c11', '-O0', '-pthread', *flags,
                '-I' + str(home / 'include'), '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC',
                *(['-DACTQL_RESIDENT_INITIAL_CONTROL_HEADER="' + str(header) + '"'] if selected else []),
                str(MODULE.ROOT / 'scripts/fixtures/resident-initial-control-ffi.c'),
                *map(str, runtime), str(home / 'lib/libmoonbitrun.o'),
                str(home / 'lib/libbacktrace.a'), '-lm', '-o', str(executable)]
            result = subprocess.run(arguments, capture_output=True, text=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stderr)
            for mode in (('components', 'partial', 'stderr') if selected else ('unselected',)):
                result = subprocess.run([str(executable), mode], capture_output=True, text=True, timeout=10,
                    env={'PATH': '/usr/bin:/bin', 'LANG': 'C'})
                self.assertEqual(result.returncode, 0, result.stderr)
                if mode == 'stderr':
                    self.assertEqual(result.stderr, 'command diagnostic\n')
                    self.assertEqual(result.stdout, 'PASS diagnostic consumed on stderr only\n')
                else:
                    self.assertEqual(result.stdout,
                        '{"kind":"stopped","scope":"original-command-retired"}\n'
                        'PASS original capture retirement; no second entry or renewal\n')
        self.assertEqual(identities(), before, 'Original pinned runtime changed during FFI component')


class LinuxResidentComposition(unittest.TestCase):
    def test_selected_resident_uses_one_pinned_provider_and_own_capture_header(self):
        fixture = RemoteScopedComposition()
        fixture.setUp()
        planned = MODULE.commands_for('\n'.join(shlex.join(c) for c in fixture.commands),
            fixture.home, fixture.emission, fixture.stage, fixture.clang, None,
            source_sha=fixture.source, resident_control_header=fixture.header,
            target='linux-x64', stock_file_control_bytes=4096)
        c = [step for step in planned if step[0] == str(fixture.clang)]
        for step in c:
            self.assertIn('-DACTQL_NATIVE_LINUX_X64_RESIDENT_ENTRY', step)
            self.assertIn('-DACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY', step)
            self.assertIn('-DACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=170', step)
        self.assertEqual(sum(any(arg.startswith('-DACTQL_SCOPED_READ_PROVIDER=') for arg in step)
                             for step in c), 1)
        self.assertEqual(sum(any(arg.startswith('-DACTQL_RESIDENT_INITIAL_CONTROL_HEADER=') for arg in step)
                             for step in c), 1)
        exports = {'-Wl,--export-dynamic-symbol=' + symbol
                   for symbol in MODULE.LOCAL_COMPONENT_PROVIDER_EXPORTS}
        self.assertEqual({arg for arg in planned[-1] if arg in exports}, exports)
        self.assertFalse(any(arg in exports for step in planned[:-1] for arg in step))

    def test_linux_resident_recipe_keeps_original_extents_and_exact_file_control_page(self):
        with tempfile.TemporaryDirectory() as temporary:
            record = MODULE.command_initial_control_header('a' * 40,
                Path(temporary) / 'resident.h', MODULE.ENTRY, 'linux-x64')
            old = json.loads((MODULE.ROOT / MODULE.RESIDENT_RECIPE).read_bytes())
            selected = record['selected'].copy()
            self.assertEqual(selected.pop('target'), 'linux-x64')
            self.assertEqual(selected.pop('stockFileControlBytes'), 4096)
            old.pop('target')
            self.assertEqual(selected, old)
            text = Path(record['header']['path']).read_text()
            self.assertIn('#define ACTQL_RESIDENT_TARGET_LINUX_X64 1\n', text)
            self.assertIn('#define ACTQL_RESIDENT_SQLITE_HEAP 33554432\n', text)
            self.assertIn('#define ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES 4096\n', text)


class LinuxBundleComposition(unittest.TestCase):
    def setUp(self):
        self.fixture = BundleInstallerComposition()
        self.fixture.setUp()

    def test_linux_bundle_keeps_one_original_provider_header_and_runtime(self):
        planned = self.fixture.plan(target='linux-x64', stock_file_control_bytes=4096)
        c = [step for step in planned if step[0] == str(self.fixture.fixture.clang)]
        self.assertTrue(c)
        for step in c:
            self.assertIn('-D_GNU_SOURCE', step)
            self.assertIn('-DACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY', step)
            self.assertIn('-DACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=170', step)
            self.assertNotIn('-isysroot', step)
            self.assertFalse(any(arg.startswith('-mmacosx-') for arg in step))
        self.assertEqual(sum(any(arg.startswith('-DACTQL_SCOPED_READ_PROVIDER=') for arg in step)
                             for step in c), 1)
        self.assertEqual(sum(any(arg.startswith('-DACTQL_BUNDLE_INITIAL_CONTROL_HEADER=') for arg in step)
                             for step in c), 1)
        self.assertFalse(any(arg.startswith('-DACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN')
                             for step in c for arg in step))

    def test_linux_bundle_requires_the_exact_control_page_and_target(self):
        for size in (None, 0, 1, 4095, 4097, 8192):
            with self.subTest(size=size), self.assertRaisesRegex(ValueError, 'control page'):
                self.fixture.plan(target='linux-x64', stock_file_control_bytes=size)
        for entry in (MODULE.LOCAL_ENTRY,):
            with self.subTest(entry=entry), self.assertRaisesRegex(ValueError, 'target/entry'):
                MODULE.commands_for('', Path('/moon'), Path('/owned/emission'), Path('/owned/allocator'),
                                    Path('/cc'), None, target='linux-x64', entry=entry,
                                    stock_file_control_bytes=4096)

    def test_linux_recipe_retains_all_old_quantities_and_own_target_pin(self):
        with tempfile.TemporaryDirectory() as temporary:
            record = MODULE.command_initial_control_header(self.fixture.fixture.source,
                Path(temporary) / 'linux.h', MODULE.BUNDLE_ENTRY, 'linux-x64')
            old = json.loads((MODULE.ROOT / MODULE.BUNDLE_ENTRY / 'initial_control_recipe.json').read_bytes())
            selected = record['selected'].copy()
            self.assertEqual(selected.pop('target'), 'linux-x64')
            self.assertEqual(selected.pop('stockFileControlBytes'), 4096)
            old.pop('target')
            self.assertEqual(selected, old)
            text = Path(record['header']['path']).read_text()
            self.assertIn('#define ACTQL_RESIDENT_TARGET_LINUX_X64 1\n', text)
            self.assertIn('#define ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES 4096\n', text)
            self.assertFalse(record['permission'])
            self.assertFalse(record['physicalAcquired'])

if __name__ == '__main__':
    unittest.main()
