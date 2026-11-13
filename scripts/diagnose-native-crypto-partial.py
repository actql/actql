"""Temporary one-process Linux partial diagnostic; never a release producer."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import platform
import re
import shlex
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('crypto_producer', ROOT / 'scripts/produce-native-crypto-component.py')
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)
MARKER = 'ACTQL_CRYPTO_PARTIAL_GDB '


def assess(gdb_status: int, stdout: str) -> dict:
    observations = [json.loads(line[len(MARKER):]) for line in stdout.splitlines() if line.startswith(MARKER)]
    if len(observations) != 1:
        raise ValueError('Exactly one debugger observation required')
    observed = observations[0]
    rows = [json.loads(line) for line in stdout.splitlines() if line.startswith('{')]
    rows = [row for row in rows if row.get('case') == 'partial']
    passed = (gdb_status == 0 and observed.get('inferiorExitCode') == 0
              and observed.get('signal') is None and not observed.get('debuggerError')
              and not observed.get('watchdogFired')
              and not observed.get('killedAfterStop') and len(rows) == 1
              and rows[0].get('passed') is True and rows[0].get('original_cleanup') is True)
    return {'passed': passed, 'gdbExitCode': gdb_status, 'observed': observed,
            'case': None if len(rows) != 1 else {key: rows[0].get(key) for key in ('case', 'passed', 'original_cleanup')}}


def debugger_script(binary: Path, stages: list[tuple[str, str]]) -> str:
    # No locals, arguments, memory, core dump, instruction operands or payloads
    # are captured. One original inferior runs once; an observed signal is a
    # failure and the debugger explicitly retires its stopped process.
    return '\n'.join([
        'set pagination off', 'set confirm off', 'set print frame-arguments none',
        'set auto-load off', 'set debuginfod enabled off', 'set startup-with-shell off',
        'set disable-randomization off', 'handle SIGSEGV stop nopass print',
        'file ' + str(binary), 'set args partial', 'python',
        'import gdb, json, os, re, signal, threading',
        "observed = {'stages': [], 'signal': None, 'inferiorExitCode': None, 'stack': [], 'killedAfterStop': False, 'watchdogFired': False}",
        'class Stage(gdb.Breakpoint):',
        '    def __init__(self, location, label):',
        '        super().__init__(location, internal=True)',
        '        self.label = label',
        '    def stop(self):',
        "        if len(observed['stages']) < 32: observed['stages'].append(self.label)",
        '        return False',
        'def exited(event):',
        "    if not observed['killedAfterStop']: observed['inferiorExitCode'] = getattr(event, 'exit_code', None)",
        'def stopped(event):',
        '    if isinstance(event, gdb.SignalEvent):',
        "        observed['signal'] = event.stop_signal",
        'gdb.events.exited.connect(exited)', 'gdb.events.stop.connect(stopped)',
        'def interrupt_owned_debugger():',
        "    observed['watchdogFired'] = True",
        '    os.kill(os.getpid(), signal.SIGINT)',
        'timer = threading.Timer(30, interrupt_owned_debugger)',
        'timer.daemon = True',
        'try:',
        "    policy = gdb.execute('info signals SIGSEGV', to_string=True)",
        "    selected = re.search(r'^SIGSEGV\\s+(Yes|No)\\s+(Yes|No)\\s+(Yes|No)\\b', policy, re.M)",
        "    if selected is None or selected.groups() != ('Yes', 'Yes', 'No'): raise RuntimeError('Signal stop policy mismatch')",
        "    observed['signalPolicy'] = {'stop': True, 'print': True, 'pass': False}",
        '    for location, label in ' + repr(stages) + ': Stage(location, label)',
        '    timer.start()',
        "    gdb.execute('run', to_string=False)",
        "    if observed['signal'] is not None:",
        '        frame = gdb.newest_frame()',
        "        while frame is not None and len(observed['stack']) < 32:",
        "            name = frame.name() or '<unknown>'",
        "            name = name if re.fullmatch(r'[A-Za-z0-9_.$<>?]+', name) else '<unavailable>'",
        '            sal = frame.find_sal()',
        "            observed['stack'].append({'function': name, 'file': None if sal.symtab is None else os.path.basename(sal.symtab.filename), 'line': sal.line or None})",
        '            frame = frame.older()',
        'except BaseException as error:',
        "    observed['debuggerError'] = type(error).__name__",
        'finally:',
        '    timer.cancel()',
        '    if gdb.selected_inferior().pid:',
        "        observed['killedAfterStop'] = True",
        "        gdb.execute('kill', to_string=True)",
        '    print(' + repr(MARKER) + ' + json.dumps(observed, sort_keys=True))',
        'end', 'quit', '',
    ])


def diagnose(args: argparse.Namespace) -> int:
    if (platform.system(), platform.machine()) != ('Linux', 'x86_64'):
        raise ValueError('This diagnostic requires actual Linux x86-64')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if source != args.source or subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True):
        raise ValueError('Exact clean committed diagnostic Source required')
    args.output.mkdir(parents=True, exist_ok=False)
    deadline = time.monotonic() + args.seconds
    report = {'scope': 'one original Linux 4096-byte partial under debugger; not normal or performance acceptance',
              'source': source, 'sourceProductUnmodified': True, 'passed': False, 'commands': []}
    inputs = {}

    def save():
        (args.output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(command, label, *, text=True, maximum=4 * 1024 * 1024):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Diagnostic total deadline exhausted')
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=text, timeout=min(60, remaining))
        raw_out = result.stdout.encode() if text else result.stdout
        raw_err = result.stderr.encode() if text else result.stderr
        if len(raw_out) + len(raw_err) > maximum:
            raise ValueError('Bounded diagnostic command output exceeded')
        (args.output / (label + '.stdout')).write_bytes(raw_out)
        (args.output / (label + '.stderr')).write_bytes(raw_err)
        report['commands'].append({'label': label, 'command': command, 'exit': result.returncode})
        save()
        return result

    def prepare(command, label):
        result = run(command, label)
        if result.returncode:
            raise ValueError('Diagnostic preparation failed: ' + label)
        return result.stdout

    try:
        recipe_path = P.SOURCE / 'source.json'
        recipe = json.loads(recipe_path.read_bytes())
        inputs[str(recipe_path)] = P.original(recipe_path)
        for name, expected in recipe['local'].items():
            path = P.SOURCE / name
            inputs[str(path)] = P.original(path)
            if inputs[str(path)] != expected:
                raise ValueError('Changed pinned Crypto Source: ' + name)
        selected = recipe['source_targets'][P.LINUX_TARGET]
        archives = []
        for expected in (selected['package'], selected['license']['package']):
            path = args.output / (expected['name'] + '.deb')
            with urllib.request.urlopen(expected['url'], timeout=min(30, deadline - time.monotonic())) as stream:
                if not stream.url.startswith('https://'):
                    raise ValueError('HTTPS package input required')
                data = stream.read(expected['bytes'] + 1)
            if len(data) != expected['bytes'] or hashlib.sha256(data).hexdigest() != expected['sha256']:
                raise ValueError('Exact official package bytes/hash required')
            path.write_bytes(data)
            archives.append(path)
        prefix = args.output / 'openssl-input'
        packages = P.prepare_linux_package_inputs(prefix, archives, selected)
        inputs.update(packages['inputs'])
        tools = {name: path.resolve(strict=True) for name, path in
                 [('clang', args.clang), ('gdb', args.gdb), ('dpkg-deb', Path('/usr/bin/dpkg-deb'))]}
        for path in [*tools.values(), Path(__file__).resolve(), ROOT / 'scripts/produce-native-crypto-component.py']:
            inputs[str(path)] = P.original(path, 512 * 1024 * 1024)
        target = prepare([str(tools['clang']), '-dumpmachine'], 'compiler-target').strip()
        if re.fullmatch(r'x86_64-(?:[A-Za-z0-9_.]+-)?linux-gnu', target) is None:
            raise ValueError('Actual Linux x86-64 compiler required')
        version = prepare([str(tools['clang']), '--version'], 'compiler-version')
        if not re.search(r'clang version 19\.', version):
            raise ValueError('Original clang19 major required')
        report['compilerVersion'] = version
        report['gdbVersion'] = prepare([str(tools['gdb']), '--version'], 'debugger-version')
        derived = args.output / 'original-provider'
        prepared = json.loads(prepare([sys.executable, str(ROOT / 'packages/python-local-runtime/native/pre-root/prepare_scoped_read.py'),
                                      '--moonbit', str(args.moon_home), '--destination', str(derived),
                                      '--target', P.LINUX_TARGET], 'prepare-provider'))
        if prepared['status'] != 'review-source-only' or prepared['target'] != P.LINUX_TARGET:
            raise ValueError('Same original selected provider Source required')
        flags = ['-D' + value for value in ['_GNU_SOURCE', 'ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN',
                 'ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY', 'ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=1',
                 'ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES=32', *prepared['required_defines']]]
        flags.append('-DACTQL_SCOPED_READ_PROVIDER="' + str(derived / 'owned_capacity.c') + '"')
        common = [str(tools['clang']), '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror',
                  *dict.fromkeys(flags), '-I' + str(derived), '-I' + str(prefix / 'include'),
                  '-I' + str(prefix / 'include/x86_64-linux-gnu')]
        provider = args.output / 'provider.o'
        prepare([*common, '-MD', '-MF', str(args.output / 'provider.d'), '-c', str(derived / 'owned_capacity.c'),
                 '-o', str(provider)], 'compile-provider')
        fixture_object = args.output / 'fixture.o'
        prepare([*common, '-MD', '-MF', str(args.output / 'fixture.d'), '-c',
                 str(P.SOURCE / 'fixtures/allocator_conformance.c'), '-o', str(fixture_object)], 'compile-fixture')
        backtrace_object = args.output / 'backtrace.o'
        prepare([*common, '-MD', '-MF', str(args.output / 'backtrace.d'), '-c',
                 str(derived / 'backtrace.c'), '-o', str(backtrace_object)], 'compile-backtrace')
        binary = args.output / 'allocator-conformance'
        prepare([*common, str(fixture_object), str(provider), str(derived / 'libmoonbitrun.o'),
                 str(backtrace_object), str(derived / 'libbacktrace.a'),
                 str(prefix / selected['archive']['path']), '-ldl', '-lpthread', '-lm', '-o', str(binary)], 'link-fixture')
        # Record source/header inputs and original prebuilt provider members.
        for path in [derived / 'libmoonbitrun.o', derived / 'libbacktrace.a']:
            inputs[str(path)] = P.original(path)
        for dependency in [args.output / 'provider.d', args.output / 'fixture.d', args.output / 'backtrace.d']:
            for name in shlex.split(dependency.read_text().replace('\\\n', ' ').split(':', 1)[1]):
                path = Path(name).resolve(strict=True)
                inputs[str(path)] = P.original(path, 512 * 1024 * 1024)
        source_file = P.SOURCE / 'component.c'
        fixture_file = P.SOURCE / 'fixtures/allocator_conformance.c'
        def location(path, literal):
            lines = [index + 1 for index, line in enumerate(path.read_text().splitlines()) if literal in line]
            if len(lines) != 1:
                raise ValueError('One exact pinned Source stage required')
            return str(path) + ':' + str(lines[0])
        stages = [('actql_crypto_component_bind_current_with_custody', 'bind-enter'),
                  (location(source_file, 'if (OPENSSL_init_crypto('), 'openssl-init-before'),
                  (location(source_file, 'state->default_provider = OSSL_PROVIDER_load('), 'provider-load-before'),
                  (location(fixture_file, 'assert(acquired == 1);'), 'bind-returned'),
                  ('actql_crypto_component_close', 'close-enter'),
                  ('OPENSSL_thread_stop', 'openssl-thread-stop'), ('OPENSSL_cleanup', 'openssl-cleanup')]
        debugger = args.output / 'partial.gdb'
        debugger.write_text(debugger_script(binary, stages))
        report['binary'] = P.original(binary)
        report['instrumentation'] = {'debugSymbolsAdded': True, 'optimization': '-O2', 'partialBytes': 4096,
                                     'originalOwnerBytes': 6291456, 'runs': 1, 'stageBreakpoints': stages,
                                     'stoppedInferiorKilledByDebugger': 'only after signal; not original cleanup ACK'}
        (args.output / 'inputs.json').write_text(json.dumps({'source': source, 'packages': packages['packages'],
                                                         'provider': prepared, 'inputs': inputs}, indent=2) + '\n')
        result = run([str(tools['gdb']), '--nx', '--nh', '--batch', '-x', str(debugger)], 'partial-gdb')
        report['result'] = assess(result.returncode, result.stdout)
        P.verify_original_inputs(inputs)
        if (subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source
                or subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True)):
            raise ValueError('Diagnostic Source changed')
        report['passed'] = report['result']['passed']
        return 0 if report['passed'] else 1
    except Exception as error:
        report['diagnosticError'] = type(error).__name__
        raise
    finally:
        save()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True)
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--gdb', type=Path, required=True)
    parser.add_argument('--moon-home', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=180)
    arguments = parser.parse_args()
    if not 0 < arguments.seconds <= 300:
        parser.error('An existing bounded 1..300 second diagnostic budget is required')
    sys.exit(diagnose(arguments))
