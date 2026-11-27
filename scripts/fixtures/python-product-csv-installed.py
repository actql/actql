"""Run one authored CSV case with the ordinary installed Python facade."""
from __future__ import annotations

import argparse
import asyncio
from collections.abc import Mapping
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from functools import partial
from hashlib import sha256
import inspect
import json
import os
from pathlib import Path
import runpy
import sqlite3
import sys

CASE_SHA256 = '085456d884d0efe87cf5f9a05e09d5c73809e4f88760cba43062b0c30c4bcb2b'


def plain(value):
    if isinstance(value, Mapping):
        return {key: plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(item) for item in value]
    return value


def verify_project(project, files):
    observed = {}
    for name, expected in files.items():
        path = project / name
        info = path.lstat()
        if path.is_symlink() or not path.is_file() or sha256(path.read_bytes()).hexdigest() != expected['sha256']:
            raise AssertionError('Original CSV project input changed: ' + name)
        observed[name] = [info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, expected['sha256']]
    return observed


def failure_codes(failure):
    result, observed = [], set()
    while failure is not None and len(result) < 8 and id(failure) not in observed:
        observed.add(id(failure))
        result.append(getattr(failure, 'code', None))
        failure = getattr(failure, 'original_error', None) or failure.__cause__ or failure.__context__
    return result


def readonly_store(project):
    path = project / '.actql/state/client.sqlite3'
    if not path.is_file() or path.is_symlink() or path.with_name(path.name + '-journal').exists():
        raise AssertionError('CSV result requires the original physically closed Store')
    return sqlite3.connect(path.as_uri() + '?mode=ro&immutable=1', uri=True)


def prove_no_submission(project):
    if not (project / '.actql/state/client.sqlite3').exists():
        return
    with closing(readonly_store(project)) as store:
        for namespace in ('client_submitted_intents', 'client_runs', 'public_index'):
            prefix = f'namespace:{len(namespace)}:{namespace}:'
            if store.execute('SELECT 1 FROM core_bytes WHERE key >= ? AND key < ? LIMIT 1',
                             (prefix, prefix[:-1] + ';')).fetchone() is not None:
                raise AssertionError('Invalid CSV declaration wrote an original Run row')


