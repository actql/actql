import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'yaml';

test('temporary Crypto diagnostic requires the original inferior result and only one manual C job', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  assert.deepEqual(Object.keys(workflow.on), ['workflow_dispatch']);
  assert.deepEqual(Object.keys(workflow.jobs), ['crypto-partial']);
  const job = workflow.jobs['crypto-partial'];
  assert.equal(job['runs-on'], 'ubuntu-24.04');
  const commands = job.steps.map(step => step.run ?? '').join('\n');
  assert(commands.includes('scripts/diagnose-native-crypto-partial.py'));
  assert(!/produce-native-cli|npm (?:run|ci)|moon (?:build|test)|test-native-approval/u.test(commands));
  assert.deepEqual(job.permissions, {contents: 'read'});
  const code = String.raw`
import ast, importlib.util, json
from pathlib import Path
path=Path('scripts/diagnose-native-crypto-partial.py')
ast.parse(path.read_text())
spec=importlib.util.spec_from_file_location('diagnostic',path)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
row=json.dumps({'case':'partial','passed':True,'original_cleanup':True})
def output(value): return m.MARKER+json.dumps(value)+'\n'+row+'\n'
good={'signal':None,'inferiorExitCode':0,'killedAfterStop':False}
assert m.assess(0,output(good))['passed']
assert not m.assess(0,output({**good,'signal':'SIGSEGV','inferiorExitCode':None,'killedAfterStop':True}))['passed']
assert not m.assess(0,output({**good,'inferiorExitCode':1}))['passed']
assert not m.assess(0,output({**good,'watchdogFired':True}))['passed']
assert not m.assess(1,output(good))['passed']
assert not m.assess(0,m.MARKER+json.dumps(good)+'\n')['passed']
try: m.assess(0,'')
except ValueError: pass
else: raise AssertionError('missing observation accepted')
script=m.debugger_script(Path('/tmp/fixture'),[('main','entry')])
assert script.count("gdb.execute('run'")==1
assert "gdb.execute('kill'" in script
assert 'threading.Timer(30' in script
assert 'handle SIGSEGV stop nopass print' in script and 'noprint' not in script
assert "info signals SIGSEGV" in script and "Signal stop policy mismatch" in script
assert 'frame.read_var' not in script and 'bt full' not in script
print('original inferior status, no false signal pass, bounded one-run script verified')
`;
  const result = spawnSync('python3', ['-c', code], {cwd: new URL('..', import.meta.url), encoding: 'utf8', timeout: 10000});
  assert.equal(result.status, 0, result.stdout + result.stderr);
});
