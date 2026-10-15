// Process-flow counters with an explicit public Client double. No actual
// SDK/Host/Core/Store/Provider, numerical supplier or installed E2E is proved.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

const script = readFileSync(new URL('./fixtures/first-m1-public-process.mjs', import.meta.url));
function fixture(t, options = {}) {
  const root = mkdtempSync(join(tmpdir(), 'actql-m1-public-flow-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const app = join(root, 'application.mjs'), state = join(root, 'state'), evidence = join(root, 'evidence');
  const trace = join(root, 'trace.jsonl'), entry = join(root, 'consumer.mjs');
  mkdirSync(join(root, 'node_modules/@actql/node'), {recursive: true});
  writeFileSync(entry, script);
  writeFileSync(join(root, 'node_modules/@actql/node/package.json'), JSON.stringify({
    type: 'module', exports: './index.mjs',
  }));
  writeFileSync(join(root, 'node_modules/@actql/node/index.mjs'), `
import assert from 'node:assert/strict';
import {appendFileSync,existsSync,mkdirSync,readFileSync} from 'node:fs';
const trace=name=>appendFileSync(${JSON.stringify(trace)},JSON.stringify(name)+'\\n');
const selected=${JSON.stringify(options)};
const ref={namespaceId:'fixture',authorityScopeCid:'fixture-scope',runDefinitionCid:'fixture-definition',runId:'run-original'};
const checkpoint={kind:'model_invocation',checkpointCid:'fixture-checkpoint',subject:{runDefinitionCid:ref.runDefinitionCid}};
const fail=code=>Object.assign(new Error('Do not log this private fixture body'),{code});
export async function open(options){
  trace('open');assert.equal(options.stateDir,${JSON.stringify(state)});assert.equal(options.durability,'durable');
  mkdirSync(options.stateDir,{recursive:true});
  const run={ref,
    async status(){trace('status');return{status:'succeeded'};},
    async wait(){trace('wait');return{status:'succeeded'};},
    result(name){trace('result');assert.equal(name,'answer');return{async all(options){trace('all');assert.equal(options.maxRows,1);return[{value:selected.wrongAnswer?'private-unexpected-answer':'expected'}];}};
    },
  };
  return{
    newSubmission(){trace('newSubmission');return{nonce:'original-fixture-nonce'};},
    async start(program,options){trace('start');assert.deepEqual(program,{fixture:true});
      assert.ok(existsSync(${JSON.stringify(join(evidence, 'submission.json'))}));
      assert.deepEqual(JSON.parse(readFileSync(${JSON.stringify(join(evidence, 'submission.json'))},'utf8')),options.submissionRef);
      if(selected.startUnknown)throw fail('SubmissionUnknown');return run;},
    async checkpoints(){trace('checkpoints');return{items:[checkpoint]};},
    async reviewCheckpoint(value){trace('review');assert.strictEqual(value,checkpoint);return{bytes:new Uint8Array([1])};},
    async resolveCheckpoints(items,options){trace('resolve');assert.strictEqual(items[0].checkpoint,checkpoint);
      assert.equal(items[0].decision,'approved');assert.equal(typeof options.signer.sign,'function');
      assert.ok(existsSync(${JSON.stringify(join(evidence, 'approval-attempt.json'))}));
      if(selected.resolutionUnknown)throw fail('ResolutionUnknown');return{results:[{status:'committed'}],signed:[]};},
    async attach(value){trace('attach');assert.deepEqual(value,ref);return run;},
    async close(){trace('close');if(selected.closeUnknown)throw fail('CleanupUnknown');},
  };
}
`);
  writeFileSync(app, `import{appendFileSync}from'node:fs';
appendFileSync(${JSON.stringify(trace)},JSON.stringify('application-import')+'\\n');
export default {installation:{},program:{fixture:true},resultName:'answer',expectedRows:[{value:'expected'}],
  ${options.noSigner ? '' : 'signer:{sign(){throw new Error("Client double must not invoke signing");}},'}
};
`);
  const events = () => existsSync(trace) ? readFileSync(trace, 'utf8').trim().split('\n').map(JSON.parse) : [];
  const child = (phase, selectedApp = app) => {
    const result = spawnSync(process.execPath, [entry, phase, selectedApp, state, evidence, '2000'], {
      cwd: root, env: {PATH: process.env.PATH}, timeout: 5000, maxBuffer: 65536, encoding: 'utf8',
    });
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.equal(result.stderr, '', result.stderr);
    return {...result, value: JSON.parse(result.stdout.trim())};
  };
  return {root, app, state, evidence, trace, events, child};
}

test('first M1 public process uses one live original Host through review approval and Named Result', t => {
  const f = fixture(t); const result = f.child('run');
  assert.equal(result.status, 0);
  assert.deepEqual(f.events(), ['application-import', 'open', 'newSubmission', 'start',
    'checkpoints', 'review', 'resolve', 'wait', 'result', 'all', 'close']);
  assert.equal(result.value.outcome, 'original_named_result_matched');
  assert.equal(result.value.physicalDispatches, null);
  assert.equal(result.value.physicalCleanup, 'not_independently_measured');
  assert.equal(result.value.normalProfile, null);
});

test('first M1 fresh process reads the same Result without submit approve or reconciliation', t => {
  const f = fixture(t); assert.equal(f.child('run').status, 0);
  const before = f.events().length;
  const result = f.child('read'); assert.equal(result.status, 0);
  assert.deepEqual(f.events().slice(before), ['application-import', 'open', 'attach',
    'status', 'result', 'all', 'close']);
});

test('first M1 repeat run refuses before importing the application or opening another Host', t => {
  const f = fixture(t); assert.equal(f.child('run').status, 0);
  const before = f.events(); const result = f.child('run');
  assert.equal(result.status, 1); assert.equal(result.value.error, 'M1FreshStartRequired');
  assert.deepEqual(f.events(), before);
});

test('first M1 unknown submission retains the original nonce and never resubmits', t => {
  const f = fixture(t, {startUnknown: true}); const result = f.child('run');
  assert.equal(result.status, 1); assert.equal(result.value.error, 'SubmissionUnknown');
  assert.deepEqual(f.events(), ['application-import', 'open', 'newSubmission', 'start', 'close']);
  assert.ok(existsSync(join(f.evidence, 'submission.json')));
  assert.equal(existsSync(join(f.evidence, 'run.json')), false);
  assert.equal(f.child('run').value.error, 'M1FreshStartRequired');
});

test('first M1 lost approval reply and failed close retain both original responsibilities', t => {
  const f = fixture(t, {resolutionUnknown: true, closeUnknown: true}); const result = f.child('run');
  assert.equal(result.status, 1); assert.equal(result.value.error, 'ResolutionUnknown');
  assert.equal(result.value.cleanupError, 'CleanupUnknown');
  assert.ok(existsSync(join(f.evidence, 'approval-attempt.json')));
  assert.equal(f.events().filter(value => value === 'resolve').length, 1);
  assert.equal(f.events().includes('result'), false);
  assert.equal(result.stdout.includes('private fixture'), false);
});

test('first M1 read refuses a changed original application before Host acquisition', t => {
  const f = fixture(t); assert.equal(f.child('run').status, 0);
  const before = f.events(); writeFileSync(f.app, readFileSync(f.app, 'utf8') + '\n// changed\n');
  const result = f.child('read'); assert.equal(result.status, 1);
  assert.equal(result.value.error, 'ERR_ASSERTION');
  assert.deepEqual(f.events(), before);
});

test('first M1 requires a reviewer before opening or submitting', t => {
  const f = fixture(t, {noSigner: true}); const result = f.child('run');
  assert.equal(result.status, 1); assert.equal(result.value.error, 'M1ReviewerRequired');
  assert.deepEqual(f.events(), ['application-import']);
});

test('first M1 mismatched answer fails without disclosing raw expected or returned values', t => {
  const f = fixture(t, {wrongAnswer: true}); const result = f.child('run');
  assert.equal(result.status, 1); assert.equal(result.value.error, 'ERR_ASSERTION');
  assert.equal(result.stdout.includes('private-unexpected-answer'), false);
  assert.equal(result.stdout.includes('expected'), false);
  assert.equal(f.events().at(-1), 'close');
});
