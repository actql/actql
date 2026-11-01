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
OPERATIONS = ('first-init', 'cold-existing', 'warm-select', 'warm-result', 'warm-status',
              'warm-join', 'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode')
SMALL_QUERIES = {
    'warm-join': dict(operation='warm-join',
        text="WITH lhs AS (SELECT 1 AS id), rhs AS (SELECT 1 AS id, 'joined' AS label) "
             'SELECT lhs.id AS id, rhs.label AS label FROM lhs JOIN rhs ON lhs.id = rhs.id MAX_OUTPUT_ROWS 1',
        expected=[dict(id=1, label='joined')]),
    'warm-decimal-sum': dict(operation='warm-decimal-sum',
        text="WITH items AS (SELECT CAST('1.25' AS DECIMAL(8,2)) AS amount "
             "UNION ALL SELECT CAST('2.50' AS DECIMAL(8,2)) AS amount "
             "UNION ALL SELECT CAST('0.25' AS DECIMAL(8,2)) AS amount) "
             'SELECT SUM(amount) AS total FROM items', expected=[dict(total='4.00')]),
    'warm-union': dict(operation='warm-union',
        text='WITH items AS (SELECT 2 AS id UNION ALL SELECT 1 AS id) '
             'SELECT id FROM items |> ASSERT UNIQUE BY (id) |> ORDER BY id', expected=[dict(id=1), dict(id=2)]),
    'warm-parameters': dict(operation='warm-parameters', text='SELECT @id AS id',
        options=dict(parameters=dict(id=7), parameterDeclarations=dict(id=dict(type='number'))), expected=[dict(id=7)]),
    'warm-unicode': dict(operation='warm-unicode', text="SELECT 'é😀' AS label", expected=[dict(label='é😀')]),
}


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
    record = dict(pid=process.pid, code=code, wallNs=ended-started, startedNs=started, endedNs=ended,
                cpuUserUs=round(usage.ru_utime*1e6), cpuSystemUs=round(usage.ru_stime*1e6),
                cpuScope='waited child and its waited descendants; unrelated/orphan CPU excluded',
                childReportedMaximumRssBytes=usage.ru_maxrss * (1024 if sys.platform == 'linux' else 1),
                childReportedMinorFaults=usage.ru_minflt, childReportedMajorFaults=usage.ru_majflt,
                memoryScope='OS wait4 child report; not acquired, initialized or used allocation bytes',
                executable=str(executable), cwd=str(cwd), args=args, stdout=stdout.decode(), stderr=stderr.decode())
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


def python_failure(error):
    """Retain bounded scalar failure facts, never SDK holders or payload objects."""
    import inspect

    pending, indices, chain = [error], {id(error): 0}, []
    truncated = False
    for current in pending:
        # Read stored exception data without invoking custom properties/formatters.
        args = BaseException.args.__get__(current, type(current))
        message = args[0][:2048] if args and type(args[0]) is str else '<non-string exception arguments>'
        row = dict(name=type(current).__name__[:2048], message=message[:2048])
        for name in ('code', 'rows_yielded', 'cleanup_pending', 'attempt_id'):
            value = inspect.getattr_static(current, name, None)
            if type(value) in (str, int, bool) or value is None:
                row[name] = value[:2048] if type(value) is str else value
        causes = {}
        for name in ('original_error', 'cleanup_error', 'validation_error', '__cause__', '__context__'):
            value = (BaseException.__dict__[name].__get__(current, type(current))
                     if name in ('__cause__', '__context__') else inspect.getattr_static(current, name, None))
            if not isinstance(value, BaseException):
                continue
            if id(value) not in indices:
                if len(pending) == 8:
                    truncated = True
                    continue
                indices[id(value)] = len(pending)
                pending.append(value)
            causes[name] = indices[id(value)]
        row['causes'] = causes
        chain.append(row)
    return {**chain[0], 'errorChain': chain, 'errorChainTruncated': truncated}


