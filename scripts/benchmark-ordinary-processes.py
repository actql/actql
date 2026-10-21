"""Measure existing ordinary Native/Python installations, without a producer.

The JSON report feeds the existing performance assessor. A successful collector
exit means only that its selected public operations and cleanup completed.
Missing comparison, structure, history and boundary evidence cannot pass the
separate required assessment.
"""
import argparse
import base64
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import resource
import stat
import subprocess
import sys
import tarfile
import time
import uuid
import zipfile


EXPECTED = [{'id': 1}]
SQL = 'SELECT 1 AS id'
FIXTURE = (SQL + '\n[{"id":1}]\n').encode()
OPERATIONS = ('first-init', 'cold-existing', 'warm-select', 'warm-result', 'warm-status')


def wire(value):
    return json.dumps(value, separators=(',', ':'), ensure_ascii=False).encode()


def digest(value):
    return hashlib.sha256(value).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def platform_key():
    return {('Darwin', 'arm64'): 'darwin-arm64',
            ('Linux', 'x86_64'): 'linux-x64-gnu'}.get((platform.system(), platform.machine()))


def regular(path):
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode):
        raise ValueError(f'Expected installed regular payload: {path}')
    body = path.read_bytes()
    return {'bytes': len(body), 'mode': stat.S_IMODE(metadata.st_mode), 'sha256': digest(body)}


