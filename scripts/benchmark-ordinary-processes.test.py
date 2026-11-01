"""Actual process/fixture tests of the collector, not ActQL performance tests."""
import base64
import csv
import hashlib
import io
import json
import runpy
from pathlib import Path
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
import venv
import zipfile

SCRIPT = Path(__file__).with_name('benchmark-ordinary-processes.py')
SOURCE = 'a' * 40


def sha(body):
    return hashlib.sha256(body).hexdigest()


NATIVE = r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
args=sys.argv[1:];cwd=Path.cwd()
if args[0]=='init':
 (cwd/args[1]).mkdir()
elif args[0]=='run':
 assert (cwd/'query.aql').read_text()=='SELECT 1 AS id;\n'.replace('\\n','\n')
 (cwd/'events').write_text('submit\n')
 (cwd/'answer.jsonl').write_text('{"id":1}\n')
 (cwd/'run.json').write_text('{"synthetic":true}')
 print(json.dumps({'run':{'status':'succeeded','run_id':'synthetic-original'},'delivery_status':'delivered'}))
elif args[0]=='result':
 assert args[1]=='synthetic-original'
 with (cwd/'events').open('a') as f:f.write('result\n')
 if (cwd.parent/'fail-result').exists():
  print('Synthetic Unknown; no resend',file=sys.stderr);sys.exit(1)
 print('{"id":1}')
else:raise AssertionError(args)
'''

NATIVE_OPERATIONS = r'''#!/usr/bin/env python3
import hashlib,json,os,re,sys,time
from pathlib import Path
FAIL_QUERY=None
SLOW_QUERY=None
REUSE_RUN=False
FAIL_RESULT=False
ALTER_RESULT=False
args=sys.argv[1:];cwd=Path.cwd()
def event(kind,value=None):
 with(cwd/'events').open('a')as f:f.write(json.dumps({'kind':kind,'value':value,'pid':os.getpid()})+'\n')
if args[0]=='init':(cwd/args[1]).mkdir()
elif args[0]=='run':
 assert '--format'not in args and '--receipt'not in args
 value=int(re.fullmatch(r'SELECT ([0-9]+) AS id;\n',(cwd/args[1]).read_text())[1])
 event('run',value);run='synthetic-run-'+str(0 if REUSE_RUN else value)
 if value==FAIL_QUERY:
  print(json.dumps({'run':{'run_id':run,'status':'needs_reconciliation'},'delivery_status':'unknown'}));sys.exit(0)
 if value==SLOW_QUERY:time.sleep(1.01)
 file=cwd/args[args.index('--output')+1];file.write_text(json.dumps({'id':value},separators=(',',':'))+'\n')
 values=json.loads((cwd/'values.json').read_text())if(cwd/'values.json').exists()else{}
 values[run]=value;(cwd/'values.json').write_text(json.dumps(values))
 print(json.dumps({'run':{'run_id':run,'status':'succeeded'},'delivery_status':'delivered','deliveries':[{'run_id':run,'status':'delivered','request':{'path':str(file),'format':'jsonl','result':'answer','result_cid':'sha256:'+hashlib.sha256(str(value).encode()).hexdigest()}}]}))
elif args[0]=='result':
 value=json.loads((cwd/'values.json').read_text())[args[1]];event('result',value)
 if FAIL_RESULT:print('Synthetic Unknown; no resend',file=sys.stderr);sys.exit(1)
 if ALTER_RESULT:Path(__file__).write_text(Path(__file__).read_text()+'\n# modified fixture payload\n')
 print(json.dumps({'id':value}))
else:raise AssertionError(args)
'''

PYTHON = '''import json,os
from pathlib import Path
from types import SimpleNamespace
def open(*,state_dir):
 state=Path(state_dir);state.mkdir(exist_ok=True)
 def event(name):
  with (state/'events').open('a') as f:f.write(json.dumps({'event':name,'pid':os.getpid()})+'\\n')
 event('open')
 ref={'namespaceId':'synthetic','authorityScopeCid':'sha256:'+'b'*64,'runDefinitionCid':'sha256:'+'c'*64}
 class Result:
  def all(self):event('result');return [{'id':1}]
 class Execution:
  def __init__(self):self.ref=ref
  def status(self):event('status');return SimpleNamespace(status='succeeded')
  def result(self,name):assert name=='main';return Result()
 class Query:
  def __init__(self):self.execution=Execution()
  def all(self):event('submit');return [{'id':1}]
 class Client:
  def sql(self,text):assert text=='SELECT 1 AS id';return Query()
  def attach(self,original):assert original==ref;event('attach');return Execution()
  def close(self):
   event('close')
   if (state.parent/'fail-close').exists():raise RuntimeError('Synthetic cleanup pending')
 return Client()