def python_sample(config):
    """Only public installed SDK methods; private config belongs to this harness."""
    assert Path(sys.prefix).resolve() == Path(config['venv']).resolve(), 'Wrong installed Python interpreter'
    public_start = time.perf_counter_ns()
    import actql
    assert Path(actql.__file__).resolve().is_relative_to(Path(config['consumer']).resolve())
    client = None
    rows = []
    original = config.get('originalRun')
    result = dict(pid=os.getpid(), cleanup=dict(closed=False), samples=rows,
                  publicTiming=dict(kind='process-result-close', startNs=public_start))
    try:
        client = actql.open(state_dir=Path(config['stateId']))
        if original is None:
            query = client.sql(SQL)
            assert query.all() == EXPECTED
            result['publicTiming']['observedNs'] = time.perf_counter_ns()
            execution = query.execution
            original = dict(execution.ref)
        else:
            execution = client.attach(original)
            assert dict(execution.ref) == original
        result['originalRun'] = original
        operation = config['operation']
        fixture = SMALL_QUERIES.get(operation)
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
                elif fixture:
                    options = dict(fixture.get('options', {}))
                    if 'parameterDeclarations' in options:
                        options['parameter_declarations'] = options.pop('parameterDeclarations')
                    value = client.sql(fixture['text'], **options).all()
                elif operation == 'warm-status':
                    status = execution.status()
                    value = {'status': status.status}
                else:
                    value = execution.result('main').all()
                expected = fixture['expected'] if fixture else ({'status': 'succeeded'} if operation == 'warm-status' else EXPECTED)
                assert value == expected
            except BaseException as error:
                failure = python_failure(error)
            end = time.perf_counter_ns()
            if failure is None and 'observedNs' not in result['publicTiming']:
                result['publicTiming']['observedNs'] = end
            after = resource.getrusage(resource.RUSAGE_SELF)
            row = dict(iteration=iteration, pid=os.getpid(), wallNs=end-start,
                       cpuUserUs=round((after.ru_utime-before.ru_utime)*1e6),
                       cpuSystemUs=round((after.ru_stime-before.ru_stime)*1e6),
                       cpuScope='actual Python SDK process including native threads; other processes excluded',
                       peakRssBytes=after.ru_maxrss * (1024 if sys.platform == 'linux' else 1),
                       rssScope='actual Python process high-water RSS; not per-operation allocation',
                       completed=failure is None, verified=failure is None,
                       publicTiming=dict(kind='public-status' if operation == 'warm-status' else 'public-result',
                                         startNs=start, observedNs=end, endNs=end))
            if failure:
                row['error'] = failure
            else:
                row['actualSha256'] = digest(wire(value))
            rows.append(row)
            if failure or operation.startswith('warm-') and row['wallNs'] >= 100_000_000:
                result['stoppedEarly'] = True
                break
    except BaseException as error:
        result['failure'] = python_failure(error)
    finally:
        if client:
            result['publicTiming']['closeStartNs'] = time.perf_counter_ns()
            try:
                client.close()
                result['cleanup']['closed'] = True
            except BaseException as error:
                result['cleanup']['failure'] = python_failure(error)
            result['publicTiming']['closeEndNs'] = time.perf_counter_ns()
        result['publicTiming']['endNs'] = time.perf_counter_ns()
        write(Path(config['resultPath']), result)
    return 0 if not result.get('failure') and result['cleanup']['closed'] and all(r['verified'] for r in rows) else 1


def python_priority_protocol(mode):
    count = 100 if mode == 'final' else 3
    return dict(selection='priority-transition', mode=mode,
                entry='ordinary actql.open(state_dir)', firstQuery={'text':'SELECT 0 AS id', 'expected':[{'id':0}]},
                queries=[{'text':f'SELECT {n} AS id', 'expected':[{'id':n}]} for n in range(1, count+1)],
                samplesPerOperation=count,
                savedOriginals='first three successful new-query Results, read cyclically without resubmission',
                order=['first-query-separate', 'warm-select', 'warm-result'],
                timing='public construction/all, public execution.ref capture and independent row oracle',
                diagnosticStopMs=5000,
                close='one original public close; failed or Unknown operations are never retried')