def safe_member(name):
    path = Path(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name or any(ord(c) < 32 for c in name):
        raise ValueError('Unsafe package member')


def verify_packages(adapter, manifest_path, consumer, source):
    """Compare actual formal packages and installed payloads, not filenames."""
    assert consumer.is_dir() and not consumer.is_symlink(), 'Installed consumer cannot be a source symlink'
    raw = manifest_path.read_bytes()
    manifest = json.loads(raw)
    if adapter == 'native':
        assert manifest['version'] == 'actql-native-cli-release/0.1'
        assert manifest['sourceSha'] == source
        key = platform_key()
        assert key in manifest['platforms'], 'No ordinary package for this actual platform'
        wanted = {'actql', '@actql/cli-' + key}
        assert wanted <= {p['name'] for p in manifest['packages']}
        payloads = {}
        for package in manifest['packages']:
            if package['name'] not in wanted:
                continue
            assert Path(package['file']).name == package['file']
            archive = manifest_path.parent / package['file']
            data = archive.read_bytes()
            assert len(data) == package['bytes'] and digest(data) == package['sha256']
            assert package['integrity'] == 'sha512-' + base64.b64encode(hashlib.sha512(data).digest()).decode()
            declared = {row['path']: row for row in package['files']}
            found = {}
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as tar:
                for member in tar:
                    if member.isdir():
                        continue
                    assert member.isfile() and member.name.startswith('package/')
                    name = member.name[8:]
                    safe_member(name)
                    assert name not in found
                    body = tar.extractfile(member).read()
                    found[name] = dict(path=name, bytes=len(body), mode=member.mode, sha256=digest(body))
            assert found == declared, 'Native tar payload set differs'
            prefix = Path() if package['name'] == 'actql' else Path('node_modules') / package['name']
            for name, row in found.items():
                payloads[(prefix / name).as_posix()] = {k: row[k] for k in ('bytes', 'mode', 'sha256')}
        executable = consumer / 'bin/actql.mjs'
        assert executable.is_file()
    else:
        assert manifest['source_sha'] == source and manifest['platform'] == platform_key()
        assert {row['distribution'] for row in manifest['wheels']} == {'actql', 'actql-sdk', 'actql-local-runtime'}
        payloads = {}
        for wheel in manifest['wheels']:
            assert Path(wheel['file']).name == wheel['file']
            data = (manifest_path.parent / 'wheels' / wheel['file']).read_bytes()
            assert len(data) == wheel['bytes'] and digest(data) == wheel['sha256']
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                names = [n for n in archive.namelist() if not n.endswith('/')]
                assert len(names) == len(set(names))
                record = next(n for n in names if n.endswith('.dist-info/RECORD'))
                table = list(csv.reader(io.StringIO(archive.read(record).decode())))
                assert len(table) == len(names) and {r[0] for r in table} == set(names)
                for name, expected_hash, size in table:
                    safe_member(name)
                    body = archive.read(name)
                    if name == record:
                        assert expected_hash == size == ''
                    else:
                        actual = base64.urlsafe_b64encode(hashlib.sha256(body).digest()).decode().rstrip('=')
                        assert expected_hash == 'sha256=' + actual and int(size) == len(body)
                    if '.dist-info/' not in name:
                        assert name not in payloads
                        payloads[name] = dict(bytes=len(body), mode=(archive.getinfo(name).external_attr >> 16) & 0o777,
                                              sha256=digest(body))
        # The consumer is its site-packages directory, never a source checkout.
        assert (consumer / 'actql/__init__.py').is_file()
    observed = {}
    for name, expected in payloads.items():
        for parent in Path(name).parents:
            directory = consumer / parent
            assert directory.is_dir() and not directory.is_symlink(), 'Installed product directory cannot be linked'
        actual = regular(consumer / name)
        assert actual == expected, f'Installed payload differs: {name}'
        observed[name] = actual
    assert observed, 'No installed ordinary product payloads'
    return manifest, digest(raw), observed


def command(executable, args, cwd, output, name):
    """The existing outer guard owns deadlines/process-tree cancellation."""
    started = time.perf_counter_ns()
    with (output / (name + '.stdout')).open('xb') as stdout, (output / (name + '.stderr')).open('xb') as stderr:
        env = {k: v for k, v in os.environ.items() if k not in
               ('NODE_OPTIONS', 'NODE_PATH', 'NODE_V8_COVERAGE', 'PYTHONPATH', 'PYTHONHOME',
                'ACTQL_NATIVE_TIMINGS', 'ACTQL_NATIVE_TIMINGS_RAW')}
        env['PYTHONDONTWRITEBYTECODE'] = '1'
        process = subprocess.Popen([str(executable), *args], cwd=cwd, env=env, stdout=stdout, stderr=stderr)
        _, status, usage = os.wait4(process.pid, 0)
        code = os.waitstatus_to_exitcode(status)
        process.returncode = code
    ended = time.perf_counter_ns()
    stdout = (output / (name + '.stdout')).read_bytes()
    stderr = (output / (name + '.stderr')).read_bytes()
    assert len(stdout) + len(stderr) <= 4 * 1024 * 1024, 'Bounded command output exceeded'
    record = dict(pid=process.pid, code=code, wallNs=ended-started,
                cpuUserUs=round(usage.ru_utime*1e6), cpuSystemUs=round(usage.ru_stime*1e6),
                cpuScope='waited child and its waited descendants; unrelated/orphan CPU excluded',
                childReportedMaximumRssBytes=usage.ru_maxrss * (1024 if sys.platform == 'linux' else 1),
                childReportedMinorFaults=usage.ru_minflt, childReportedMajorFaults=usage.ru_majflt,
                memoryScope='OS wait4 child report; not acquired, initialized or used allocation bytes',
                executable=str(executable), args=args, stdout=stdout.decode(), stderr=stderr.decode())
    write(output / (name + '.command.json'), record)
    return record


def native_sample(consumer, output, operation, state, original, index):
    executable = consumer / 'bin/actql.mjs'
    records = []
    try:
        if operation != 'cold-existing':
            records.append(command(executable, ['init', state.name], output, output, f'{index}-init'))
            assert records[-1]['code'] == 0, 'Ordinary init failed'
            (state / 'query.aql').write_text(SQL + ';\n')
            records.append(command(executable, ['run', 'query.aql', '--format', 'aql-text', '--output',
                                               'answer.jsonl', '--receipt', 'run.json', '--json'],
                                   state, output, f'{index}-run'))
            assert records[-1]['code'] == 0, 'Ordinary Run command failed'
            response = json.loads(records[-1]['stdout'])
            assert response['run']['status'] == 'succeeded' and response['delivery_status'] == 'delivered'
            original = response['run']['run_id']
            assert isinstance(original, str) and original
            assert (state / 'answer.jsonl').read_bytes() == b'{"id":1}\n'
        else:
            records.append(command(executable, ['result', original, '--result', 'answer', '--format', 'jsonl'],
                                   state, output, f'{index}-result'))
            assert records[-1]['code'] == 0 and records[-1]['stdout'] == '{"id":1}\n'
    except BaseException as error:
        error.observation = dict(commands=records, pid=records[-1]['pid'] if records else None,
                                 cleanup=dict(closed=all(r['code'] is not None for r in records)))
        raise
    return dict(originalRun=original, actualSha256=digest(wire(EXPECTED)), pid=records[-1]['pid'],
                commands=records, cleanup=dict(closed=True, scope='Actual command processes exited; no arena/GC/remote ACK inferred'))


def python_sample(config):
    """Only public installed SDK methods; private config belongs to this harness."""
    assert Path(sys.prefix).resolve() == Path(config['venv']).resolve(), 'Wrong installed Python interpreter'
    import actql
    assert Path(actql.__file__).resolve().is_relative_to(Path(config['consumer']).resolve())
    client = None
    rows = []
    original = config.get('originalRun')
    result = dict(pid=os.getpid(), cleanup=dict(closed=False), samples=rows)
    try:
        client = actql.open(state_dir=Path(config['stateId']))
        if original is None:
            query = client.sql(SQL)
            assert query.all() == EXPECTED
            execution = query.execution
            original = dict(execution.ref)
        else:
            execution = client.attach(original)
            assert dict(execution.ref) == original
        result['originalRun'] = original
        operation = config['operation']
        if operation == 'first-init':
            # Query.all already verified these rows. Initialization must not
            # manufacture an additional Result operation after that completion.
            result['actualSha256'] = digest(wire(EXPECTED))
            return 0
        if operation == 'warm-status':
            assert execution.status().status == 'succeeded'
        for iteration in range(config['count']):
            before = resource.getrusage(resource.RUSAGE_SELF)
            start = time.perf_counter_ns()
            failure = None
            try:
                if operation == 'warm-select':
                    value = client.sql(SQL).all()
                elif operation == 'warm-status':
                    status = execution.status()
                    value = {'status': status.status}
                else:
                    value = execution.result('main').all()
                expected = {'status': 'succeeded'} if operation == 'warm-status' else EXPECTED
                assert value == expected
            except BaseException as error:
                failure = dict(name=type(error).__name__, message=str(error))
            end = time.perf_counter_ns()
            after = resource.getrusage(resource.RUSAGE_SELF)
            row = dict(iteration=iteration, pid=os.getpid(), wallNs=end-start,
                       cpuUserUs=round((after.ru_utime-before.ru_utime)*1e6),
                       cpuSystemUs=round((after.ru_stime-before.ru_stime)*1e6),
                       cpuScope='actual Python SDK process including native threads; other processes excluded',
                       completed=failure is None, verified=failure is None)
            if failure:
                row['error'] = failure
            else:
                row['actualSha256'] = digest(wire(value))
            rows.append(row)
            if failure or operation.startswith('warm-') and row['wallNs'] >= 100_000_000:
                result['stoppedEarly'] = True
                break
    except BaseException as error:
        result['failure'] = dict(name=type(error).__name__, message=str(error))
    finally:
        if client:
            try:
                client.close()
                result['cleanup']['closed'] = True
            except BaseException as error:
                result['cleanup']['failure'] = dict(name=type(error).__name__, message=str(error))
        write(Path(config['resultPath']), result)
    return 0 if not result.get('failure') and result['cleanup']['closed'] and all(r['verified'] for r in rows) else 1


def collect(args):
    output = Path(args.output).resolve()
    consumer = Path(args.consumer).absolute()
    manifest_path = Path(args.manifest).resolve()
    manifest, cohort, before = verify_packages(args.adapter, manifest_path, consumer, args.source)
    assert args.adapter != 'native' or not args.operation.startswith('warm-'), 'CLI process launches are not retained-Host warm samples'
    assert not output.exists(), 'Use distinct new benchmark state; no old Run replay'
    output.mkdir(mode=0o700, parents=True)
    protocol = dict(adapter=args.adapter, operation=args.operation, fixture=SQL,
                    cold='Each sample launches a new actual process; OS caches not evicted',
                    warm='Python only: same open public Host and actual SDK process',
                    close='Await synchronous public SDK close or actual CLI process exit',
                    earlyStop='One failed/Unknown sample stops; warm diagnostic over100ms stops without a p95 claim')
    environment = dict(platform=sys.platform, architecture=platform.machine(), osRelease=platform.release(),
                       python=platform.python_version(), pythonExecutableSha256=digest(Path(sys.executable).read_bytes()))
    binding = dict(cohortSha256=cohort, fixtureSha256=digest(FIXTURE),
                   environmentSha256=digest(wire(environment)), historyProtocolSha256=digest(wire(protocol)))
    series = dict(operation=args.operation, mode=args.mode, **binding, profiled=False,
                  load=args.load, samples=[], stoppedEarly=False)
    report = dict(sourceSha=args.source, **{k: binding[k] for k in ('cohortSha256','environmentSha256','historyProtocolSha256')},
                  executionPath='native-cli' if args.adapter == 'native' else 'python-sdk',
                  protocol=protocol, environment=environment, latency=[series], functional={**binding, 'rows': []},
                  cleanup=dict(closed=False), fullAcceptance=False, packageFailure=None,
                  missing=['Matched per-route public comparison profile', 'Actual per-operation structural/history/chunk/boundary evidence'],
                  structuralCounters=None, allocationAndInitializedBytes=None, databaseReads=None,
                  qualification='Collector-only selected public operation. Counters unavailable here are missing, never zero. Separate required assessor must reject missing coverage.')
    original = None
    state = output / 'existing-state'
    expected = {'status':'succeeded'} if args.operation == 'warm-status' else EXPECTED
    count = (100 if args.operation.startswith('warm-') else 30) if args.mode == 'final' else 3
    pids = set()

    def sample(operation, sample_state, index, sample_count=1):
        start = time.perf_counter_ns()
        if args.adapter == 'native':
            try:
                value = native_sample(consumer, output, operation, sample_state, original, index)
            except BaseException as error:
                observed = getattr(error, 'observation', None)
                if observed is not None:
                    observed['wallNs'] = time.perf_counter_ns()-start
                raise
            value.update(wallNs=time.perf_counter_ns()-start,
                         cpuUserUs=sum(r['cpuUserUs'] for r in value['commands']),
                         cpuSystemUs=sum(r['cpuSystemUs'] for r in value['commands']),
                         cpuScope='Selected CLI startup through verified output and exit, including waited descendants')
        else:
            venv = Path(args.venv).resolve()
            config = dict(operation=operation, consumer=str(consumer), venv=str(venv), stateId=str(sample_state),
                          count=sample_count, resultPath=str(output / f'{index}-child.json'), originalRun=original)
            config_path = output / f'{index}-config.json'
            write(config_path, config)
            record = command(venv/'bin/python', ['-I','-B',str(Path(__file__).resolve()), '--sample',str(config_path)],
                             output, output, str(index))
            value = json.loads(Path(config['resultPath']).read_text()) if Path(config['resultPath']).exists() else {}
            assert value.get('pid') == record['pid'], 'Actual child PID/receipt missing or different'
            value.update(command=record, wallNs=time.perf_counter_ns()-start,
                         cpuUserUs=record['cpuUserUs'], cpuSystemUs=record['cpuSystemUs'], cpuScope=record['cpuScope'])
            if record['code'] != 0 or value.get('failure') or not value.get('cleanup', {}).get('closed'):
                error = ValueError('Public operation or close failed')
                error.observation = value
                raise error
        return value

    report['observations'] = []
    active = 'seed' if args.operation == 'cold-existing' else 'sample'
    try:
        if args.operation == 'cold-existing':
            report['seed'] = sample('first-init', state, 'seed')
            original = report['seed']['originalRun']
            pids.add(report['seed']['pid'])
        iterations = 1 if args.operation.startswith('warm-') else count
        active = 'sample'
        for iteration in range(iterations):
            selected = output / f'new-state-{iteration}' if args.operation == 'first-init' else state
            observation = sample(args.operation, selected, iteration, count if args.operation.startswith('warm-') else 1)
            report['observations'].append(observation)
            if args.operation.startswith('warm-'):
                samples = observation['samples']
                series['stoppedEarly'] = observation.get('stoppedEarly', False)
                for row in samples:
                    series['samples'].append({**binding, **row, 'stateId':str(selected), 'hostId':str(observation['pid'])})
            else:
                assert observation['pid'] not in pids, 'Process sample reused a seed/sample PID'
                pids.add(observation['pid'])
                row = {**binding, **{k:observation[k] for k in ('pid','wallNs','cpuUserUs','cpuSystemUs','cpuScope')},
                       'iteration':iteration, 'stateId':str(selected), 'completed':True,'verified':True,
                       'actualSha256':digest(wire(expected))}
                series['samples'].append(row)
            write(output/'measurements.json', report)
            if not args.operation.startswith('warm-') and observation['wallNs'] > (50_000_000_000 if args.operation == 'first-init' else 20_000_000_000):
                series['stoppedEarly'] = True
                break
        report['cleanup']['closed'] = True
    except BaseException as error:
        report['firstFailure'] = dict(name=type(error).__name__, message=str(error))
        observation = getattr(error, 'observation', None)
        if observation is not None:
            report['failedObservation'] = observation
            report['cleanup']['closed'] = observation.get('cleanup', {}).get('closed', False)
            if active == 'seed':
                report['seedFailed'] = True
            elif args.operation.startswith('warm-'):
                for row in observation.get('samples', []):
                    series['samples'].append({**binding, **row, 'stateId':str(state), 'hostId':str(observation['pid'])})
            elif observation.get('pid'):
                records = observation.get('commands', [observation['command']] if 'command' in observation else [])
                series['samples'].append({**binding, 'iteration':len(series['samples']), 'pid':observation['pid'],
                    'stateId':str(selected if 'selected' in locals() else state),
                    'wallNs':observation.get('wallNs', sum(r['wallNs'] for r in records)),
                    'cpuUserUs':sum(r['cpuUserUs'] for r in records),
                    'cpuSystemUs':sum(r['cpuSystemUs'] for r in records),
                    'cpuScope':'Actual failed command records; not hidden from raw samples', 'completed':False, 'verified':False})
        series['stoppedEarly'] = True
    finally:
        try:
            assert verify_packages(args.adapter, manifest_path, consumer, args.source)[2] == before
            report['installedPayloadsUnchanged'] = True
        except BaseException as error:
            report['packageFailure'] = str(error)
        complete = bool(series['samples']) and all(r['verified'] for r in series['samples']) and report['cleanup']['closed']
        report['functional']['rows'].append(dict(operation=args.operation,completed=complete,
             expectedSha256=digest(wire(expected)), **({'actualSha256':digest(wire(expected))} if complete else {})))
        write(output/'measurements.json', report)
    return 0 if complete and not report.get('firstFailure') and report['packageFailure'] is None else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sample', help=argparse.SUPPRESS)
    parser.add_argument('--adapter', choices=('native','python'))
    parser.add_argument('--manifest')
    parser.add_argument('--consumer', help='Installed actql Native package root or Python site-packages')
    parser.add_argument('--venv', help='Python adapter only: existing normal consumer venv')
    parser.add_argument('--source')
    parser.add_argument('--output')
    parser.add_argument('--operation', choices=OPERATIONS)
    parser.add_argument('--mode', choices=('diagnostic','final'), default='diagnostic')
    parser.add_argument('--load', choices=('isolated','concurrent'), default='concurrent')
    args = parser.parse_args()
    if args.sample:
        return python_sample(json.loads(Path(args.sample).read_text()))
    assert all(getattr(args,k) for k in ('adapter','manifest','consumer','source','output','operation'))
    assert len(args.source)==40 and all(c in '0123456789abcdef' for c in args.source)
    assert args.adapter != 'python' or args.venv
    return collect(args)


if __name__ == '__main__':
    sys.exit(main())
