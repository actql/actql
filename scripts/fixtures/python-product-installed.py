"""Run inside an external installed consumer; never load repository assets."""
import argparse
from importlib import metadata
import json
import sys


def installed(version, mode):
    if metadata.version('actql-sdk') != version:
        raise AssertionError('Installed SDK cohort differs')
    if mode == 'sdk-only':
        for package in ('actql', 'actql-local-runtime', 'wasmtime', 'duckdb'):
            try:
                metadata.version(package)
            except metadata.PackageNotFoundError:
                pass
            else:
                raise AssertionError('Lightweight installation contains Local distribution: ' + package)
        import actql_sdk
        assert 'wasmtime' not in sys.modules and 'duckdb' not in sys.modules
        print(json.dumps({'mode': mode, 'version': version, 'sdk_only': True,
                          'local_executed': False}))
        return
    if metadata.version('actql') != version or metadata.version('actql-local-runtime') != version:
        raise AssertionError('Installed product/runtime cohort differs')
    from actql import Client
    # This is the actual product gate, not a metadata fallback. A missing public
    # factory or Result/recovery supplier fails instead of reporting success.
    with Client.open() as client:
        submission = client.new_submission()
        run = client.start_source('SELECT 1 AS n', format='sql', submission_ref=submission)
        state = run.wait()
        assert state['status'] == 'succeeded', state
        rows = run.result('answer').all(max_rows=1)
        assert rows == [{'n': 1}], rows
        assert run.result('answer').all(max_rows=1) == [{'n': 1}]
        original = dict(run.ref)
    with Client.open() as client:
        observed = client.lookup_submission(submission)
        assert observed['kind'] == 'ready' and dict(observed['admission']['ref']) == original
        run = client.attach(original)
        assert run.wait()['status'] == 'succeeded'
        assert run.result('answer').all(max_rows=1) == [{'n': 1}]
    print(json.dumps({'mode': mode, 'version': version, 'select1': True,
                      'reread': True, 'original_run_reused': True, 'closed': True}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--mode', choices=('sdk-only', 'local'), required=True)
    options = parser.parse_args()
    installed(options.version, options.mode)