def python_priority_sample(config):
    """One actual installed SDK process/Host, with separate original Run targets."""
    assert Path(sys.prefix).resolve() == Path(config['venv']).resolve(), 'Wrong installed Python interpreter'
    protocol = python_priority_protocol(config['mode'])
    result = dict(pid=os.getpid(), hostId=str(uuid.uuid4()), stateId=config['stateId'],
                  environment=dict(platform=sys.platform, architecture=platform.machine(),
                      osRelease=platform.release(), python=platform.python_version(),
                      pythonExecutableSha256=digest(Path(sys.executable).read_bytes())),
                  cleanup=dict(closed=False), latency=[], savedOriginals=[],
                  publicCallAttempts=dict(open=0, sql=0, savedResultAll=0, close=0))
    client = None
    active = 'ordinary public import/open'
    originals, runs, results = [], set(), set()

    def measured(row, action):
        start, cpu = time.perf_counter_ns(), time.process_time_ns()
        before = resource.getrusage(resource.RUSAGE_SELF)
        try:
            action(row)
            row.update(completed=True, verified=True)
        except BaseException as error:
            row.update(completed=False, verified=False,
                       error=python_failure(error))
            raise
        finally:
            after = resource.getrusage(resource.RUSAGE_SELF)
            row.update(wallNs=time.perf_counter_ns()-start, processCpuNs=time.process_time_ns()-cpu,
                       cpuUserUs=round((after.ru_utime-before.ru_utime)*1e6),
                       cpuSystemUs=round((after.ru_stime-before.ru_stime)*1e6),
                       cpuScope='actual retained Python SDK process including native threads; unrelated processes excluded')

    def identity():
        return dict(pid=os.getpid(), hostId=result['hostId'], stateId=config['stateId'],
                    publicOperationId=str(uuid.uuid4()))

    def query(fixture, row):
        row.update(querySha256=digest(wire(fixture['text'])), expectedSha256=digest(wire(fixture['expected'])))
        result['publicCallAttempts']['sql'] += 1
        pending = client.sql(fixture['text'])
        value = pending.all()
        row['actualSha256'] = digest(wire(value))
        assert value == fixture['expected'], 'Independent materialized-row oracle differs'
        execution = pending.execution
        assert execution is not None
        reference = dict(execution.ref)
        # Python has no public Result.ref getter. This is the exact public Run
        # reference plus the documented named-Result request, not a physical CID.
        selected = dict(run=reference, resultName='main')
        row.update(runRefSha256=digest(wire(reference)), resultRefSha256=digest(wire(selected)))
        assert row['runRefSha256'] not in runs and row['resultRefSha256'] not in results, 'New SQL reused an original Run/Result'
        runs.add(row['runRefSha256']); results.add(row['resultRefSha256'])
        return dict(execution=execution, runRef=reference, resultRef=selected,
                    runRefSha256=row['runRefSha256'], resultRefSha256=row['resultRefSha256'],
                    expected=fixture['expected'], expectedSha256=row['expectedSha256'])

    try:
        assert sys.getprofile() is None and sys.gettrace() is None, 'Priority latency must be unprofiled'
        start, cpu = time.perf_counter_ns(), time.process_time_ns()
        import actql
        assert Path(actql.__file__).resolve().is_relative_to(Path(config['consumer']).resolve())
        result['publicCallAttempts']['open'] += 1
        client = actql.open(state_dir=Path(config['stateId']))
        result['moduleImportAndOpen'] = dict(wallNs=time.perf_counter_ns()-start,
                                             processCpuNs=time.process_time_ns()-cpu)
        active = 'first-query-separate'
        result['firstQuery'] = identity()
        measured(result['firstQuery'], lambda row: query(protocol['firstQuery'], row))
        for operation in ['warm-select', 'warm-result']:
            active = operation
            fresh = operation == 'warm-select'
            workload = (dict(kind='new-durable-run-result-rows', fixtures=[dict(
                querySha256=digest(wire(f['text'])), expectedSha256=digest(wire(f['expected']))) for f in protocol['queries']])
                if fresh else dict(kind='saved-original-result-rows', originals=[{
                    k:original[k] for k in ['runRefSha256','resultRefSha256','expectedSha256']} for original in originals]))
            series = dict(operation=operation, publicWorkload=workload,
                          fixtureSha256=digest(wire(workload)), samples=[], stoppedEarly=False)
            result['latency'].append(series)
            for iteration in range(protocol['samplesPerOperation']):
                row = dict(**identity(), iteration=iteration)
                series['samples'].append(row)

                def execute(row):
                    if fresh:
                        original = query(protocol['queries'][iteration], row)
                        if len(originals) < 3:
                            originals.append(original)
                    else:
                        original = originals[iteration % len(originals)]
                        row.update({k:original[k] for k in ['runRefSha256','resultRefSha256','expectedSha256']})
                        result['publicCallAttempts']['savedResultAll'] += 1
                        value = original['execution'].result('main').all()
                        row['actualSha256'] = digest(wire(value))
                        assert value == original['expected'], 'Saved original rows differ'

                measured(row, execute)
                if row['wallNs'] >= protocol['diagnosticStopMs'] * 1_000_000:
                    series.update(stoppedEarly=True, stopReason='slow diagnostic; final distribution not measured')
                    result['stoppedAt'] = operation
                    break
            if series['stoppedEarly']:
                break
    except BaseException as error:
        result['firstFailure'] = dict(operation=active, **python_failure(error))
        if result['latency']:
            result['latency'][-1].update(stoppedEarly=True, stopReason='public functional failure')
    finally:
        if client is not None:
            start = time.perf_counter_ns()
            try:
                result['publicCallAttempts']['close'] += 1
                client.close()
                result['cleanup']['closed'] = True
            except BaseException as error:
                result['cleanup']['failure'] = python_failure(error)
            result['cleanup']['wallNs'] = time.perf_counter_ns()-start
        result['savedOriginals'] = [{k:original[k] for k in ['runRef','resultRef','expected']} for original in originals]
        write(Path(config['resultPath']), result)
    return 1 if result.get('firstFailure') or not result['cleanup']['closed'] else 0


