"""One existing failed C fixture, fresh process; no compiler or producer."""
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile

SOURCE = 'a14bf70216e626b351a08060a97005bf55ad3632'
RUN, ARTIFACT = 43398478059, 14024660342
ZIP_BYTES = 1985507
ZIP_SHA = 'bc1b11e4b41c73e8a29cf4beec89f078bce10ca4d79253df0c386f6381f2373c'
BINARY_BYTES = 5386296
BINARY_SHA = '5cfda23fef48a5b6ab56cb8a67151e7d16f71932f18fbd063465a6cbf72a9285'
ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ['RUNNER_TEMP']) / 'crypto-close-replay'


def main():
    assert (platform.system(), platform.machine()) == ('Linux', 'x86_64')
    current = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    assert current == os.environ['GITHUB_SHA']
    assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
    subprocess.run(['git', 'diff', '--exit-code', SOURCE, current, '--',
                    'packages/python-local-runtime/native/crypto-component',
                    'packages/python-local-runtime/native/pre-root',
                    'scripts/produce-native-crypto-component.py'], cwd=ROOT, check=True)
    OUT.mkdir(mode=0o700)
    report = {'diagnosticSource': current, 'binarySource': SOURCE, 'originalRun': RUN,
              'originalAttempt': 1, 'artifactId': ARTIFACT, 'compilerInvocations': 0,
              'scope': 'Same failed ELF, one fresh partial process; no cleanup success claim',
              'observed': False}
    try:
        base = 'https://api.github.com/repos/actql/actql/actions/'
        headers = {'Authorization': 'Bearer ' + os.environ['GITHUB_TOKEN'],
                   'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}

        def api(path):
            with urllib.request.urlopen(urllib.request.Request(base + path, headers=headers), timeout=30) as r:
                raw = r.read(1048577)
            assert len(raw) <= 1048576
            return json.loads(raw)

        run, artifact = api('runs/' + str(RUN)), api('artifacts/' + str(ARTIFACT))
        assert run['head_sha'] == SOURCE and run['run_attempt'] == 1
        assert run['status'] == 'completed' and run['conclusion'] == 'failure'
        assert artifact['workflow_run']['id'] == RUN and artifact['workflow_run']['head_sha'] == SOURCE
        assert artifact['size_in_bytes'] == ZIP_BYTES and artifact['digest'] == 'sha256:' + ZIP_SHA
        assert not artifact['expired']

        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, fp, code, message, response_headers, new_url):
                return None

        try:
            urllib.request.build_opener(NoRedirect).open(
                urllib.request.Request(base + 'artifacts/' + str(ARTIFACT) + '/zip', headers=headers), timeout=30)
        except urllib.error.HTTPError as r:
            assert r.code == 302 and r.headers['Location'].startswith('https://')
            location = r.headers['Location']
            r.close()
        else:
            raise ValueError('Expected original HTTPS artifact redirect')
        # Do not forward the credential to signed artifact storage.
        with urllib.request.urlopen(location, timeout=30) as r:
            raw = r.read(ZIP_BYTES + 1)
        assert len(raw) == ZIP_BYTES and hashlib.sha256(raw).hexdigest() == ZIP_SHA
        z = zipfile.ZipFile(io.BytesIO(raw))
        assert sorted(z.namelist()) == ['allocator-conformance', 'inputs.json', 'partial.stderr', 'partial.stdout', 'summary.json']
        assert sum(i.file_size for i in z.infolist()) < 8 * 1024 * 1024
        old = json.loads(z.read('summary.json'))
        assert old['source'] == SOURCE and old['passed'] is False
        assert [(c['case'], c['passed']) for c in old['cases']] == [
            ('bounded-search', True), ('split-merge-membership', True), ('partial', False)]
        binary = z.read('allocator-conformance')
        assert len(binary) == BINARY_BYTES and hashlib.sha256(binary).hexdigest() == BINARY_SHA
        assert old['binary'] == {'bytes': BINARY_BYTES, 'sha256': BINARY_SHA}
        executable = OUT / 'allocator-conformance'
        executable.write_bytes(binary)
        executable.chmod(0o700)
        (OUT / 'original-inputs.json').write_bytes(z.read('inputs.json'))
        script = OUT / 'close.gdb'
        script.write_text('set pagination off\nset confirm off\nset print elements 256\n'
            'handle SIGABRT stop nopass print\ninfo signals SIGABRT\n'
            'file ' + str(executable) + '\n'
            'break __assert_fail\nrun partial\n'
            'printf "ACTQL_ORIGINAL_ASSERT\\n"\nx/s $rdi\nbt 12\n'
            # File-local state must not resolve to libc's unrelated state.
            # Offsets are from this exact, hash-pinned ELF's symbol table.
            'set $base = (char*)&actql_crypto_component_inventory - 0x67f00\n'
            'set $s = *(char**)($base + 0x48e550)\n'
            'printf "ACTQL_COMPONENT_STATE_HEADER\\n"\nx/18gx $s\n'
            'printf "ACTQL_COMPONENT_GLOBAL_ACKS\\n"\n'
            'x/1ub $base + 0x48e56c\nx/1ub $base + 0x48e570\nx/1ub $base + 0x48e564\n'
            'disassemble actql_crypto_component_inventory\n'
            'continue\nprintf "ACTQL_STOP_AFTER_ORIGINAL_ASSERT\\n"\nbt 12\nquit\n')
        result = subprocess.run(['/usr/bin/gdb', '--nx', '--nh', '--batch', '-x', str(script)],
                                cwd=ROOT, capture_output=True, text=True, timeout=45)
        assert len(result.stdout) + len(result.stderr) < 1048576
        (OUT / 'gdb.stdout').write_text(result.stdout)
        (OUT / 'gdb.stderr').write_text(result.stderr)
        report['debuggerExit'] = result.returncode
        report['observed'] = (result.returncode == 0 and
            'ACTQL_COMPONENT_STATE_HEADER' in result.stdout and
            'ACTQL_STOP_AFTER_ORIGINAL_ASSERT' in result.stdout and
            'actql_crypto_component_close() == 0' in result.stdout and
            'received signal SIGABRT' in result.stdout)
        return 0 if report['observed'] else 1
    finally:
        (OUT / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    sys.exit(main())
