"""Actual private entry issuance; not loader/prelude or ordinary wheel supply."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import sysconfig
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
OWNER = ROOT / 'src/platform_native/host_bootstrap'
SPEC = importlib.util.spec_from_file_location(
    'python_initial_provider', ROOT / 'scripts/produce-python-native-provider.py')
PROVIDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROVIDER)


def record(path):
    raw = path.read_bytes()
    return {'path': str(path), 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


class PythonInitialPlatformEntry(unittest.TestCase):
    def test_selected_producer_preparation_and_exact_interpreter_imports(self):
        scratch = Path(tempfile.mkdtemp(prefix='python-platform-recipe-', dir=ROOT / '_build'))
        home = Path(os.environ['MOON_HOME'])
        source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                                         text=True).strip()
        initial = PROVIDER.prepare_python_initial_component(source, home, scratch)
        PROVIDER.require_python_initial_component_current(initial)
        self.assertEqual(Path(initial['runtime']).read_bytes(),
                         PROVIDER.python_initial_runtime_bytes((home / 'lib/libmoonbitrun.o').read_bytes()))
        self.assertFalse(initial['recipe']['complete_outside_initial_supply'])
        self.assertFalse(initial['recipe']['worker_supply'])
        flags = PROVIDER.python_initial_link_flags()
        self.assertEqual(flags, ['-Wl,-no_inits', '-Wl,-U,_PyGILState_Check',
            '-Wl,-U,_Py_GetVersion', '-Wl,-U,_PyInterpreterState_Get',
            '-Wl,-U,_PyThreadState_Get', '-Wl,-U,_PyInterpreterState_GetID',
            '-Wl,-U,_PyThreadState_GetID', '-Wl,-U,_PyMem_GetAllocator'])
        probe = scratch / 'link.c'
        probe.write_text('extern int PyGILState_Check(void);\n'
                         'int original(void) { return PyGILState_Check(); }\n')
        command = ['/Library/Developer/CommandLineTools/usr/bin/clang',
                   '-isysroot', os.environ['SDKROOT'], '-mmacosx-version-min=11.0',
                   '-dynamiclib', str(probe), '-o', str(scratch / 'link.dylib'), *flags]
        selected = subprocess.run(command, capture_output=True, text=True, timeout=30)
        self.assertEqual(selected.returncode, 0, selected.stderr)
        probe.write_text('extern int actql_foreign_unresolved(void);\n'
                         'int original(void) { return actql_foreign_unresolved(); }\n')
        foreign = subprocess.run(command, capture_output=True, text=True, timeout=30)
        self.assertNotEqual(foreign.returncode, 0)
        self.assertIn('actql_foreign_unresolved', foreign.stderr)
        derived = Path(initial['runtime'])
        derived.write_bytes(derived.read_bytes() + b'foreign')
        with self.assertRaisesRegex(ValueError, 'input changed'):
            PROVIDER.require_python_initial_component_current(initial)

    def test_actual_entry_original_partial_and_runtime_fence(self):
        self.assertEqual(sys.platform, 'darwin')
        self.assertEqual(sys.version_info[:3], (3, 12, 12))
        scratch = Path(tempfile.mkdtemp(prefix='python-platform-entry-', dir=ROOT / '_build'))
        runtime = Path(os.environ['MOON_HOME']) / 'lib/libmoonbitrun.o'
        derived = scratch / 'runtime.o'
        derived.write_bytes(PROVIDER.python_initial_runtime_bytes(runtime.read_bytes()))
        source = OWNER / 'fixtures/python_initial_platform_entry.c'
        entry = OWNER / 'python_initial_platform.c'
        source_sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                                             text=True).strip()
        recipe = {'qualification': 'Actual private initial entry diagnostic only',
                  'source': source_sha, 'entry': record(entry), 'fixture': record(source),
                  'runtime': record(runtime), 'derived': record(derived),
                  'interpreter': sys.version, 'header': record(Path(sysconfig.get_path('include')) / 'Python.h')}
        recipe_bytes = json.dumps(recipe, sort_keys=True, separators=(',', ':')).encode()
        recipe_sha = hashlib.sha256(recipe_bytes).hexdigest()
        (scratch / 'recipe.json').write_bytes(recipe_bytes)
        library, dependencies = scratch / 'original.dylib', scratch / 'original.d'
        base = ['/Library/Developer/CommandLineTools/usr/bin/clang', '-std=c11', '-O0',
                '-Wall', '-Wextra', '-Werror', '-isysroot', os.environ['SDKROOT'],
                '-mmacosx-version-min=11.0', '-I' + sysconfig.get_path('include'),
                '-I' + str(Path(os.environ['MOON_HOME']) / 'include')]
        # Absence of selected compilation cannot silently select this entry.
        unselected = subprocess.run(base + ['-fsyntax-only', str(entry)],
                                    capture_output=True, text=True, timeout=30)
        (scratch / 'unselected.stderr').write_text(unselected.stderr)
        self.assertNotEqual(unselected.returncode, 0)
        self.assertIn('Select the original Python operational component recipe explicitly',
                      unselected.stderr)
        command = base + ['-DACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY',
                         '-DACTQL_PYTHON_INITIAL_SOURCE_SHA="' + source_sha + '"',
                         '-DACTQL_PYTHON_INITIAL_RECIPE_SHA="' + recipe_sha + '"',
                         '-MD', '-MF', str(dependencies), '-dynamiclib',
                         '-undefined', 'dynamic_lookup', '-Wl,-no_inits',
                         str(source), str(derived), '-o', str(library)]
        built = subprocess.run(command, capture_output=True, text=True, timeout=60)
        (scratch / 'compile.stdout').write_text(built.stdout)
        (scratch / 'compile.stderr').write_text(built.stderr)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        child = '''import ctypes,json,sys
library=ctypes.PyDLL(sys.argv[1])
call=library.original_python_platform_entry_case
call.argtypes=[ctypes.c_int];call.restype=ctypes.c_int
assert call(int(sys.argv[2]))==1
print(json.dumps({'case':int(sys.argv[2]),'actual_entry_case':1}))
'''
        results = []
        for mode, name in enumerate(['ready-thread', 'mapping-partial', 'ready-fork',
                                     'unsupported-environment']):
            result = subprocess.run([sys.executable, '-I', '-B', '-c', child,
                                     str(library), str(mode)], capture_output=True,
                                    text=True, timeout=20)
            (scratch / (name + '.stdout')).write_text(result.stdout)
            (scratch / (name + '.stderr')).write_text(result.stderr)
            self.assertEqual(result.returncode, 0, (name, result.stdout, result.stderr))
            results.append({'name': name, **json.loads(result.stdout)})
        inputs = [record(Path(name)) for name in
                  shlex.split(dependencies.read_text().replace('\\\n', ' '))[1:]]
        packet = {'qualification': 'Actual production private C entry with actual CPython/MI; '
                  'controlled mapping-failure/emitted receiver and diagnostic load. Not '
                  'before-load OS coverage, product Moon, Worker, VM or ordinary wheel',
                  'recipe': recipe, 'recipe_sha256': recipe_sha,
                  'command': command, 'inputs': inputs, 'library': record(library),
                  'cases': results, 'unselected_compile_refused': True}
        (scratch / 'result.json').write_text(json.dumps(packet, indent=2) + '\n')
        print(json.dumps({'actual_cases': len(results), 'evidence': str(scratch / 'result.json')}))


if __name__ == '__main__':
    unittest.main()