def collect_python_priority(args):
    assert args.adapter == 'python' and args.operation in (None, 'warm-select'), 'Priority selection requires ordinary Python warm operations'
    output, consumer = Path(args.output).resolve(), Path(args.consumer).absolute()
    manifest_path, environment = Path(args.manifest).resolve(), Path(args.venv).resolve()
    _, cohort, before = verify_packages('python', manifest_path, consumer, args.source)
    assert not output.exists(), 'Use distinct new benchmark state; no old Run replay'
    output.mkdir(mode=0o700, parents=True)
    protocol = python_priority_protocol(args.mode)
    report = dict(sourceSha=args.source, cohortSha256=cohort, executionPath='python-sdk',
                  selection='priority-transition', mode=args.mode, historyProtocol=protocol,
                  historyProtocolSha256=digest(wire(protocol)), latency=[], functional={'rows':[]},
                  cleanup=dict(closed=False), priorityConditions={}, installedPayloadsUnchanged=False,
                  packageFailure=None, fullAcceptance=False,
                  structuralCounters=None, population=None,
                  qualification='Raw ordinary Python checkpoint selection only. Missing actual safety, population and experiment observations remain incomplete; no performance or release acceptance.')
    config = dict(selection='priority-transition', mode=args.mode, consumer=str(consumer), venv=str(environment),
                  stateId=str(output/'new-state'), resultPath=str(output/'priority-child.json'))
    config_path = output/'priority-config.json'; write(config_path, config)
    try:
        record = command(environment/'bin/python', ['-I','-B',str(Path(__file__).resolve()), '--sample',str(config_path)],
                         output, output, 'priority')
        report['command'] = record
        observed = json.loads(Path(config['resultPath']).read_text())
        assert observed['pid'] == record['pid'], 'Actual priority child PID/receipt differs'
        report.update({k:observed[k] for k in ['cleanup','savedOriginals','publicCallAttempts']})
        report['observedEnvironment'] = observed['environment']
        binding = dict(cohortSha256=cohort, environmentSha256=digest(wire(observed['environment'])),
                       historyProtocolSha256=report['historyProtocolSha256'])
        report.update(binding); report['functional'].update(binding)
        for key in ['firstQuery','firstFailure','stoppedAt','moduleImportAndOpen']:
            if key in observed:
                report[key] = observed[key]
        if 'moduleImportAndOpen' in observed:
            report['priorityConditions']['startedHost'] = True
        for series in observed['latency']:
            series.update(binding, mode=args.mode, firstQuery=observed.get('firstQuery'),
                          profiled=False, load=args.load)
            for row in series['samples']:
                row.update(binding, fixtureSha256=series['fixtureSha256'])
            report['latency'].append(series)
            rows = series['samples']
            complete = bool(rows) and all(row['verified'] for row in rows)
            report['functional']['rows'].append(dict(operation=series['operation'], completed=complete,
                expectedSha256=digest(wire([row.get('expectedSha256') for row in rows])),
                **({'actualSha256':digest(wire([row.get('actualSha256') for row in rows]))} if complete else {})))
        if record['code'] != 0 and not report.get('firstFailure'):
            report['firstFailure'] = dict(operation='priority child', message='Public operation or close process failed')
    except BaseException as error:
        report.setdefault('firstFailure', dict(operation='priority observation', name=type(error).__name__, message=str(error)))
    finally:
        try:
            assert verify_packages('python', manifest_path, consumer, args.source)[2] == before
            report['installedPayloadsUnchanged'] = True
        except BaseException as error:
            report['packageFailure'] = str(error)
        if report.get('firstFailure') or report['packageFailure'] or not report['cleanup']['closed']:
            for row in report['functional']['rows']:
                row['completed'] = False
                row.pop('actualSha256', None)
        write(output/'measurements.json', report)
    return 1 if report.get('firstFailure') or report['packageFailure'] or not report['cleanup']['closed'] else 0



