"""Ordinary same-live-Host Runs, original Result rereads and cold Saved.

All lifecycle actions use the installed public Client. The optional inventory
record is a read-only, non-atomic diagnostic; it is never a cleanup action or
physical acknowledgement. No garbage collection or private retirement is used.
"""
from __future__ import annotations

import hashlib
from collections.abc import Mapping
import json
import os
from pathlib import Path
import sys
import time


ROOT = Path(__file__).resolve().parent


def plain(value):
    if isinstance(value, Mapping):
        return {key: plain(child) for key, child in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(child) for child in value]
    return value


def write_event(phase, **details):
    with (ROOT / 'events.jsonl').open('a', encoding='utf-8') as target:
        target.write(json.dumps({'pid': os.getpid(), 'phase': phase,
                                 'elapsed': time.monotonic() - START, **details}) + '\n')
        target.flush()


def inventory(client):
    host = client._client._local_host
    names = ('_prepared_inputs', '_run_loans', '_public_run_references', '_run_state_custody',
             '_run_publications', '_row_outputs', '_run_rows', '_journal_outputs',
             '_physical_starts', '_source_free_computes', '_source_free_invocations',
             '_publication_preflights', '_publishers', '_tasks', '_result_exports',
             '_result_chunks', '_publications', '_saved_result_reads', '_payloads',
             '_inputs', '_response_streams', '_projections', '_physical_work')
    counts = {name: len(getattr(host, name)) for name in names}
    counts['stopped_work'] = sum(work.stopped for work in tuple(host._physical_work))
    counts['core_loans'] = len(host._core._loans)
    counts['core_task_loans'] = len(host._core._task_loans)
    counts['custody_runs'] = len(host._runs._runs)
    counts['custody_preparations'] = len(host._preparation._preparations)
    counts['core_retained_work'] = host._core._host_retained_work is not None
    return counts


SETTLED_COUNTS = (
    '_physical_work', '_tasks', 'core_task_loans', '_result_exports', '_result_chunks',
    '_run_loans', 'custody_runs', '_public_run_references', '_run_state_custody',
    '_prepared_inputs', 'custody_preparations', '_saved_result_reads', '_response_streams',
)


def settled_inventory(client, mode, ordinal):
    # These checkpoints follow successful worker wait and all Result reader
    # closes. No failed, pending or concurrent work belongs to this fixture.
    observed = inventory(client)
    if any(observed[name] != 0 for name in SETTLED_COUNTS) or observed['core_retained_work']:
        write_event('retirement-pending', mode=mode, ordinal=ordinal, inventory=observed)
        raise AssertionError('Successful ordinary execution or closed reader remains held')
    return observed


def record_reference(references, ordinal, submission, run=None):
    # Keep the signed submission in the private replay input only. The
    # artifact carries a fingerprint and the synthetic Run definition CID.
    encoded = json.dumps(submission, sort_keys=True, separators=(',', ':')).encode('utf-8')
    reference = {'ordinal': ordinal, 'submission_sha256': hashlib.sha256(encoded).hexdigest()}
    if run is not None:
        reference['run_definition_cid'] = run['runDefinitionCid']
        references[-1] = reference
    else:
        references.append(reference)
    temporary = ROOT / 'original-reference.pending'
    temporary.write_text(json.dumps({'producer_pid': os.getpid(), 'runs': references}) + '\n',
                         encoding='utf-8')
    temporary.replace(ROOT / 'original-reference.json')


def rows(run, expected):
    state = run.status()
    assert state['status'] == 'succeeded'
    actual = run.result('answer').all(max_rows=1)
    assert type(actual) is list and len(actual) == 1
    assert type(actual[0]) is dict and set(actual[0]) == {'n'}
    assert type(actual[0]['n']) is int and actual[0]['n'] == expected


def failure_data(error):
    result = {'type': type(error).__name__}
    code = getattr(error, 'code', None)
    if type(code) is str and len(code) <= 256:
        result['code'] = code
    return result


def run_phase(phase):
    from actql import Client
    client = None
    failed = False
    try:
        client = Client.open()
        write_event('opened', mode=phase, inventory=inventory(client))
        if phase == 'warm':
            originals, executions, references = [], [], []
            for ordinal in range(1, 11):
                submission = client.new_submission()
                submission_data = plain(submission)
                record_reference(references, ordinal, submission_data)
                write_event('submission-created', ordinal=ordinal)
                expected = 40 + ordinal
                execution = client.start_source(f'SELECT {expected} AS n', format='sql',
                                                submission_ref=submission)
                original = {'ordinal': ordinal, 'expected': expected,
                            'submission': submission_data, 'run': plain(execution.ref)}
                record_reference(references, ordinal, submission_data, original['run'])
                assert all(item['run'] != original['run'] for item in originals)
                originals.append(original)
                # Persist every actual reference before its first wait.
                temporary = ROOT / 'originals.pending.json'
                temporary.write_text(json.dumps({'producer_pid': os.getpid(), 'runs': originals}) + '\n')
                temporary.replace(ROOT / 'originals.json')
                write_event('original-recorded-before-wait', ordinal=ordinal)
                assert execution.wait()['status'] == 'succeeded'
                rows(execution, expected)
                executions.append(execution)
                write_event('result-complete', ordinal=ordinal, inventory=inventory(client))
                if ordinal in (1, 3, 10):
                    for prior, item in zip(executions, originals):
                        rows(prior, item['expected'])
                        attached = client.attach(item['run'])
                        assert plain(attached.ref) == item['run']
                        rows(attached, item['expected'])
                    write_event('checkpoint-complete', ordinal=ordinal, retirement_checked=True,
                                inventory=settled_inventory(client, phase, ordinal))
            write_event('warm-complete', runs=len(originals), inventory=inventory(client))
        elif phase == 'saved':
            original = json.loads((ROOT / 'originals.json').read_text())
            assert original['producer_pid'] != os.getpid()
            assert len(original['runs']) == 10
            for item in original['runs']:
                observed = client.lookup_submission(item['submission'])
                assert observed['kind'] == 'ready'
                assert plain(observed['admission']['ref']) == item['run']
                execution = client.attach(item['run'])
                assert plain(execution.ref) == item['run']
                rows(execution, item['expected'])
                write_event('saved-result-complete', ordinal=item['ordinal'])
            write_event('saved-complete', runs=10, retirement_checked=True,
                        inventory=settled_inventory(client, phase, 10))
        else:
            raise ValueError('Unknown repeated-Host fixture phase')
    except BaseException as primary:
        failed = True
        write_event('primary-failure', mode=phase, error=failure_data(primary))
        raise
    finally:
        if client is not None:
            write_event('first-close-attempted', mode=phase, inventory=inventory(client))
            try:
                client.close()
            except BaseException as cleanup:
                write_event('first-close-failed', mode=phase, error=failure_data(cleanup))
                if not failed:
                    raise
            else:
                write_event('first-close-returned', mode=phase, physical_release_observed=False)


START = time.monotonic()
if __name__ == '__main__':
    run_phase(sys.argv[1])
