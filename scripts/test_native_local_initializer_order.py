"""Normal main must not depend on a private pre-main command constructor."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('local_initializer', ROOT / 'scripts/produce-native-remote-scoped-runtime.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LocalInitializerOrder(unittest.TestCase):
    def test_runtime_initializers_and_options_precede_normal_command_main(self):
        self.assertEqual(sys.platform, 'darwin')
        home = Path(os.environ['MOON_HOME']).resolve()
        sdk = Path(os.environ['SDKROOT']).resolve()
        scratch = Path(tempfile.mkdtemp(prefix='actql-normal-command-main-'))
        flags = ['-std=c11', '-O0', '-isysroot', str(sdk),
                 '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', '-I' + str(home / 'include'),
                 '-DACTQL_NATIVE_CLIENT_SOURCE_SHA="1234567890abcdef1234567890abcdef12345678"']
        executable = scratch / 'normal-main'
        command = ['/Library/Developer/CommandLineTools/usr/bin/clang', *flags,
                   str(ROOT / 'scripts/fixtures/native-command-initializer-observation.c'),
                   str(ROOT / 'scripts/fixtures/native-command-member-unavailable.c'),
                   str(home / 'lib/runtime/runtime.c'), str(home / 'lib/runtime/backtrace.c'),
                   str(home / 'lib/libmoonbitrun.o'), '-o', str(executable)]
        built = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        records = []
        for options in [False, True]:
            environment = {**os.environ, 'ACTQL_NATIVE_LOCAL_RUNTIME': '{"controlled":"normal main"}'}
            if options:
                environment['MIMALLOC_VERBOSE'] = '0'
                environment['MIMALLOC_SHOW_STATS'] = '0'
            result = subprocess.run([str(executable)], capture_output=True, text=True,
                                    timeout=10, env=environment)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout, 'normal main passed\n')
            self.assertEqual(result.stderr, '')
            records.append({'options': options, 'code': result.returncode})
        print(json.dumps({'executable': str(executable), 'records': records,
                          'qualification': 'C/O0 normal-main/initializer boundary, not installed CLI acceptance'}))


if __name__ == '__main__':
    unittest.main()
