"""Same MI physical implementation through the distinct Python typed entrance.

The CAPI original and finite selection below are diagnostic entry inputs, not
an ordinary initial-coverage supplier or the missing Worker/VM admission.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    'python_initial_provider', ROOT / 'scripts/produce-python-native-provider.py')
PROVIDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROVIDER)
OWNER = ROOT / 'src/platform_native/host_bootstrap'


def record(path):
    raw = path.read_bytes()
    return {'path': str(path), 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


class PythonInitialNativeBinding(unittest.TestCase):
    def test_command_original_is_not_a_python_original(self):
        command = ['/Library/Developer/CommandLineTools/usr/bin/clang', '-std=c11',
                   '-isysroot', os.environ['SDKROOT'], '-I' + str(OWNER),
                   '-Werror=incompatible-pointer-types', '-fsyntax-only', '-x', 'c', '-']
        prefix = '#include "command_platform.h"\n#include "python_initial_platform.h"\n'
        correct = prefix + '''void selected(actql_native_python_initial_platform_original *entry) {
  (void)actql_native_python_initial_managed_begin(entry);
}
'''
        accepted = subprocess.run(command, input=correct, text=True, capture_output=True)
        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        foreign = correct.replace('actql_native_python_initial_platform_original *entry',
                                  'actql_native_command_platform_original *entry')
        refused = subprocess.run(command, input=foreign, text=True, capture_output=True)
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn('incompatible pointer types', refused.stderr)

    def test_command_physical_preprocessing_tokens_are_identical(self):
        scratch = Path(tempfile.mkdtemp(prefix='python-initial-command-', dir=ROOT / '_build'))
        original = scratch / 'initial_managed_original.inc'
        original.write_bytes(subprocess.check_output([
            'git', 'show', '03f2f58e4fd5e58f8096137de41955265e205c54:'
            'src/platform_native/host_bootstrap/initial_managed.inc'], cwd=ROOT))
        command = ['/Library/Developer/CommandLineTools/usr/bin/clang', '-std=c11',
                   '-isysroot', os.environ['SDKROOT'], '-I' + str(OWNER), '-E', '-P', '-x', 'c']
        old = subprocess.run(command + [str(original)], check=True, capture_output=True).stdout
        current = subprocess.run(command + [str(OWNER / 'initial_managed.inc')],
                                 check=True, capture_output=True).stdout
        (scratch / 'command-original.i').write_bytes(old)
        (scratch / 'command-current.i').write_bytes(current)
        # Conditional source lines can add whitespace to -E output. Compare
        # actual compiler tokens, retaining spelling inside string/char tokens;
        # do not collapse whitespace inside literals or discard C constructs.
        def tokens(path):
            call = [command[0], '-std=c11', '-x', 'cpp-output', '-fsyntax-only',
                    '-Xclang', '-dump-tokens', str(path)]
            result = subprocess.run(call, check=True, capture_output=True)
            (scratch / (path.name + '.tokens')).write_bytes(result.stderr)
            values = [line.split(b'\t', 1)[0] for line in result.stderr.splitlines()]
            self.assertTrue(values and values[-1] == b"eof ''")
            return values
        expected = tokens(scratch / 'command-original.i')
        actual = tokens(scratch / 'command-current.i')
        self.assertEqual(actual, expected)
        print(json.dumps({'command_token_sha256': hashlib.sha256(b'\n'.join(actual)).hexdigest(),
                          'tokens': len(actual), 'evidence': str(scratch)}))

    def test_runtime_initializer_requires_same_current_managed_original(self):
        self.assertEqual(sys.platform, 'darwin')
        self.assertEqual(sys.version_info[:3], (3, 12, 12))
        import sysconfig
        scratch = Path(tempfile.mkdtemp(prefix='python-initial-runtime-', dir=ROOT / '_build'))
        runtime = Path(os.environ['MOON_HOME']) / 'lib/libmoonbitrun.o'
        selected = scratch / 'runtime.o'
        selected.write_bytes(PROVIDER.python_initial_runtime_bytes(runtime.read_bytes()))
        source = OWNER / 'fixtures/python_initial_runtime.c'
        library, dependencies = scratch / 'original.dylib', scratch / 'original.d'
        command = ['/Library/Developer/CommandLineTools/usr/bin/clang', '-std=c11', '-O0',
                   '-Wall', '-Wextra', '-Werror', '-isysroot', os.environ['SDKROOT'],
                   '-mmacosx-version-min=11.0', '-I' + sysconfig.get_path('include'),
                   '-I' + str(Path(os.environ['MOON_HOME']) / 'include'),
                   '-MD', '-MF', str(dependencies), '-dynamiclib', '-undefined', 'dynamic_lookup',
                   '-Wl,-no_inits', str(source), str(selected), '-o', str(library)]
        built = subprocess.run(command, capture_output=True, text=True, timeout=60)
        (scratch / 'compile.stdout').write_text(built.stdout)
        (scratch / 'compile.stderr').write_text(built.stderr)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        child = '''import ctypes,json,sys
library=ctypes.PyDLL(sys.argv[1])
call=library.original_python_runtime_case
call.argtypes=[ctypes.c_int];call.restype=ctypes.c_int
assert call(int(sys.argv[2]))==1
print(json.dumps({'case':int(sys.argv[2]),'actual_mi_case':1}))
'''
        results = []
        for mode, name in enumerate(['missing', 'partial', 'ready-then-restored']):
            result = subprocess.run([sys.executable, '-I', '-B', '-c', child,
                                     str(library), str(mode)], capture_output=True,
                                    text=True, timeout=20)
            (scratch / (name + '.stdout')).write_text(result.stdout)
            (scratch / (name + '.stderr')).write_text(result.stderr)
            self.assertEqual(result.returncode, 0, (name, result.stdout, result.stderr))
            results.append({'name': name, **json.loads(result.stdout)})
        inputs = [record(Path(name)) for name in
                  shlex.split(dependencies.read_text().replace('\\\n', ' '))[1:]]
        packet = {'qualification': 'Actual CPython/MI with controlled emitted-initializer '
                  'receiver; not product Moon initialization or ordinary initial supply',
                  'source': record(source), 'runtime': record(runtime),
                  'derived_runtime': record(selected), 'library': record(library),
                  'command': command, 'inputs': inputs, 'cases': results}
        (scratch / 'result.json').write_text(json.dumps(packet, indent=2) + '\n')
        print(json.dumps({'actual_cases': len(results), 'evidence': str(scratch / 'result.json')}))

    def test_actual_python_original_mapping_current_and_partial(self):
        self.assertEqual(sys.platform, 'darwin')
        self.assertEqual(sys.version_info[:3], (3, 12, 12))
        import sysconfig
        scratch = Path(tempfile.mkdtemp(prefix='python-initial-binding-', dir=ROOT / '_build'))
        runtime = Path(os.environ['MOON_HOME']) / 'lib/libmoonbitrun.o'
        selected = scratch / 'runtime.o'
        selected.write_bytes(PROVIDER.python_initial_runtime_bytes(runtime.read_bytes()))
        library = scratch / 'original.dylib'
        dependencies = scratch / 'original.d'
        source = OWNER / 'fixtures/python_initial_managed.c'
        command = ['/Library/Developer/CommandLineTools/usr/bin/clang', '-std=c11', '-O0',
                   '-Wall', '-Wextra', '-Werror', '-isysroot', os.environ['SDKROOT'],
                   '-mmacosx-version-min=11.0', '-I' + sysconfig.get_path('include'),
                   '-MD', '-MF', str(dependencies), '-dynamiclib', '-undefined', 'dynamic_lookup',
                   '-Wl,-no_inits', str(source), str(selected), '-o', str(library)]
        built = subprocess.run(command, capture_output=True, text=True, timeout=60)
        (scratch / 'compile.stdout').write_text(built.stdout)
        (scratch / 'compile.stderr').write_text(built.stderr)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        late_library = scratch / 'already-initialized.dylib'
        late_command = [part for part in command if part != '-Wl,-no_inits']
        late_command = [str(runtime) if part == str(selected) else
                        str(late_library) if part == str(library) else part
                        for part in late_command]
        late_command[late_command.index('-MF') + 1] = str(scratch / 'late.d')
        late = subprocess.run(late_command, capture_output=True, text=True, timeout=60)
        (scratch / 'late-compile.stdout').write_text(late.stdout)
        (scratch / 'late-compile.stderr').write_text(late.stderr)
        self.assertEqual(late.returncode, 0, late.stdout + late.stderr)
        child = '''import ctypes,json,sys
library=ctypes.PyDLL(sys.argv[1])
call=library.original_python_initial_case
call.argtypes=[ctypes.c_int];call.restype=ctypes.c_int
assert call(int(sys.argv[2]))==1
print(json.dumps({'case':int(sys.argv[2]),'actual_original_case':1}))
'''
        results = []
        for mode, name in enumerate(['missing', 'invalid', 'mapping-failed',
                                     'heap-partial', 'ready', 'spent-original',
                                     'already-initialized']):
            result = subprocess.run([sys.executable, '-I', '-B', '-c', child,
                                     str(late_library if mode == 6 else library), str(mode)],
                                    capture_output=True, text=True, timeout=20)
            (scratch / (name + '.stdout')).write_text(result.stdout)
            (scratch / (name + '.stderr')).write_text(result.stderr)
            self.assertEqual(result.returncode, 0, (name, result.stdout, result.stderr))
            results.append({'name': name, **json.loads(result.stdout)})
        inputs = []
        for name in shlex.split(dependencies.read_text().replace('\\\n', ' '))[1:]:
            path = Path(name)
            inputs.append(record(path))
        packet = {'qualification': 'Actual selected CPython/MI diagnostic entry only; '
                  'fixture selection is not ordinary initial coverage, Worker, VM or funding',
                  'source': record(source), 'runtime': record(runtime),
                  'derived_runtime': record(selected), 'library': record(library),
                  'late_library': record(late_library), 'late_command': late_command,
                  'command': command, 'inputs': inputs, 'cases': results}
        (scratch / 'result.json').write_text(json.dumps(packet, indent=2) + '\n')
        print(json.dumps({'actual_cases': len(results), 'evidence': str(scratch / 'result.json')}))


if __name__ == '__main__':
    unittest.main()