'''

PRIORITY_PYTHON = '''import hashlib,json,os,re,time
from pathlib import Path
def open(*,state_dir):
 state=Path(state_dir);state.mkdir(exist_ok=True)
 def event(name,value=None):
  with (state/'events').open('a') as f:f.write(json.dumps({'event':name,'value':value,'pid':os.getpid()})+'\\n')
 event('open')
 class Result:
  def __init__(self,value):self.value=value
  def all(self):event('result',self.value);return [{'id':self.value}]
 class Execution:
  def __init__(self,value):
   self.value=value
   self.ref={'namespaceId':'synthetic','authorityScopeCid':'sha256:'+'b'*64,'runDefinitionCid':'sha256:'+hashlib.sha256(str(value).encode()).hexdigest()}
  def result(self,name):assert name=='main';return Result(self.value)
 class Query:
  def __init__(self,value):self.value=value;self.execution=Execution(value)
  def all(self):event('submit',self.value);return [{'id':self.value}]
 class Client:
  def sql(self,text):
   match=re.fullmatch(r'SELECT ([0-9]+) AS id',text);assert match,text
   value=int(match[1])
   if value==FAIL_QUERY:event('failed-submit',value);raise RuntimeError('Synthetic Unknown; no resend')
   if value==SLOW_QUERY:time.sleep(5.01)
   return Query(value)
  def close(self):
   event('close')
   if (state.parent/'fail-close').exists():raise RuntimeError('Synthetic cleanup pending')
 return Client()
