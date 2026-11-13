"""One hard-coded failed diagnostic ELF, fresh process; no compiler or producer."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import os
import platform
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('partial_diagnostic', ROOT / 'scripts/diagnose-native-crypto-partial.py')
D = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(D)
BINARY_SOURCE = 'db7ac05a1ba7ac43d9bdb39570c00ab987b70b9b'
ORIGINAL_RUN = 43393813496
ARTIFACT = 14021199374
ZIP_BYTES = 2108545
ZIP_SHA = '19564e2da946328613041d6fcdfbabf4a5b796a459c395fe312f13d51b1d583f'
BINARY_BYTES = 5616424
BINARY_SHA = '7433ea743052d1a8b4d40ce01cff6c3c2935c246f926c206a70adacb89fe6847'
PRODUCT_PATHS = ['packages/python-local-runtime/native/crypto-component',
                 'packages/python-local-runtime/native/pre-root', 'scripts/produce-native-crypto-component.py']


def validate_original(data: bytes) -> tuple[dict, dict, bytes]:
    if len(data) != ZIP_BYTES or hashlib.sha256(data).hexdigest() != ZIP_SHA:
        raise ValueError('Exact original diagnostic ZIP required')
    with zipfile.ZipFile(io.BytesIO(data)) as container:
        names = container.namelist()
        if sorted(names) != ['allocator-conformance', 'inputs.json', 'summary.json']:
            raise ValueError('Only the exact three original diagnostic members required')
        if sum(member.file_size for member in container.infolist()) > 8 * 1024 * 1024:
            raise ValueError('Bounded original diagnostic members required')
        summary = json.loads(container.read('summary.json'))
        inputs = json.loads(container.read('inputs.json'))
        binary = container.read('allocator-conformance')
    if (summary['source'] != BINARY_SOURCE or inputs['source'] != BINARY_SOURCE
            or summary['passed'] is not False or summary['instrumentation']['runs'] != 1
            or summary['instrumentation']['partialBytes'] != 4096
            or summary['instrumentation']['originalOwnerBytes'] != 6291456):
        raise ValueError('Original failed same-partial scope required')
    if (len(binary) != BINARY_BYTES or hashlib.sha256(binary).hexdigest() != BINARY_SHA
            or summary['binary'] != {'bytes': BINARY_BYTES, 'sha256': BINARY_SHA}
            or binary[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', binary, 18)[0] != 62):
        raise ValueError('Exact original inert Linux x64 ELF required')
    return summary, inputs, binary


def replay(args: argparse.Namespace) -> int:
    if (platform.system(), platform.machine()) != ('Linux', 'x86_64'):
        raise ValueError('Actual matching Linux x64 host required')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if source != args.source or subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True):
        raise ValueError('Exact clean committed debugger Source required')
    subprocess.run(['git', 'diff', '--exit-code', BINARY_SOURCE, source, '--', *PRODUCT_PATHS], cwd=ROOT, check=True)
    args.output.mkdir(parents=True, exist_ok=False)
    report = {'scope': 'same inert failed ELF, ONE fresh partial process under corrected debugger; not ordinary acceptance',
              'diagnosticSource': source, 'binarySource': BINARY_SOURCE, 'originalRun': ORIGINAL_RUN,
              'originalAttempt': 1, 'artifact': ARTIFACT, 'compilerInvocations': 0, 'providerBuilds': 0,
              'passed': False, 'originalProductAndProviderSourceExact': True}
    deadline = time.monotonic() + 180
    def remaining(maximum):
        value = deadline - time.monotonic()
        if value <= 0:
            raise TimeoutError('Original replay deadline exhausted')
        return min(maximum, value)
    def save():
        (args.output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    try:
        token = os.environ['GITHUB_TOKEN']
        headers = {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
                   'X-GitHub-Api-Version': '2022-11-28'}
        base = 'https://api.github.com/repos/actql/actql/actions/'
        def api(path):
            request = urllib.request.Request(base + path, headers=headers)
            with urllib.request.urlopen(request, timeout=remaining(30)) as stream:
                raw = stream.read(1024 * 1024 + 1)
            if len(raw) > 1024 * 1024:
                raise ValueError('Bounded original GitHub metadata required')
            return json.loads(raw)
        run = api('runs/' + str(ORIGINAL_RUN))
        artifact = api('artifacts/' + str(ARTIFACT))
        if (run['head_sha'] != BINARY_SOURCE or run['run_attempt'] != 1
                or run['status'] != 'completed' or run['conclusion'] != 'failure'
                or run['path'] != '.github/workflows/performance-matrix.yml'
                or artifact['workflow_run']['id'] != ORIGINAL_RUN
                or artifact['workflow_run']['head_sha'] != BINARY_SOURCE
                or artifact['name'] != 'crypto-partial-diagnostic-' + BINARY_SOURCE
                or artifact['expired'] or artifact['size_in_bytes'] != ZIP_BYTES
                or artifact['digest'] != 'sha256:' + ZIP_SHA):
            raise ValueError('Exact failed original run/artifact association required')
        # Never forward the GitHub credential to the signed storage redirect.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, fp, code, message, response_headers, new_url):
                return None
        opener = urllib.request.build_opener(NoRedirect)
        try:
            opener.open(urllib.request.Request(base + 'artifacts/' + str(ARTIFACT) + '/zip', headers=headers), timeout=remaining(30))
        except urllib.error.HTTPError as response:
            if response.code != 302 or not response.headers['Location'].startswith('https://'):
                raise ValueError('Official HTTPS artifact redirect required')
            location = response.headers['Location']
            response.close()
        else:
            raise ValueError('Original artifact redirect missing')
        with urllib.request.urlopen(location, timeout=remaining(30)) as stream:
            data = stream.read(ZIP_BYTES + 1)
        original, old_inputs, binary = validate_original(data)
        # Check the exact original static archive, headers and product Sources
        # against their retained receipt, not this host's compiler/header files.
        recipe = json.loads((D.P.SOURCE / 'source.json').read_bytes())
        selected = recipe['source_targets'][D.P.LINUX_TARGET]
        for actual, expected in zip(old_inputs['packages'], [selected['package'], selected['license']['package']]):
            if any(actual[key] != expected[key] for key in ('bytes', 'sha256')):
                raise ValueError('Original pinned package receipt changed')
        for name, expected in recipe['local'].items():
            ending = '/packages/python-local-runtime/native/crypto-component/' + name
            matches = [value for path, value in old_inputs['inputs'].items() if path.endswith(ending)]
            if matches != [expected]:
                raise ValueError('Original Crypto Source receipt changed')
        executable = args.output / 'allocator-conformance'
        executable.write_bytes(binary)
        executable.chmod(0o700)  # This new private copy only; original ZIP stays immutable.
        debugger = args.output / 'partial.gdb'
        debugger.write_text(D.debugger_script(executable, original['instrumentation']['stageBreakpoints']))
        current_gdb = args.gdb.resolve(strict=True)
        current_inputs = {str(current_gdb): D.P.original(current_gdb, 512 * 1024 * 1024),
                          str(Path(__file__).resolve()): D.P.original(Path(__file__).resolve()),
                          str(ROOT / 'scripts/diagnose-native-crypto-partial.py'): D.P.original(ROOT / 'scripts/diagnose-native-crypto-partial.py')}
        receipt = {'binarySource': BINARY_SOURCE, 'diagnosticSource': source, 'originalInputs': old_inputs,
                   'originalArtifact': {'id': ARTIFACT, 'run': ORIGINAL_RUN, 'attempt': 1, 'bytes': ZIP_BYTES, 'sha256': ZIP_SHA},
                   'binary': original['binary'], 'currentDebuggerInputs': current_inputs,
                   'oldHostCompilerOrHeaderReceiptsAreNotCurrentHostEvidence': True,
                   'host': {'platform': platform.platform(), 'libc': platform.libc_ver()},
                   'debuggerVersion': subprocess.check_output([str(current_gdb), '--version'], text=True, timeout=10)}
        (args.output / 'inputs.json').write_text(json.dumps(receipt, indent=2) + '\n')
        result = subprocess.run([str(current_gdb), '--nx', '--nh', '--batch', '-x', str(debugger)],
                                cwd=ROOT, capture_output=True, text=True, timeout=remaining(60))
        if len(result.stdout.encode()) + len(result.stderr.encode()) > 4 * 1024 * 1024:
            raise ValueError('Bounded debugger output required')
        (args.output / 'private-gdb.stdout').write_text(result.stdout)
        (args.output / 'private-gdb.stderr').write_text(result.stderr)
        report['result'] = D.assess(result.returncode, result.stdout)
        report['originalBinary'] = D.P.original(executable)
        if report['originalBinary'] != original['binary']:
            raise ValueError('Original diagnostic executable bytes changed')
        D.P.verify_original_inputs(current_inputs)
        if (subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source
                or subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True)):
            raise ValueError('Debugger Source changed')
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
    parser.add_argument('--gdb', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    sys.exit(replay(parser.parse_args()))