def collect_native_operations(args):
    """Separate CLI processes; a durable Run with file rows is not a warm SDK call."""
    assert args.adapter == 'native' and args.operation is None, 'Native operation selection requires Native CLI without an ordinary operation'
    output, consumer = Path(args.output).resolve(), Path(args.consumer).absolute()
    manifest_path = Path(args.manifest).resolve()
    _, cohort, before = verify_packages('native', manifest_path, consumer, args.source)
    assert not output.exists(), 'Use distinct new benchmark state; no old Run replay'
    output.mkdir(mode=0o700, parents=True)
    count = 100 if args.mode == 'final' else 3
    protocol = dict(selection='native-operations', mode=args.mode, samplesPerOperation=count,
        firstQuery={'text':'SELECT 0 AS id','expected':[{'id':0}]},
        queries=[{'text':f'SELECT {n} AS id','expected':[{'id':n}]} for n in range(1,count+1)],
        order=['init-separate','first-query-separate','cold-new-run','cold-result'],
        entry='ordinary init, then one actual CLI child per Program Run/file rows or saved Result',
        savedOriginals='first three measured successful Runs, read cyclically without resubmission',
        timing='startup through child exit, response and materialized-row oracle; child duration also retained',
        diagnosticStopMs=1000, close='actual CLI process exit, no SDK Host.close or native-arena ACK inferred')
    environment = dict(platform=sys.platform, architecture=platform.machine(), osRelease=platform.release(),
        controllerPython=platform.python_version(), controllerExecutableSha256=digest(Path(sys.executable).read_bytes()))
    binding = dict(cohortSha256=cohort, environmentSha256=digest(wire(environment)),
                   historyProtocolSha256=digest(wire(protocol)))
    state, executable = output/'new-state', consumer/'bin/actql.mjs'
    report = dict(sourceSha=args.source, **binding, executionPath='native-cli', selection='native-operations',
        mode=args.mode, environment=environment, historyProtocol=protocol, latency=[],
        functional={**binding,'rows':[]}, cleanup=dict(closed=False), installedPayloadsUnchanged=False,
        packageFailure=None, commands=[], savedOriginals=[], publicCallAttempts=dict(init=0,run=0,result=0),
        structuralCounters=None, population=None, fullPerformanceAccepted=False,
        qualification='Native process latency/functional selection only; no retained-Host warm, matched comparator, history, safety or release acceptance.')
    originals, runs = [], set()
    active = 'init'

    def measured(row, action):
        start = time.perf_counter_ns()
        try:
            action(row)
            row.update(completed=True,verified=True)
        except BaseException as error:
            row.update(completed=False,verified=False,error=dict(name=type(error).__name__,message=str(error)))
            raise
        finally:
            end = time.perf_counter_ns()
            row['wallNs'] = end-start
            record = row.get('command')
            if record:
                row.update(pid=record['pid'],childWallNs=record['wallNs'],cpuUserUs=record['cpuUserUs'],
                    cpuSystemUs=record['cpuSystemUs'],cpuScope=record['cpuScope'],
                    peakRssBytes=record['childReportedMaximumRssBytes'], rssScope=record['memoryScope'])
                if row.get('verified'):
                    row['publicTiming'] = dict(kind='cli-result-exit', startNs=start,
                        exitNs=row['exitObservedNs'], observedNs=end, endNs=end)

    def invoke(row, arguments, name):
        record = command(executable,arguments,state,output,name)
        row['exitObservedNs'] = time.perf_counter_ns()
        row['command'] = record;report['commands'].append(record)
        assert record['code'] == 0, 'Original public command failed; do not retry or resubmit'
        return record

    def new_query(fixture, row, name):
        query, destination = state/(name+'.aql'), state/(name+'.jsonl')
        query_bytes=query.read_bytes()
        assert query_bytes==(fixture['text']+';\n').encode(), 'Actual selected query file differs from the fixture'
        row.update(queryPath=str(query),queryFileSha256=digest(query_bytes),outputPath=str(destination),
            querySha256=digest(wire(fixture['text'])),expectedSha256=digest(wire(fixture['expected'])))
        report['publicCallAttempts']['run'] += 1
        record = invoke(row,['run',query.name,'--output',destination.name,'--json'],name)
        response = json.loads(record['stdout']);row['publicResponse'] = response
        row['publicRunId'] = response['run']['run_id']
        assert response['run']['status'] == 'succeeded' and response['delivery_status'] == 'delivered', 'Original admitted Run/delivery did not succeed'
        assert isinstance(row['publicRunId'],str) and row['publicRunId'] and row['publicRunId'] not in runs, 'New SQL reused an original Run'
        runs.add(row['publicRunId'])
        deliveries = response['deliveries'];assert len(deliveries)==1
        delivery = deliveries[0];assert delivery['run_id']==row['publicRunId'] and delivery['status']=='delivered'
        request = delivery['request'];assert request['path']==str(destination) and request['format']=='jsonl'
        selected = dict(runId=row['publicRunId'],resultName=request['result'],resultCid=request['result_cid'])
        assert all(isinstance(value,str) and value for value in selected.values())
        row.update(runRefSha256=digest(wire(dict(runId=row['publicRunId']))),resultRefSha256=digest(wire(selected)))
        assert stat.S_ISREG(destination.lstat().st_mode) and destination.stat().st_size<=4*1024*1024
        value = [json.loads(line)for line in destination.read_text().splitlines()]
        row['actualSha256'] = digest(wire(value));assert value==fixture['expected'], 'Independent materialized-row oracle differs'
        return dict(**selected,runRefSha256=row['runRefSha256'],resultRefSha256=row['resultRefSha256'],
                    expected=fixture['expected'],expectedSha256=row['expectedSha256'])

    try:
        report['publicCallAttempts']['init'] += 1
        initial = command(executable,['init',state.name],output,output,'init')
        report['initialization'] = initial;report['commands'].append(initial)
        assert initial['code']==0,'Ordinary init failed'
        active = 'first-query-separate'
        report['firstQuery'] = dict(publicOperationId=str(uuid.uuid4()),stateId=str(state))
        (state/'first.aql').write_text(protocol['firstQuery']['text']+';\n')
        measured(report['firstQuery'],lambda row:new_query(protocol['firstQuery'],row,'first'))
        for operation in ['cold-new-run','cold-result']:
            active = operation;fresh = operation=='cold-new-run'
            workload = (dict(kind='new-durable-run-result-file-rows',fixtures=[dict(querySha256=digest(wire(f['text'])),expectedSha256=digest(wire(f['expected'])))for f in protocol['queries']])
                if fresh else dict(kind='saved-original-result-rows',originals=[{k:r[k]for k in ['runRefSha256','resultRefSha256','expectedSha256']}for r in originals]))
            series = dict(**binding,operation=operation,mode=args.mode,profiled=False,load=args.load,
                publicWorkload=workload,fixtureSha256=digest(wire(workload)),samples=[],stoppedEarly=False)
            report['latency'].append(series)
            for iteration in range(count):
                row = dict(**binding,fixtureSha256=series['fixtureSha256'],iteration=iteration,
                           publicOperationId=str(uuid.uuid4()),stateId=str(state))
                series['samples'].append(row)
                if fresh:(state/f'new-{iteration}.aql').write_text(protocol['queries'][iteration]['text']+';\n')
                def execute(row):
                    if fresh:
                        original = new_query(protocol['queries'][iteration],row,f'new-{iteration}')
                        if len(originals)<3:originals.append(original)
                    else:
                        original=originals[iteration%len(originals)]
                        row.update({k:original[k]for k in ['runRefSha256','resultRefSha256','expectedSha256']})
                        row['publicRunId']=original['runId'];report['publicCallAttempts']['result']+=1
                        record=invoke(row,['result',original['runId'],'--result',original['resultName'],'--format','jsonl'],f'result-{iteration}')
                        value=[json.loads(line)for line in record['stdout'].splitlines()]
                        row['actualSha256']=digest(wire(value));assert value==original['expected'],'Saved original rows differ'
                measured(row,execute)
                if row['wallNs']>=protocol['diagnosticStopMs']*1_000_000:
                    series.update(stoppedEarly=True,stopReason='obvious slow sample; no acceptance distribution')
                    report['stoppedAt']=operation;break
            if series['stoppedEarly']:break
    except BaseException as error:
        report['firstFailure']=dict(operation=active,name=type(error).__name__,message=str(error))
        if report['latency']:report['latency'][-1]['stoppedEarly']=True
    finally:
        report['cleanup']=dict(closed=all(r['code']is not None for r in report['commands']),
            scope='Actual synchronous CLI children exited; no SDK close or arena ACK inferred')
        try:
            assert verify_packages('native',manifest_path,consumer,args.source)[2]==before
            report['installedPayloadsUnchanged']=True
        except BaseException as error:report['packageFailure']=str(error)
        report['savedOriginals']=originals
        for series in report['latency']:
            rows=series['samples'];complete=(len(rows)==count and all(r['verified']for r in rows)and
                not report.get('firstFailure')and report['packageFailure']is None and report['cleanup']['closed'])
            report['functional']['rows'].append(dict(operation=series['operation'],fixtureSha256=series['fixtureSha256'],completed=complete,
                expectedSha256=digest(wire([r.get('expectedSha256')for r in rows])),
                **({'actualSha256':digest(wire([r.get('actualSha256')for r in rows]))}if complete else {})))
        write(output/'measurements.json',report)
    return 1 if report.get('firstFailure')or report['packageFailure']or not report['cleanup']['closed']else 0