FAIL_QUERY=None
SLOW_QUERY=None
'''


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='actql-process-collector-fixture-')
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def native(self, fail_result=False, operations=False, fail_query=None, reuse_run=False, alter_result=False, slow_query=None):
        root = self.root
        consumer = root/'installed-native'
        packages = root/'packages'
        packages.mkdir()
        platform_key = 'darwin-arm64' if sys.platform == 'darwin' else 'linux-x64-gnu'
        manifest = dict(version='actql-native-cli-release/0.1', sourceSha=SOURCE,
                        platforms={platform_key:{}}, packages=[])
        code = NATIVE.replace("if (cwd.parent/'fail-result').exists():", 'if True:') if fail_result else NATIVE
        if operations:
            code=NATIVE_OPERATIONS.replace('FAIL_QUERY=None','FAIL_QUERY='+repr(fail_query)).replace('SLOW_QUERY=None','SLOW_QUERY='+repr(slow_query)).replace('REUSE_RUN=False','REUSE_RUN='+repr(reuse_run)).replace('FAIL_RESULT=False','FAIL_RESULT='+repr(fail_result)).replace('ALTER_RESULT=False','ALTER_RESULT='+repr(alter_result))
        for name, members in [('actql', {'bin/actql.mjs':code.encode()}),
                              ('@actql/cli-'+platform_key, {'bin/actql-native-client':b'synthetic artifact only'})]:
            filename = name.replace('@','').replace('/','-')+'.tgz'
            files = []
            with tarfile.open(packages/filename,'w:gz') as archive:
                for path, body in members.items():
                    mode = 0o755
                    item = tarfile.TarInfo('package/'+path);item.mode=mode;item.size=len(body)
                    archive.addfile(item,io.BytesIO(body))
                    prefix = consumer if name == 'actql' else consumer/'node_modules'/name
                    target=prefix/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(body);target.chmod(mode)
                    files.append(dict(path=path,bytes=len(body),mode=mode,sha256=sha(body)))
            raw=(packages/filename).read_bytes()
            manifest['packages'].append(dict(name=name,file=filename,bytes=len(raw),sha256=sha(raw),
                integrity='sha512-'+base64.b64encode(hashlib.sha512(raw).digest()).decode(),files=files))
        path=packages/'release.json';path.write_text(json.dumps(manifest))
        return path, consumer, None

    def python(self, fail_close=False, alter_on_close=False, priority=False, fail_query=None,
               repeat_reference=False, slow_query=None, failure_chain=False, small_queries=False):
        root=self.root
        environment=root/'venv'
        venv.EnvBuilder(with_pip=False, symlinks=True).create(environment)
        paths=json.loads(subprocess.check_output([str(environment/'bin/python'),'-I','-c',
            'import json,sysconfig;print(json.dumps(sysconfig.get_paths()))']))
        consumer=Path(paths['purelib'])
        packages=root/'packages';(packages/'wheels').mkdir(parents=True)
        key='darwin-arm64' if sys.platform=='darwin' else 'linux-x64-gnu'
        cohort=dict(source_sha=SOURCE,platform=key,wheels=[])
        code = PRIORITY_PYTHON if priority else PYTHON
        if small_queries:
            fixtures = runpy.run_path(str(SCRIPT))['SMALL_QUERIES']
            literal_rows = {'warm-join': [{'id': 1, 'label': 'joined'}], 'warm-decimal-sum': [{'total': '4.00'}],
                            'warm-union': [{'id': 1}, {'id': 2}], 'warm-parameters': [{'id': 7}],
                            'warm-unicode': [{'label': 'é😀'}]}
            answers = {'SELECT 1 AS id': [{'id': 1}], **{fixtures[key]['text']: value for key, value in literal_rows.items()}}
            code = code.replace(" def __init__(self):self.execution=Execution()\n  def all(self):event('submit');return [{'id':1}]",
                                " def __init__(self,value):self.execution=Execution();self.value=value\n  def all(self):event('submit');return self.value")
            code = code.replace("def sql(self,text):assert text=='SELECT 1 AS id';return Query()",
                                f"def sql(self,text,**options):\n   values={answers!r}\n   expected={{'parameters':{{'id':7}},'parameter_declarations':{{'id':{{'type':'number'}}}}}} if text=='SELECT @id AS id' else {{}}\n   assert options==expected\n   assert text in values;event('sql:'+text);return Query(values[text])")
        if fail_query is not None:
            code = code.replace('FAIL_QUERY=None', f'FAIL_QUERY={fail_query}')
        if failure_chain:
            code += """
def chain_failure():
 error=RuntimeError('Synthetic uncertain read')
 error.code='ClientTransportUnknown'
 error.rows_yielded=0
 error.cleanup_pending=True
 error.attempt_id='synthetic-attempt'
 error.original_error=ValueError('Synthetic retained allocation')
 error.original_error.code='LocalFileError'
 error.cleanup_error=RuntimeError('Synthetic pending transport')
 error.__cause__=LookupError('Synthetic cause')
 error.__context__=ArithmeticError('Synthetic context')
 error.validation_error=ValueError('Synthetic validation')
 return error
"""
            code = code.replace("raise RuntimeError('Synthetic Unknown; no resend')", 'raise chain_failure()')
            code = code.replace("event('result');return", "event('result');raise chain_failure();return")
        if slow_query is not None:
            code = code.replace('SLOW_QUERY=None', f'SLOW_QUERY={slow_query}')
        if repeat_reference:
            code = code.replace('hashlib.sha256(str(value).encode())', "hashlib.sha256(b'0')")
        if fail_close:
            code = code.replace("if (state.parent/'fail-close').exists():", 'if True:')
        if alter_on_close:
            code = code.replace("event('close')", "event('close');Path(__file__).write_text(Path(__file__).read_text()+'\\n# altered on close\\n')")
        for distribution,members in [('actql',{'actql/__init__.py':code.encode()}),
                ('actql-sdk',{'actql_sdk/__init__.py':b'# Explicit synthetic SDK fixture\n'}),
                ('actql-local-runtime',{'actql_local_runtime/__init__.py':b'# No real runtime\n'})]:
            filename=distribution+'.whl';record=distribution.replace('-','_')+'.dist-info/RECORD'
            rows=[]
            with zipfile.ZipFile(packages/'wheels'/filename,'w') as archive:
                for path,body in members.items():
                    entry=zipfile.ZipInfo(path);entry.external_attr=(stat.S_IFREG|0o644)<<16;archive.writestr(entry,body)
                    target=consumer/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(body);target.chmod(0o644)
                    rows.append([path,'sha256='+base64.urlsafe_b64encode(hashlib.sha256(body).digest()).decode().rstrip('='),str(len(body))])
                stream=io.StringIO();writer=csv.writer(stream);writer.writerows([*rows,[record,'','']]);archive.writestr(record,stream.getvalue())
            raw=(packages/'wheels'/filename).read_bytes();cohort['wheels'].append(dict(distribution=distribution,file=filename,bytes=len(raw),sha256=sha(raw)))
        path=packages/'cohort.json';path.write_text(json.dumps(cohort))
        return path,consumer,environment

    def collect(self, adapter, fixture, operation, output=None, extra=()):
        manifest,consumer,environment=fixture
        output=output or self.root/'measurement'
        args=[sys.executable,'-I','-B',str(SCRIPT),'--adapter',adapter,'--manifest',str(manifest),
              '--consumer',str(consumer),'--source',SOURCE,'--output',str(output),'--operation',operation,*extra]
        if environment:args+=['--venv',str(environment)]
        result=subprocess.run(args,capture_output=True,text=True)
        path=output/'measurements.json'
        report=json.loads(path.read_text()) if path.exists() else None
        return result,report,output

    def test_native_cold_uses_actual_distinct_children_and_same_original(self):
        result,report,output=self.collect('native',self.native(),'cold-existing')
        self.assertEqual(result.returncode,0,result.stderr)
        rows=report['latency'][0]['samples'];self.assertEqual(len(rows),3)
        self.assertEqual(len({r['pid'] for r in rows}),3)
        self.assertNotIn(report['seed']['pid'],{r['pid'] for r in rows})
        self.assertEqual((output/'existing-state/events').read_text().splitlines(),['submit','result','result','result'])
        self.assertTrue(report['cleanup']['closed']);self.assertFalse(report['fullAcceptance'])
        self.assertIsNone(report['structuralCounters'])
        self.assertTrue(all(r['wallNs']>0 for r in rows))
        self.assertTrue(report['missing'])

    def test_native_initialization_has_distinct_states_and_is_not_warm_host(self):
        fixture=self.native()
        result,report,_=self.collect('native',fixture,'first-init')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(len({r['stateId'] for r in report['latency'][0]['samples']}),3)
        result,_,_=self.collect('native',fixture,'warm-select',self.root/'wrong-warm')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('not retained-Host warm',result.stderr)

    def test_native_failure_keeps_actual_failed_sample_and_never_retries(self):
        result,report,output=self.collect('native',self.native(fail_result=True),'cold-existing')
        self.assertEqual(result.returncode,1,result.stderr)
        rows=report['latency'][0]['samples'];self.assertEqual(len(rows),1)
        self.assertFalse(rows[0]['verified']);self.assertGreater(rows[0]['wallNs'],0)
        self.assertTrue(report['cleanup']['closed'])
        self.assertEqual((output/'existing-state/events').read_text().splitlines(),['submit','result'])
        self.assertEqual(report['failedObservation']['commands'][0]['code'],1)

    def test_modified_installed_payload_refuses_before_execution(self):
        fixture=self.native();launcher=fixture[1]/'bin/actql.mjs';launcher.write_text(launcher.read_text()+'\n# altered\n')
        result,report,_=self.collect('native',fixture,'cold-existing')
        self.assertNotEqual(result.returncode,0);self.assertIsNone(report)

    def test_source_symlink_is_not_an_installed_consumer(self):
        manifest,consumer,environment=self.native()
        link=self.root/'linked-consumer';link.symlink_to(consumer,target_is_directory=True)
        result,report,_=self.collect('native',(manifest,link,environment),'first-init')
        self.assertNotEqual(result.returncode,0);self.assertIsNone(report)
        self.assertIn('source symlink',result.stderr)

    def test_python_warm_keeps_one_real_host_and_returns_cleanup(self):
        result,report,output=self.collect('python',self.python(),'warm-result')
        self.assertEqual(result.returncode,0,result.stderr)
        rows=report['latency'][0]['samples'];self.assertEqual(len(rows),3)
        self.assertEqual(len({r['pid'] for r in rows}),1);self.assertEqual(len({r['hostId'] for r in rows}),1)
        events=[json.loads(x) for x in (output/'existing-state/events').read_text().splitlines()]
        self.assertEqual([x['event'] for x in events],['open','submit','result','result','result','close'])
        self.assertTrue(report['cleanup']['closed']);self.assertIsNone(report['databaseReads'])

    def test_python_join_and_aggregate_keep_the_same_retained_host(self):
        fixture = self.python(small_queries=True)
        for operation in ['warm-join', 'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode']:
            with self.subTest(operation=operation):
                result, report, output = self.collect('python', fixture, operation, self.root/operation)
                self.assertEqual(result.returncode, 0, result.stderr)
                rows = report['latency'][0]['samples']
                self.assertEqual(len(rows), 3)
                self.assertEqual(len({row['pid'] for row in rows}), 1)
                self.assertEqual(len({row['hostId'] for row in rows}), 1)
                events = [json.loads(line)['event'] for line in (output/'existing-state/events').read_text().splitlines()]
                self.assertEqual(events.count('open'), 1)
                self.assertEqual(events.count('submit'), 4)
                self.assertEqual(events.count('close'), 1)
                self.assertTrue(report['cleanup']['closed'])
                self.assertTrue(all(row['verified'] for row in rows))
                self.assertTrue(all(row['publicTiming']['kind']=='public-result' and
                    row['publicTiming']['startNs']<=row['publicTiming']['observedNs']<=row['publicTiming']['endNs']
                    and row['peakRssBytes']>0 for row in rows))

    def test_python_cold_retains_reference_without_another_submission(self):
        result,report,output=self.collect('python',self.python(),'cold-existing')
        self.assertEqual(result.returncode,0,result.stderr)
        rows=report['latency'][0]['samples'];self.assertEqual(len({r['pid']for r in rows}),3)
        events=[json.loads(x) for x in (output/'existing-state/events').read_text().splitlines()]
        self.assertEqual(sum(x['event']=='submit' for x in events),1)
        self.assertEqual(sum(x['event']=='attach' for x in events),3)
        self.assertEqual(sum(x['event']=='result' for x in events),3)
        self.assertEqual(sum(x['event']=='close' for x in events),4)

    def test_python_initialization_has_no_extra_saved_result_operation(self):
        result,report,output=self.collect('python',self.python(),'first-init')
        self.assertEqual(result.returncode,0,result.stderr)
        rows=report['latency'][0]['samples'];self.assertEqual(len({r['stateId']for r in rows}),3)
        for row in rows:
            events=[json.loads(x)['event']for x in (Path(row['stateId'])/'events').read_text().splitlines()]
            self.assertEqual(events,['open','submit','close'])

    def test_python_select_and_status_use_the_public_route_and_real_samples(self):
        fixture=self.python()
        for operation in ['warm-select','warm-status']:
            result,report,output=self.collect('python',fixture,operation,self.root/operation,
                                            extra=['--mode','final'] if operation=='warm-select' else ())
            self.assertEqual(result.returncode,0,result.stderr)
            count=100 if operation=='warm-select'else 3
            self.assertEqual(len(report['latency'][0]['samples']),count)
            events=[json.loads(x)['event']for x in (output/'existing-state/events').read_text().splitlines()]
            self.assertEqual(events.count('submit'),101 if operation=='warm-select'else 1)
            self.assertEqual(events.count('status'),0 if operation=='warm-select'else 4)
            self.assertEqual(events.count('result'),0)
            self.assertEqual(events[-1],'close')

    def test_wrong_source_refuses_before_any_execution(self):
        fixture=self.python();manifest=json.loads(fixture[0].read_text());manifest['source_sha']='b'*40
        fixture[0].write_text(json.dumps(manifest))
        result,report,_=self.collect('python',fixture,'first-init')
        self.assertNotEqual(result.returncode,0);self.assertIsNone(report)

    def test_python_failed_close_cannot_qualify_successful_rows(self):
        result,report,_=self.collect('python',self.python(fail_close=True),'first-init')
        self.assertEqual(result.returncode,1,result.stderr)
        self.assertFalse(report['cleanup']['closed'])
        self.assertFalse(report['functional']['rows'][0]['completed'])
        self.assertEqual(len(report['latency'][0]['samples']),1)
        self.assertFalse(report['latency'][0]['samples'][0]['verified'])

    def test_payload_changed_during_close_invalidates_functional_completion(self):
        fixture=self.python(alter_on_close=True)
        installed=fixture[1]/'actql/__init__.py';before=installed.read_bytes()
        result,report,_=self.collect('python',fixture,'warm-result')
        self.assertEqual(result.returncode,1,result.stderr)
        self.assertNotEqual(installed.read_bytes(),before)
        self.assertTrue(report['cleanup']['closed'])
        self.assertEqual(len(report['latency'][0]['samples']),3)
        self.assertTrue(all(row['verified'] for row in report['latency'][0]['samples']))
        self.assertIn('Installed payload differs',report['packageFailure'])
        self.assertFalse(report['installedPayloadsUnchanged'])
        self.assertFalse(report['functional']['rows'][0]['completed'])
        self.assertNotIn('actualSha256',report['functional']['rows'][0])
        self.assertFalse(report['fullAcceptance'])

    def test_existing_assessor_keeps_selected_process_success_incomplete(self):
        result,report,output=self.collect('native',self.native(),'first-init')
        self.assertEqual(result.returncode,0,result.stderr)
        original=(output/'measurements.json').read_bytes()
        # Fixed assessor vectors, not runtime performance observations. The
        # synthetic CLI fixture's real startup can cross 200ms under load;
        # that must not make this missing-evidence assertion nondeterministic.
        # Keep the original collector report untouched in either case.
        for wall_ns,expected in [(100_000_000,'incomplete'),(201_000_000,'failed')]:
            with self.subTest(wall_ns=wall_ns):
                vector=json.loads(original)
                for series in vector['latency']:
                    for row in series['samples']:
                        row['wallNs']=wall_ns
                        row['publicTiming']=dict(kind='cli-result-exit',startNs=0,
                            exitNs=wall_ns//2,observedNs=3*wall_ns//4,endNs=wall_ns)
                path=output/f'synthetic-assessor-{wall_ns}.json'
                path.write_text(json.dumps(vector))
                assessment=subprocess.run(['node',str(SCRIPT.with_name('operation-performance.mjs')),
                    '--input',str(path)],capture_output=True,text=True)
                self.assertEqual(assessment.returncode,1,assessment.stderr)
                body=json.loads(assessment.stdout)
                self.assertEqual(body['status'],expected)
                for section in ['structure','history','chunks','boundaries']:
                    self.assertIn(section,body['missing'])
        self.assertEqual((output/'measurements.json').read_bytes(),original)

    def test_python_priority_varies_new_runs_and_reads_their_same_originals(self):
        result,report,output=self.collect('python',self.python(priority=True),'warm-select',
            extra=['--selection','priority-transition'])
        self.assertEqual(result.returncode,0,result.stderr)
        new,saved=report['latency'];first=report['firstQuery']
        self.assertEqual([row['operation'] for row in report['latency']],['warm-select','warm-result'])
        self.assertEqual([len(row['samples']) for row in report['latency']],[3,3])
        samples=[first,*new['samples'],*saved['samples']]
        self.assertEqual(len({row['pid'] for row in samples}),1)
        self.assertEqual(first['pid'],report['command']['pid'])
        self.assertEqual(len({row['hostId'] for row in samples}),1)
        self.assertEqual(len({row['stateId'] for row in samples}),1)
        self.assertEqual(len({row['publicOperationId'] for row in samples}),7)
        self.assertEqual(len({row['runRefSha256'] for row in [first,*new['samples']]}),4)
        self.assertEqual([row['resultRefSha256'] for row in saved['samples']],
                         [row['resultRefSha256'] for row in new['samples']])
        self.assertNotIn(first['resultRefSha256'],{row['resultRefSha256'] for row in saved['samples']})
        events=[json.loads(x) for x in (output/'new-state/events').read_text().splitlines()]
        self.assertEqual([row['value'] for row in events if row['event']=='submit'],[0,1,2,3])
        self.assertEqual([row['value'] for row in events if row['event']=='result'],[1,2,3])
        self.assertEqual(report['publicCallAttempts'],dict(open=1,sql=4,savedResultAll=3,close=1))
        self.assertTrue(all(row['completed'] for row in report['functional']['rows']))
        self.assertIsNone(report['population']);self.assertIsNone(report['structuralCounters'])
        self.assertNotIn('noCompetingLargeBuild',report['priorityConditions'])
        assessment_input=output/'priority-input.json'
        assessment_input.write_text(json.dumps(dict(sourceSha=SOURCE,platforms=dict(python=[report]))))
        assessed=subprocess.run(['node',str(SCRIPT.with_name('operation-performance.mjs')),
            '--priority-transition',str(assessment_input)],capture_output=True,text=True)
        self.assertEqual(assessed.returncode,1,assessed.stderr)
        body=json.loads(assessed.stdout);self.assertEqual(body['status'],'incomplete')
        for operation in ['warm-select','warm-result']:
            self.assertEqual(body['gates']['python']['checks'][operation+' workload']['status'],'passed')
        self.assertIn('python: actual guaranteesUnchanged observation',body['missing'])

    def test_python_priority_final_has_real_100_samples_per_route(self):
        # Fast explicit synthetic processes establish collector coverage only.
        result,report,output=self.collect('python',self.python(priority=True),'warm-select',
            extra=['--selection','priority-transition','--mode','final'])
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual([len(row['samples']) for row in report['latency']],[100,100])
        new,saved=report['latency']
        self.assertEqual(len({row['querySha256'] for row in new['samples']}),100)
        self.assertEqual(len({row['runRefSha256'] for row in new['samples']}),100)
        self.assertEqual(len({row['resultRefSha256'] for row in saved['samples']}),3)
        self.assertEqual(report['publicCallAttempts'],dict(open=1,sql=101,savedResultAll=100,close=1))
        events=[json.loads(x) for x in (output/'new-state/events').read_text().splitlines()]
        self.assertEqual(sum(row['event']=='submit' for row in events),101)
        self.assertEqual(sum(row['event']=='result' for row in events),100)
        self.assertFalse(report['fullAcceptance'])

    def test_python_priority_unknown_stops_without_inheriting_prior_identity(self):
        result,report,output=self.collect('python',self.python(priority=True,fail_query=2),'warm-select',
            extra=['--selection','priority-transition'])
        self.assertEqual(result.returncode,1,result.stderr)
        self.assertEqual(len(report['latency']),1)
        rows=report['latency'][0]['samples'];self.assertEqual(len(rows),2)
        self.assertTrue(rows[0]['verified']);self.assertFalse(rows[1]['verified'])
        for key in ['runRefSha256','resultRefSha256','actualSha256']:
            self.assertNotIn(key,rows[1])
        self.assertIn('Unknown',report['firstFailure']['message'])
        self.assertEqual(report['publicCallAttempts'],dict(open=1,sql=3,savedResultAll=0,close=1))
        self.assertTrue(report['cleanup']['closed'])
        self.assertFalse(report['functional']['rows'][0]['completed'])
        events=[json.loads(x) for x in (output/'new-state/events').read_text().splitlines()]
        self.assertEqual([row['value'] for row in events if row['event']=='failed-submit'],[2])
        self.assertEqual([row['value'] for row in events if row['event']=='submit'],[0,1])

    def test_python_failure_chain_is_bounded_and_does_not_call_properties(self):
        import importlib.util
        spec=importlib.util.spec_from_file_location('collector_failure',SCRIPT)
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        class StoredFailure(Exception):
            @property
            def cleanup_error(self):raise AssertionError('Must not invoke an SDK property')
            def __str__(self):raise AssertionError('Must not invoke an exception formatter')
        original=StoredFailure('x'*4096)
        current=original
        for index in range(10):
            current.original_error=ValueError(str(index));current=current.original_error
        original.validation_error=original
        report=module.python_failure(original)
        self.assertEqual(len(report['errorChain']),8)
        self.assertTrue(report['errorChainTruncated'])
        self.assertEqual(len(report['message']),2048)
        self.assertEqual(report['causes']['validation_error'],0)
        self.assertNotIn('cleanup_error',report['causes'])
        self.assertIsNone(report['code'])
        json.dumps(report)

    def test_python_failure_causes_survive_both_process_collectors(self):
        for priority in (False, True):
            with self.subTest(priority=priority), tempfile.TemporaryDirectory() as directory:
                original_root=self.root;self.root=Path(directory)
                try:
                    fixture=self.python(priority=priority, fail_query=2 if priority else None,
                                        failure_chain=True, fail_close=True)
                    result,report,output=self.collect('python',fixture,
                        'warm-select' if priority else 'warm-result',
                        extra=['--selection','priority-transition'] if priority else [])
                finally:self.root=original_root
                self.assertEqual(result.returncode,1,result.stderr)
                failure=report['latency'][0]['samples'][-1]['error']
                self.assertEqual(failure['code'],'ClientTransportUnknown')
                self.assertEqual(failure['rows_yielded'],0)
                self.assertTrue(failure['cleanup_pending'])
                self.assertEqual(failure['attempt_id'],'synthetic-attempt')
                chain=failure['errorChain'];links=chain[0]['causes']
                self.assertEqual(chain[links['original_error']]['code'],'LocalFileError')
                self.assertEqual(chain[links['cleanup_error']]['message'],'Synthetic pending transport')
                self.assertEqual(chain[links['__cause__']]['name'],'LookupError')
                self.assertEqual(chain[links['__context__']]['name'],'ArithmeticError')
                self.assertEqual(chain[links['validation_error']]['message'],'Synthetic validation')
                self.assertFalse(report['cleanup']['closed'])
                cleanup=report['cleanup'] if priority else report['failedObservation']['cleanup']
                self.assertEqual(cleanup['failure']['message'],'Synthetic cleanup pending')
                self.assertTrue(all(not row['completed'] for row in report['functional']['rows']))
                state=output/('new-state' if priority else 'existing-state')
                events=[json.loads(line) for line in (state/'events').read_text().splitlines()]
                self.assertEqual(sum(row['event']=='close' for row in events),1)
                self.assertEqual(sum(row['event']=='submit' for row in events),2 if priority else 1)

    def test_python_priority_reused_run_refuses_instead_of_counting_a_new_run(self):
        result,report,_=self.collect('python',self.python(priority=True,repeat_reference=True),'warm-select',
            extra=['--selection','priority-transition'])
        self.assertEqual(result.returncode,1,result.stderr)
        self.assertIn('reused',report['firstFailure']['message'])
        self.assertEqual(len(report['latency'][0]['samples']),1)
        self.assertFalse(report['latency'][0]['samples'][0]['verified'])
        self.assertEqual(report['publicCallAttempts']['savedResultAll'],0)

    def test_python_priority_package_and_cleanup_failures_invalidate_both_routes(self):
        for name,options in [('package',dict(alter_on_close=True)),('cleanup',dict(fail_close=True))]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                original_root=self.root;self.root=Path(directory)
                try:
                    result,report,_=self.collect('python',self.python(priority=True,**options),'warm-select',
                        extra=['--selection','priority-transition'])
                finally:self.root=original_root
                self.assertEqual(result.returncode,1,result.stderr)
                self.assertEqual(len(report['functional']['rows']),2)
                self.assertTrue(all(not row['completed'] and 'actualSha256' not in row
                                    for row in report['functional']['rows']))
                if name=='package':
                    self.assertTrue(report['cleanup']['closed']);self.assertTrue(report['packageFailure'])
                else:self.assertFalse(report['cleanup']['closed'])

    def test_python_priority_obvious_slow_sample_stops_before_more_work(self):
        result,report,_=self.collect('python',self.python(priority=True,slow_query=1),'warm-select',
            extra=['--selection','priority-transition'])
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(len(report['latency']),1)
        series=report['latency'][0];self.assertEqual(len(series['samples']),1)
        self.assertGreaterEqual(series['samples'][0]['wallNs'],5_000_000_000)
        self.assertTrue(series['stoppedEarly']);self.assertTrue(report['cleanup']['closed'])
        self.assertEqual(report['publicCallAttempts']['savedResultAll'],0)

    def test_priority_cli_omits_operation_and_refuses_native(self):
        fixture=self.python(priority=True)
        manifest,consumer,environment=fixture;output=self.root/'without-operation'
        result=subprocess.run([sys.executable,'-I','-B',str(SCRIPT),'--adapter','python',
            '--manifest',str(manifest),'--consumer',str(consumer),'--venv',str(environment),
            '--source',SOURCE,'--output',str(output),'--selection','priority-transition'],
            capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(len(json.loads((output/'measurements.json').read_text())['latency']),2)
        # Reject a CLI process as a retained Python Host before any product call.
        with tempfile.TemporaryDirectory() as directory:
            original_root=self.root;self.root=Path(directory)
            try:
                result,report,_=self.collect('native',self.native(),'warm-select',
                    extra=['--selection','priority-transition'])
            finally:self.root=original_root
        self.assertNotEqual(result.returncode,0);self.assertIsNone(report)


    def test_native_operations_variation_originals_and_actual_children(self):
        result,report,output=self.collect('native',self.native(operations=True),'cold-existing',
            extra=['--selection','native-operations'])
        # Ordinary operation is deliberately incompatible; no command ran.
        self.assertNotEqual(result.returncode,0);self.assertIsNone(report)
        fixture=self.native_operations_fixture_in_subdirectory()
        result,report,output=self.collect_native_operations(fixture,self.root/'native-measured')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual([r['operation']for r in report['latency']],['cold-new-run','cold-result'])
        events=[json.loads(x)for x in(output/'new-state/events').read_text().splitlines()]
        self.assertEqual([(r['kind'],r['value'])for r in events],[('run',0),('run',1),('run',2),('run',3),('result',1),('result',2),('result',3)])
        self.assertEqual(len({r['pid']for r in events}),7)
        rows=[r for series in report['latency']for r in series['samples']]
        self.assertEqual(len({r['publicOperationId']for r in rows}),6)
        self.assertEqual(len({r['runRefSha256']for r in rows[:3]}),3)
        self.assertEqual([r['runRefSha256']for r in rows[:3]],[r['runRefSha256']for r in rows[3:]])
        self.assertTrue(all(r['wallNs']>=r['childWallNs']>0 for r in rows))
        first=report['firstQuery'];self.assertEqual(first['publicRunId'],first['publicResponse']['run']['run_id'])
        for index,row in enumerate([first]+rows[:3]):
            name='first'if index==0 else f'new-{index-1}'
            query=(output/'new-state'/(name+'.aql')).resolve()
            self.assertEqual(row['command']['cwd'],row['stateId'])
            self.assertEqual(row['command']['args'],['run',name+'.aql','--output',name+'.jsonl','--json'])
            self.assertEqual(row['queryPath'],str(query))
            self.assertEqual(row['queryFileSha256'],sha(query.read_bytes()))
            self.assertEqual(row['outputPath'],row['publicResponse']['deliveries'][0]['request']['path'])
            self.assertEqual(json.loads(row['command']['stdout']),row['publicResponse'])
        self.assertTrue(report['cleanup']['closed']);self.assertTrue(report['installedPayloadsUnchanged'])
        self.assertTrue(all(r['completed']for r in report['functional']['rows']))
        self.assertIsNone(report['structuralCounters']);self.assertIsNone(report['population'])
        self.assertFalse(report['fullPerformanceAccepted'])
        assessor=Path(__file__).with_name('operation-performance.mjs')
        assessed=subprocess.run(['node',str(assessor),'--native-operations',str(output/'measurements.json')],capture_output=True,text=True)
        self.assertEqual(assessed.returncode,1,assessed.stderr)
        verdict=json.loads(assessed.stdout)
        self.assertEqual(verdict['status'],'incomplete');self.assertFalse(verdict['fullPerformanceAccepted'])
        self.assertIsNone(verdict['checks']['cold-new-run']['summary']['p95Ms'])

    def native_operations_fixture_in_subdirectory(self,**options):
        original=self.root;self.root=original/'native-fixture';self.root.mkdir()
        try:return self.native(operations=True,**options)
        finally:self.root=original

    def collect_native_operations(self,fixture,output=None):
        manifest,consumer,_=fixture;output=output or self.root/'native-output'
        result=subprocess.run([sys.executable,'-I','-B',str(SCRIPT),'--adapter','native',
            '--manifest',str(manifest),'--consumer',str(consumer),'--source',SOURCE,
            '--output',str(output),'--selection','native-operations'],capture_output=True,text=True)
        path=output/'measurements.json'
        return result,json.loads(path.read_text())if path.exists()else None,output

    def test_native_operations_unknown_retains_original_response_and_stops(self):
        result,report,output=self.collect_native_operations(self.native(operations=True,fail_query=2))
        self.assertEqual(result.returncode,1,result.stderr)
        self.assertEqual(report['publicCallAttempts'],{'init':1,'run':3,'result':0})
        rows=report['latency'][0]['samples'];self.assertEqual(len(rows),2)
        self.assertFalse(rows[-1]['verified']);self.assertEqual(rows[-1]['publicRunId'],'synthetic-run-2')
        self.assertEqual(rows[-1]['publicResponse']['run']['status'],'needs_reconciliation')
        self.assertGreater(rows[-1]['wallNs'],0);self.assertTrue(report['cleanup']['closed'])
        self.assertFalse(report['functional']['rows'][0]['completed'])
        events=[json.loads(x)for x in(output/'new-state/events').read_text().splitlines()]
        self.assertEqual([r['value']for r in events],[0,1,2])

    def test_native_operations_saved_failure_never_submits_again(self):
        result,report,_=self.collect_native_operations(self.native(operations=True,fail_result=True))
        self.assertEqual(result.returncode,1,result.stderr)
        self.assertEqual(report['publicCallAttempts'],{'init':1,'run':4,'result':1})
        self.assertFalse(report['latency'][1]['samples'][0]['verified'])
        self.assertEqual(len(report['latency'][1]['samples']),1)
        self.assertTrue(report['cleanup']['closed'])

    def test_native_operations_reused_run_or_changed_package_cannot_qualify(self):
        for name,options in [('run',{'reuse_run':True}),('package',{'alter_result':True})]:
            with self.subTest(name=name),tempfile.TemporaryDirectory()as directory:
                original=self.root;self.root=Path(directory)
                try:result,report,_=self.collect_native_operations(self.native(operations=True,**options))
                finally:self.root=original
                self.assertEqual(result.returncode,1,result.stderr)
                self.assertTrue(all(not row['completed']and 'actualSha256'not in row for row in report['functional']['rows']))
                if name=='package':self.assertTrue(report['packageFailure'])
                else:self.assertIn('reused',report['firstFailure']['message'])

    def test_native_operations_slow_prefix_has_no_complete_population(self):
        result,report,_=self.collect_native_operations(self.native(operations=True,slow_query=1))
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(report['publicCallAttempts'],{'init':1,'run':2,'result':0})
        self.assertEqual(len(report['latency'][0]['samples']),1)
        self.assertTrue(report['latency'][0]['stoppedEarly'])
        self.assertFalse(report['functional']['rows'][0]['completed'])
        self.assertNotIn('actualSha256',report['functional']['rows'][0])


if __name__=='__main__':
    unittest.main()
