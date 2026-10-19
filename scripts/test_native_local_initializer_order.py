"""Actual selected C/O0 link-order counter, not an installed CLI supplier."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('local_initializer', ROOT / 'scripts/produce-native-remote-scoped-runtime.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def initializers(path):
    data = path.read_bytes()
    magic, _, _, _, count, _, _, _ = struct.unpack_from('<8I', data)
    assert magic == 0xfeedfacf
    offset = 32
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x19:
            sections = struct.unpack_from('<I', data, offset + 64)[0]
            for index in range(sections):
                section = offset + 72 + 80 * index
                name = data[section:section + 16].split(b'\0')[0]
                if name == b'__mod_init_func':
                    length, location = struct.unpack_from('<QI', data, section + 40)
                    assert length % 8 == 0
                    return list(struct.unpack_from('<' + 'Q' * (length // 8), data, location))
        offset += size
    raise AssertionError('Actual initializer section is missing')


class LocalInitializerOrder(unittest.TestCase):
    def test_actual_entry_precedes_original_allocator_only_in_selected_link(self):
        self.assertEqual(sys.platform, 'darwin')
        home = Path(os.environ['MOON_HOME']).resolve()
        sdk = Path(os.environ['SDKROOT']).resolve()
        runtime = home / 'lib/libmoonbitrun.o'
        self.assertEqual(hashlib.sha256(runtime.read_bytes()).hexdigest(),
                         'd9db2413e755c00ab374901211a03a9551222fe779022bc3648235747ed2bd96')
        scratch = Path(tempfile.mkdtemp(prefix='actql-initializer-order-'))
        emission = scratch / 'emission'
        directory = emission / 'native/release/build/cmd/native_client'
        directory.mkdir(parents=True)
        clang = '/Library/Developer/CommandLineTools/usr/bin/clang'
        flags = ['-std=c11', '-O0', '-isysroot', str(sdk),
                 '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', '-I' + str(home / 'include')]
        commands = []

        def run(command, **kwargs):
            commands.append(command)
            result = subprocess.run(command, capture_output=True, text=True, timeout=60, **kwargs)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout

        observer = scratch / 'stdout_observed.o'
        run([clang, *flags, '-DACTQL_NATIVE_CLIENT_SOURCE_SHA="1234567890abcdef1234567890abcdef12345678"',
             '-c', str(ROOT / 'scripts/fixtures/native-command-initializer-observation.c'), '-o', str(observer)])
        archive = directory / 'libnative_client-0123456789abcdef.a'
        run(['/usr/bin/ar', 'rcs', str(archive), str(observer)])
        objects = []
        for name in ['runtime', 'backtrace']:
            output = scratch / (name + '.o')
            run([clang, *flags, '-c', str(home / 'lib/runtime' / (name + '.c')), '-o', str(output)])
            objects.append(str(output))
        core = directory / 'native_client.c'
        core.write_text('#include <assert.h>\n#include <stdbool.h>\n#include <stdio.h>\n#include <stdlib.h>\n'
                        'extern int actql_test_entry_before_allocator;\nextern bool _mi_preloading(void);\n'
                        'int main(int argc,char **argv) { assert(argc==2); assert(!_mi_preloading());\n'
                        'assert(actql_test_entry_before_allocator==atoi(argv[1])); puts("actual initializer order passed"); return 0; }\n')
        records = []
        environment = {**os.environ, 'ACTQL_NATIVE_LOCAL_RUNTIME': '{"controlled":"initializer order"}'}
        for selected in [False, True]:
            executable = scratch / ('selected' if selected else 'original')
            command = [clang, *flags, '-o', str(executable), str(runtime), str(core), str(archive),
                       str(ROOT / 'scripts/fixtures/native-command-member-unavailable.c'), *objects]
            if selected:
                command = MODULE.local_initial_entry_arguments(command, home, emission)
            run(command)
            names = run(['/usr/bin/nm', '-n', str(executable)])
            symbols = {fields[-1]: int(fields[0], 16) for line in names.splitlines()
                       if len(fields := line.split()) == 3 and fields[0].isalnum()}
            order = initializers(executable)
            entry = order.index(symbols['_actql_command_capture_process_entry'])
            allocator = order.index(symbols['__mi_process_init'])
            self.assertEqual(entry < allocator, selected)
            run([str(executable), '1' if selected else '0'], env=environment)
            records.append({'selected': selected, 'entryIndex': entry, 'allocatorIndex': allocator,
                            'executable': str(executable), 'sha256': hashlib.sha256(executable.read_bytes()).hexdigest()})
        packet = {'records': records, 'commands': commands,
                  'qualification': 'Actual C/O0 real command constructor and pinned allocator object. Original archive placement initializes the allocator first; selected closed anchor/order initializes the entry first. No full CLI, managed startup, Host, arena admission or normal profile.'}
        (scratch / 'result.json').write_text(json.dumps(packet, indent=2) + '\n')
        print(json.dumps({'evidence': str(scratch / 'result.json'), 'records': records}))


if __name__ == '__main__':
    unittest.main()