def collect(args):
    if args.selection == 'native-operations':
        return collect_native_operations(args)
    if args.selection == 'priority-transition':
        return collect_python_priority(args)
    output = Path(args.output).resolve()
    consumer = Path(args.consumer).absolute()
    manifest_path = Path(args.manifest).resolve()
    manifest, cohort, before = verify_packages(args.adapter, manifest_path, consumer, args.source)
    assert args.adapter != 'native' or not args.operation.startswith('warm-'), 'CLI process launches are not retained-Host warm samples'
    assert not output.exists(), 'Use distinct new benchmark state; no old Run replay'
    output.mkdir(mode=0o700, parents=True)
    fixture = SMALL_QUERIES.get(args.operation)
    protocol = dict(adapter=args.adapter, operation=args.operation, fixture=fixture['text'] if fixture else SQL,
                    cold='Each sample launches a new actual process; OS caches not evicted',
                    warm='Python only: same open public Host and actual SDK process',
                    close='Await synchronous public SDK close or actual CLI process exit',
                    earlyStop='One failed/Unknown sample stops; warm diagnostic over100ms stops without a p95 claim')
    environment = dict(platform=sys.platform, architecture=platform.machine(), osRelease=platform.release(),
                       python=platform.python_version(), pythonExecutableSha256=digest(Path(sys.executable).read_bytes()))
    binding = dict(cohortSha256=cohort, fixtureSha256=digest(wire(fixture)) if fixture else digest(FIXTURE),
                   environmentSha256=digest(wire(environment)), historyProtocolSha256=digest(wire(protocol)))
    series = dict(operation=args.operation, mode=args.mode, **binding, profiled=False,
                  load=args.load, samples=[], stoppedEarly=False)
    report = dict(sourceSha=args.source, **{k: binding[k] for k in ('cohortSha256','environmentSha256','historyProtocolSha256')},
                  executionPath='native-cli' if args.adapter == 'native' else 'python-sdk',
                  protocol=protocol, environment=environment, latency=[series], functional={**binding, 'rows': []},
                  cleanup=dict(closed=False), fullAcceptance=False, packageFailure=None,
                  installedPayloadsUnchanged=False,
                  missing=['Matched per-route public comparison profile', 'Actual per-operation structural/history/chunk/boundary evidence'],
                  structuralCounters=None, allocationAndInitializedBytes=None, databaseReads=None,
                  qualification='Collector-only selected public operation. Counters unavailable here are missing, never zero. Separate required assessor must reject missing coverage.')
    original = None
    state = output / 'existing-state'
    expected = fixture['expected'] if fixture else ({'status':'succeeded'} if args.operation == 'warm-status' else EXPECTED)
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
            end = time.perf_counter_ns()
            value.update(wallNs=end-start,
                         cpuUserUs=sum(r['cpuUserUs'] for r in value['commands']),
                         cpuSystemUs=sum(r['cpuSystemUs'] for r in value['commands']),
                         cpuScope='Selected CLI startup through verified output and exit, including waited descendants',
                         peakRssBytes=max(r['childReportedMaximumRssBytes'] for r in value['commands']),
                         rssScope='Maximum of actual waited command RSS reports; not sum or acquired allocation',
                         publicTiming=dict(kind='cli-result-exit', startNs=start,
                             exitNs=value['commands'][-1]['endedNs'], observedNs=end, endNs=end))
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
                         cpuUserUs=record['cpuUserUs'], cpuSystemUs=record['cpuSystemUs'], cpuScope=record['cpuScope'],
                         peakRssBytes=record['childReportedMaximumRssBytes'], rssScope=record['memoryScope'])
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
                row = {**binding, **{k:observation[k] for k in ('pid','wallNs','cpuUserUs','cpuSystemUs','cpuScope','peakRssBytes','rssScope')},
                       **({'publicTiming': observation['publicTiming']} if 'publicTiming' in observation else {}),
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
        complete = (bool(series['samples']) and all(r['verified'] for r in series['samples'])
                    and report['cleanup']['closed'] and report['installedPayloadsUnchanged']
                    and not report.get('firstFailure'))
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
    parser.add_argument('--selection', choices=('ordinary','priority-transition','native-operations'), default='ordinary')
    parser.add_argument('--load', choices=('isolated','concurrent'), default='concurrent')
    args = parser.parse_args()
    if args.sample:
        config = json.loads(Path(args.sample).read_text())
        return python_priority_sample(config) if config.get('selection') == 'priority-transition' else python_sample(config)
    assert all(getattr(args,k) for k in ('adapter','manifest','consumer','source','output'))
    assert args.selection in ('priority-transition','native-operations') or args.operation
    assert len(args.source)==40 and all(c in '0123456789abcdef' for c in args.source)
    assert args.adapter != 'python' or args.venv
    return collect(args)


if __name__ == '__main__':
    sys.exit(main())
