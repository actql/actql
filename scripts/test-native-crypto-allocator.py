"""Bounded real allocator conformance; reuse the original Crypto static inputs."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('crypto_producer', ROOT / 'scripts/produce-native-crypto-component.py')
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)
MODES = ('bounded-search', 'split-merge-membership', 'partial')


def check(args: argparse.Namespace) -> int:
    args.output.mkdir(parents=True, exist_ok=False)
    report = {'scope': 'actual private C allocator; not ordinary or elapsed performance acceptance',
              'source': args.source, 'cases': [], 'passed': False, 'commands': []}
    deadline = time.monotonic() + args.seconds

    def save() -> None:
        (args.output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(command: list[str], label: str) -> subprocess.CompletedProcess:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Allocator conformance deadline exhausted')
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                timeout=min(60, remaining))
        if len(result.stdout.encode()) + len(result.stderr.encode()) > 1024 * 1024:
            raise ValueError('Allocator conformance output limit')
        (args.output / (label + '.stdout')).write_text(result.stdout)
        (args.output / (label + '.stderr')).write_text(result.stderr)
        report['commands'].append({'name': label, 'command': command, 'exit': result.returncode})
        save()
        return result

    def prepare(command: list[str], label: str) -> str:
        result = run(command, label)
        if result.returncode:
            raise ValueError(label + ' failed: ' + result.stderr)
        return result.stdout

    try:
        source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        if source != args.source or subprocess.check_output(
                ['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT, text=True):
            raise ValueError('Clean exact allocator Source required')
        recipe_path = P.SOURCE / 'source.json'
        recipe = json.loads(recipe_path.read_bytes())
        inputs = {str(recipe_path): P.original(recipe_path), str(args.clang): P.original(args.clang, 512 * 1024 * 1024)}
        for name, expected in recipe['local'].items():
            actual = P.original(P.SOURCE / name)
            if actual != expected:
                raise ValueError('Stale Crypto source identity: ' + name)
            inputs[str(P.SOURCE / name)] = actual
        system = platform.system(), platform.machine()
        linux = system == ('Linux', 'x86_64')
        if linux:
            if (args.openssl_prefix is not None or
                    (args.crypto_producer is None) == (args.openssl_package_archive is None)):
                raise ValueError('Select one explicit Linux producer or diagnostic package input')
            selected = recipe['source_targets'][P.LINUX_TARGET]
            if args.openssl_package_archive is not None:
                # Temporary validation ref only. No normal producer receipt is
                # manufactured and no component DSO is built for this C test.
                prefix = args.output / 'openssl-input'
                package_inputs = P.prepare_linux_package_inputs(prefix, args.openssl_package_archive, selected)
                inputs.update(package_inputs['inputs'])
                report['packageArchives'] = package_inputs['packages']
                inputs[str(ROOT / 'scripts/produce-native-crypto-component.py')] = P.original(ROOT / 'scripts/produce-native-crypto-component.py')
                tool = Path('/usr/bin/dpkg-deb').resolve(strict=True)
                inputs[str(tool)] = P.original(tool)
            else:
                producer_pin = P.original(args.crypto_producer, 8 * 1024 * 1024)
                with args.crypto_producer.open('rb') as stream:
                    raw = stream.read(8 * 1024 * 1024 + 1)
                if {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()} != producer_pin:
                    raise ValueError('Original Crypto producer receipt changed')
                producer = json.loads(raw)
                inputs[str(args.crypto_producer)] = producer_pin
                prefix = args.crypto_producer.parent / 'openssl-input'
                if producer['source'] != source or producer['target'] != P.LINUX_TARGET:
                    raise ValueError('Foreign original Crypto producer')
                for name, expected in {**inputs, **P.linux_member_inputs(prefix, selected)}.items():
                    if name != str(args.crypto_producer) and producer['inputs'].get(name) != expected:
                        raise ValueError('Original Crypto producer input mismatch: ' + name)
                    inputs[name] = expected
            archive = prefix / selected['archive']['path']
            includes = [prefix / 'include', prefix / 'include/x86_64-linux-gnu']
            target = ['--target', P.LINUX_TARGET]
            flags = ['-D' + value for value in ('_GNU_SOURCE', 'ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN',
                     'ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY', 'ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=1',
                     'ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES=32')]
            # This C fixture uses no stock File allocation. Its single finite
            # diagnostic slot and existing 24-byte record/8-byte table header
            # are not an installed Local control envelope.
            libraries = ['-ldl', '-lpthread', '-lm']
        else:
            if (system != ('Darwin', 'arm64') or args.openssl_prefix is None
                    or args.crypto_producer is not None or args.openssl_package_archive is not None):
                raise ValueError('Only selected Linux or explicit Darwin arm64 diagnostic inputs')
            prefix = args.openssl_prefix.resolve(strict=True)
            archive = prefix / 'lib/libcrypto.a'
            if P.original(archive) != {key: recipe['candidate_static_input'][key] for key in ('bytes', 'sha256')}:
                raise ValueError('Original Darwin static archive mismatch')
            inputs[str(archive)] = P.original(archive)
            headers = []
            for path in sorted((prefix / 'include').rglob('*')):
                if path.is_symlink():
                    raise ValueError('Unqualified Darwin OpenSSL header alias')
                if path.is_file():
                    actual = P.original(path)
                    inputs[str(path)] = actual
                    headers.append({'path': str(path.relative_to(prefix / 'include')), **actual})
            digest = hashlib.sha256(json.dumps(headers, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
            selected = recipe['candidate_static_input']
            if len(headers) != selected['header_count'] or digest != selected['header_census_sha256']:
                raise ValueError('Original Darwin OpenSSL header membership mismatch')
            includes, target = [prefix / 'include'], []
            sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
            flags, libraries = ['-isysroot', sdk, '-mmacosx-version-min=26.0'], ['-lpthread']
        derived = args.output / 'original-provider'
        prepared = json.loads(prepare([sys.executable,
            str(ROOT / 'packages/python-local-runtime/native/pre-root/prepare_scoped_read.py'),
            '--moonbit', str(args.moon_home), '--destination', str(derived), *target], 'prepare-provider'))
        if prepared['status'] != 'review-source-only':
            raise ValueError('Original derived provider preparation required')
        flags.extend('-D' + value for value in prepared['required_defines'])
        flags.append('-DACTQL_SCOPED_READ_PROVIDER="' + str(derived / 'owned_capacity.c') + '"')
        common = [str(args.clang), '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *dict.fromkeys(flags),
                  '-I' + str(derived), *['-I' + str(path) for path in includes]]
        provider = args.output / 'provider.o'
        prepare([*common, *([] if linux else ['-D_DARWIN_C_SOURCE']), '-c', str(derived / 'owned_capacity.c'),
                 '-o', str(provider)], 'compile-provider')
        binary = args.output / 'allocator-conformance'
        prepare([*common, str(P.SOURCE / 'fixtures/allocator_conformance.c'), str(provider),
                 str(derived / 'libmoonbitrun.o'), str(derived / 'backtrace.c'),
                 str(derived / 'libbacktrace.a'), str(archive), *libraries, '-o', str(binary)], 'link-fixture')
        report['profile'] = ('linux-x64-pinned-package-diagnostic' if args.openssl_package_archive is not None
                             else 'linux-x64-original-normal-inputs') if linux else 'darwin-arm64-homebrew26-diagnostic'
        report['verifiedOriginalInputs'] = len(inputs)
        report['sourcePins'], report['binary'] = recipe['local'], P.original(binary)
        (args.output / 'inputs.json').write_text(json.dumps({'source': source, 'inputs': inputs,
                                                          'provider': prepared, 'profile': report['profile']}, indent=2) + '\n')
        # Each mode has a new process and original extent. Collect independent
        # failures after successful preparation, never share initialized state.
        for mode in MODES:
            result = run([str(binary), mode], mode)
            rows = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
            selected = [row for row in rows if row.get('case') == mode]
            passed = result.returncode == 0 and len(selected) == 1 and selected[0].get('passed') is True
            passed = passed and selected[0].get('original_cleanup') is True
            report['cases'].append({'case': mode, 'passed': passed, 'observations': rows})
            save()
        P.verify_original_inputs(inputs)
        if subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source:
            raise ValueError('Allocator Source changed')
        report['passed'] = len(report['cases']) == 3 and all(case['passed'] for case in report['cases'])
        return 0 if report['passed'] else 1
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        save()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True)
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--moon-home', type=Path, default=os.environ.get('MOON_HOME'))
    parser.add_argument('--crypto-producer', type=Path)
    parser.add_argument('--openssl-package-archive', type=Path, action='append')
    parser.add_argument('--openssl-prefix', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=150)
    args = parser.parse_args()
    if not args.moon_home or not 0 < args.seconds <= 300:
        parser.error('Pinned Moon toolchain and bounded 1..300 second budget required')
    sys.exit(check(args))