async def exercise(facade, command, files, prior, receipt):
    from actql import AsyncClient, Client
    from actql_sdk import ClientError

    with ThreadPoolExecutor(max_workers=1) as thread:
        async def call(method, *args, **options):
            if facade == 'sync':
                return await asyncio.get_running_loop().run_in_executor(thread, partial(method, *args, **options))
            value = method(*args, **options)
            return await value if inspect.isawaitable(value) else value

        async def close(client):
            await call(client.close if facade == 'sync' else client.aclose)
            receipt['first_close'] = True

        try:
            api = Client if facade == 'sync' else AsyncClient
            client = await call(api.connect, mode='local')
        except ClientError as refusal:
            cleanup = getattr(refusal, 'cleanup_client', None)
            if cleanup is not None:
                await close(cleanup)
            if (command is not None or receipt['first_close'] is not True
                    or refusal.code != 'LocalClientInitializationCleanupPending'
                    or -31 not in failure_codes(refusal)):
                raise
            receipt['refusal_codes'] = failure_codes(refusal)
            return

        try:
            if command is None:
                raise AssertionError('Invalid second CSV declaration returned a Client')
            if prior is None:
                text = files[command['file']]['wire']
                checked = await call(client.check, text, kind='text', scope='bound_input', format='sql')
                if checked.outcome != 'completed' or checked.report.verdict != 'verified':
                    raise AssertionError('CSV Check refused its exact declaration')
                if receipt['source_opens']:
                    raise AssertionError('CSV Check acquired a physical Source')
                submission = await call(client.new_submission)
                receipt['submissions'] += 1
                run = await call(client.start_source, text, format='sql', read_only=True, submission_ref=submission)
                state = await call(run.wait)
            else:
                submission = prior['submission']
                found = await call(client.lookup_submission, submission)
                if found['kind'] != 'ready' or plain(found['admission']['ref']) != prior['run']:
                    raise AssertionError('CSV Saved lookup returned a different original')
                run = await call(client.attach, prior['run'])
                state = await call(run.status)
            if state['status'] != 'succeeded' or len(state.result_availability) != 1:
                raise AssertionError('CSV Run lacks its single completed Result')
            name, = state.result_availability
            result = await call(run.result, name)
            rows = await call(result.all, max_rows=8, max_wire_bytes=65536)
            if (rows != command['rows'] or any(list(row) != [c['name'] for c in command['columns']]
                                               for row in rows)):
                raise AssertionError('CSV Result rows differ from the original typed oracle')
            receipt.update(run=plain(run.ref), run_id=state['run_id'], submission=plain(submission),
                           result=name, rows=rows)
            if prior is not None:
                for key in ('run', 'run_id', 'submission', 'result', 'rows'):
                    if receipt[key] != prior[key]:
                        raise AssertionError('CSV Saved read changed the original ' + key)
        finally:
            await close(client)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', required=True)
    parser.add_argument('--facade', choices=('sync', 'async'), required=True)
    parser.add_argument('--phase', choices=('initial', 'saved', 'refuse'), required=True)
    parser.add_argument('--command')
    parser.add_argument('--prior', type=Path)
    parser.add_argument('--cohort', type=Path, required=True)
    parser.add_argument('--source', required=True)
    args = parser.parse_args()
    from actql_sdk._local_distribution import installed_local_components

    project = Path.cwd().resolve(strict=True)
    here = Path(__file__).resolve().parent
    original = (here / 'python-csv-project-cases.json').read_bytes()
    if sha256(original).hexdigest() != CASE_SHA256:
        raise AssertionError('CSV case index changed')
    selected, = [case for case in json.loads(original)['cases'] if case['id'] == args.case]
    command = next((item for item in selected['sql'] if item['file'] == args.command), None)
    if ((args.phase == 'refuse') != (args.case == 'invalid-second-declaration')
            or (args.phase == 'refuse') != (command is None)
            or (args.phase == 'saved') != (args.prior is not None)):
        raise AssertionError('CSV phase does not select an original case')
    before = verify_project(project, selected['files'])
    actual = installed_local_components()
    cohort = json.loads(args.cohort.read_bytes())
    identities = {key: getattr(actual, key) for key in
                  ('source_sha', 'module_sha256', 'image_sha256', 'artifact_sha256', 'package_version')}
    if identities['source_sha'] != args.source or any(cohort[key] != value for key, value in identities.items()):
        raise AssertionError('CSV consumer resolved a different installed runtime')
    receipt = dict(pid=os.getpid(), source=identities, case=args.case, facade=args.facade,
                   phase=args.phase, command=args.command, first_close=None,
                   submissions=0, source_opens=[], original_inputs=before)
    prior = json.loads(args.prior.read_bytes()) if args.prior is not None else None
    if prior is not None:
        if (prior['pid'] == receipt['pid'] or prior['phase'] != 'initial' or prior['first_close'] is not True
                or any(prior[key] != receipt[key] for key in ('source', 'case', 'facade', 'command', 'original_inputs'))):
            raise AssertionError('CSV Saved phase lacks the original initial receipt')
    watch = {name: Path(name).name for name in selected['files'] if name.endswith('.csv')}
    watch |= {str(project / name): basename for name, basename in list(watch.items())}
    watch |= {basename: basename for basename in watch.values()}
    observing = True

    def audit(event, arguments):
        if observing and event == 'open' and isinstance(arguments[0], (str, bytes)):
            name = os.fsdecode(arguments[0])
            if name in watch:
                flags = arguments[2]
                receipt['source_opens'].append(watch[name])
                if flags & (os.O_WRONLY | os.O_RDWR | os.O_TRUNC | os.O_CREAT):
                    raise AssertionError('CSV fixture attempted a physical write')
            elif args.phase != 'initial' and name in ('data', str(project / 'data')):
                raise AssertionError('CSV refusal or Saved acquired the physical Source root')

    sys.addaudithook(audit)
    try:
        asyncio.run(exercise(args.facade, command, selected['files'], prior, receipt))
    finally:
        observing = False
    expected_opens = [Path(command['file']).stem + '.csv'] if args.phase == 'initial' else []
    if (receipt['first_close'] is not True or receipt['submissions'] != (args.phase == 'initial')
            or receipt['source_opens'] != expected_opens or before != verify_project(project, selected['files'])):
        raise AssertionError('CSV consumer did not preserve its original Source lifecycle')
    if command is None:
        prove_no_submission(project)
    else:
        helper = runpy.run_path(str(here / 'python_csv_publication.py'))['read_published_result_schemas']
        with closing(readonly_store(project)) as store:
            store.execute('BEGIN')
            receipt['publication'] = helper(store, receipt['run'], receipt['run_id'], {receipt['result']: command})
        if prior is not None and receipt['publication'] != prior['publication']:
            raise AssertionError('CSV Saved projection changed the closed Result schema or binding')
    print(json.dumps(receipt, ensure_ascii=False))


if __name__ == '__main__':
    main()
