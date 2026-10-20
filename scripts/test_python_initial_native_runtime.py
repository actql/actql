"""Exact derived runtime recipe and actual explicit-init boundary, not funding."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    'python_native_provider', ROOT / 'scripts/produce-python-native-provider.py')
PROVIDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROVIDER)


class PythonInitialNativeRuntime(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.home = Path(os.environ['MOON_HOME']).resolve()
        cls.runtime = cls.home / 'lib/libmoonbitrun.o'
        cls.raw = cls.runtime.read_bytes()

    def test_exact_source_and_only_registration_descriptor_changes(self):
        derived = PROVIDER.python_initial_runtime_bytes(self.raw)
        self.assertEqual(len(derived), len(self.raw))
        # Independent offsets of this exact pinned object, not product output.
        expected = bytearray(self.raw)
        expected[1064:1080] = b'__actql_mi_init\0'
        expected[1128:1132] = b'\0' * 4
        self.assertEqual(derived, bytes(expected))
        self.assertEqual(hashlib.sha256(self.runtime.read_bytes()).hexdigest(),
                         PROVIDER.PYTHON_INITIAL_RUNTIME_SHA256)

    def test_unknown_object_refuses(self):
        with self.assertRaisesRegex(ValueError, 'object changed'):
            PROVIDER.python_initial_runtime_bytes(b'')

    def test_changed_instruction_refuses(self):
        changed = bytearray(self.raw)
        changed[1368] ^= 1
        with self.assertRaisesRegex(ValueError, 'object changed'):
            PROVIDER.python_initial_runtime_bytes(bytes(changed))

    def test_derived_object_cannot_be_selected_again(self):
        derived = PROVIDER.python_initial_runtime_bytes(self.raw)
        with self.assertRaisesRegex(ValueError, 'object changed'):
            PROVIDER.python_initial_runtime_bytes(derived)

    def test_actual_loader_does_not_initialize_derived_runtime(self):
        self.assertEqual(sys.platform, 'darwin')
        self.assertEqual(sys.version_info[:3], (3, 12, 12))
        scratch = Path(tempfile.mkdtemp(prefix='python-initial-runtime-', dir=ROOT / '_build'))
        derived = scratch / 'python-initial-runtime.o'
        derived.write_bytes(PROVIDER.python_initial_runtime_bytes(self.raw))
        observer = scratch / 'observe.c'
        observer.write_text('''#include <stdbool.h>
extern bool _mi_process_is_initialized;
extern void mi_process_init(void);
int original_initialized(void) { return _mi_process_is_initialized ? 1 : 0; }
void initialize_original(void) { mi_process_init(); }
''')
        clang = '/Library/Developer/CommandLineTools/usr/bin/clang'
        sdk = os.environ['SDKROOT']
        child = '''import ctypes,json,sys
library=ctypes.CDLL(sys.argv[1])
observe=library.original_initialized
observe.argtypes=[];observe.restype=ctypes.c_int
before=observe()
assert before==int(sys.argv[2]),(before,sys.argv[2])
initialize=library.initialize_original
initialize.argtypes=[];initialize.restype=None
initialize()
assert observe()==1
print(json.dumps({'before_explicit_init':before,'after_explicit_init':observe()}))
'''
        records = []
        for name, source, before in [('stock', self.runtime, 1), ('derived', derived, 0)]:
            library = scratch / (name + '.dylib')
            command = [clang, '-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
                       '-isysroot', sdk, '-mmacosx-version-min=11.0', '-dynamiclib',
                       str(observer), str(source), '-o', str(library)]
            if name == 'derived':
                # A surviving automatic initializer is a link error, not a
                # loader-time assumption based on a filename or old digest.
                command.append('-Wl,-no_inits')
            built = subprocess.run(command, capture_output=True, text=True, timeout=60)
            (scratch / (name + '.link.stdout')).write_text(built.stdout)
            (scratch / (name + '.link.stderr')).write_text(built.stderr)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            result = subprocess.run([sys.executable, '-I', '-B', '-c', child,
                                     str(library), str(before)],
                                    capture_output=True, text=True, timeout=15)
            (scratch / (name + '.stdout')).write_text(result.stdout)
            (scratch / (name + '.stderr')).write_text(result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            records.append({'command': command, 'library': PROVIDER.original(library),
                            'result': json.loads(result.stdout)})
        self.assertEqual(self.runtime.read_bytes(), self.raw)
        packet = {'qualification': 'Actual selected MI initialization ordering only; '
                  'no initial original, arena, Moon module, Worker or ordinary wheel admission',
                  'source': PROVIDER.original(self.runtime),
                  'derived': PROVIDER.original(derived),
                  'observer': PROVIDER.original(observer), 'records': records}
        (scratch / 'result.json').write_text(json.dumps(packet, indent=2) + '\n')
        print(json.dumps({'initial_runtime_evidence': str(scratch / 'result.json')}))


if __name__ == '__main__':
    unittest.main()
