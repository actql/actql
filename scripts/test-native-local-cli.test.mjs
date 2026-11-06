// Installed Native ingress and bounded Pure row-demand controls. Source
// execution, approval and full recovery remain separate acceptance subjects.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {cp, mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {after, test} from 'node:test';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {verifyNativeLocalCheckEnvironmentOriginal} from './test-native-local-source-result.mjs';

const executable=process.env.ACTQL_TEST_NATIVE_CLIENT_BINARY;
assert(executable && process.env.ACTQL_TEST_NATIVE_CLIENT_LAUNCHER,
  'Select the actual installed Native Local launcher and binary');
const scratch = await createOwnedScratch({parent: process.platform==='darwin'?'/private/tmp':tmpdir(), prefix: 'actql-native-local-cli-',
  label: 'Native Local CLI ingress'});
const project=join(scratch.path,'project');
const emptyPath = join(scratch.path, 'empty-path');
await mkdir(emptyPath);
console.log(`Native CLI binary sha256:${createHash('sha256').update(await readFile(executable)).digest('hex')}`);
// Only the installed launcher's actual initialization creates the Product,
// Account and runtime bindings. Program fixtures do not construct that context.
const initialized=runNative(['init',project],scratch.path);
assert.equal(initialized.status,0,initialized.stderr);
assert.match(initialized.stdout,/^Local Host adopted; no Run has been admitted\./u);
const originalConfiguration=await readFile(join(project,'actql.config.json'));
const fixtures=fileURLToPath(new URL('./fixtures/native-local-cli',import.meta.url));
for(const name of await readdir(fixtures)) {
  if(name!=='actql.config.json') await cp(join(fixtures,name),join(project,name));
}
const originalEnvironment=await readFile(join(project,'environment.json'));
verifyNativeLocalCheckEnvironmentOriginal(originalEnvironment);
after(async()=>{
  assert.deepEqual(await readFile(join(project,'environment.json')),originalEnvironment);
  assert.deepEqual(await readFile(join(project,'actql.config.json')),originalConfiguration);
  scratch.passed();
});

function check(file, format = 'json', options = [], global = []) {
  const selection=global.length===0?[]:['--mode','local',...global];
  const args=[...selection,'check','--program-file',file,'--format',format,'--json',...options];
  return runNative(args);
}

function runNative(args,cwd=project) {
  const launcher = process.env.ACTQL_TEST_NATIVE_CLIENT_LAUNCHER;
  const result = spawnSync(process.execPath,[launcher,...args],
    {cwd,env:{PATH:emptyPath,LANG:'C'},maxBuffer:65536,
      encoding: 'utf8', timeout: 15_000});
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  return result;
}

for (const [file, format] of [['values.json', 'json'], ['literal.sql', 'sql']]) {
  test(`Native Local checks ${format} in its actual adopted Host without admitting a Run`, async () => {
    const result = check(file, format);
    assert.equal(result.status, 0, result.stderr);
    const report = JSON.parse(result.stdout);
    assert.equal(report.version,'actql-check-outcome/0.1');
    assert.equal(report.outcome,'completed');
    assert.equal(report.report.verdict,'verified');
    assert.equal(report.report.runnable.verdict,'yes');
    assert.equal(report.report.scope.kind,'bound_input');
    const input=report.report.inputs.find(value=>value.document_id===(format==='json'?'program':'source'));
    assert.equal(input.byte_length,(await readFile(join(project,file))).length);
    assert.match(input.revision,/^rev:[0-9a-f]{64}$/u);
    for(const key of ['run','verified','programDefinitionCid','parameterValuesCid'])
      assert.equal(Object.hasOwn(report,key),false,key);
  });
}

test('Native Local rejects wrong text form without a JSON fallback', async () => {
  const result = check('values.json', 'aql-text');
  assert.equal(result.status, 1);
  const outcome=JSON.parse(result.stdout);
  assert.equal(outcome.version,'actql-check-outcome/0.1');
  assert.equal(outcome.outcome,'completed');
  assert.equal(outcome.report.verdict,'invalid');
  const source=outcome.report.inputs.find(input=>input.document_id==='source');
  assert.equal(source.kind,'text');
  assert.equal(source.byte_length,(await readFile(join(project,'values.json'))).length);
  assert.match(source.revision,/^rev:[0-9a-f]{64}$/u);
  assert.equal(outcome.report.inputs.some(input=>input.document_id==='program'),false);
  assert(outcome.report.reasons.some(reason=>reason.code==='query_syntax_invalid'));
});

test('Native Local never switches to a Remote endpoint', () => {
  const result = check('values.json', 'json', [], ['--endpoint', 'https://127.0.0.1:1/']);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /Local mode cannot use Remote connection options/u);
});

test('Native Remote refuses a Local cancellation Submission binding before transport setup', () => {
  for (const operation of ['lookup-cancellation', 'cancel']) {
    const options = operation === 'cancel' ? ['--operation-attempt-id', 'original-invocation'] : [];
    const result = runNative(['--mode', 'remote', operation, '--ref-file', 'absent-run.json',
      '--submission-ref-file', 'absent-submission.json', '--cancel-id', 'original', '--expected-revision', '0', ...options]);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /Original Local submission binding is unavailable in Remote mode/u);
  }
});

test('Native Remote refuses Local original-delivery bindings before transport setup', () => {
  const common = ['--mode', 'remote', 'delivery-attempt', '--ref-file', 'absent-run.json',
    '--result-name', 'answer', '--attempt-id', 'original'];
  for (const [options, reason] of [
    [['--submission-ref-file', 'absent-submission.json'], /Original Local submission binding is unavailable in Remote mode/u],
    [['--purpose', 'cli-read'], /Explicit Local delivery purpose is unavailable in Remote mode/u],
  ]) {
    const result = runNative([...common, ...options]);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, reason);
  }
});

test('Native Local retains parameter values and distinguishes wrong type', async () => {
  await writeFile(join(project, 'parameter.sql'), 'SELECT @message AS message\n');
  await writeFile(join(project, 'declarations.json'), JSON.stringify({message: {type: 'string'}}));
  const revisions = [];
  for (const [index, value] of ['e\u0301', 'é', '\r', '\n', '\r\n'].entries()) {
    const name = `parameters-${index}.json`;
    const original=Buffer.from(JSON.stringify({message:value}));
    await writeFile(join(project,name),original);
    const result = check('parameter.sql', 'sql', ['--parameter-declarations-file', 'declarations.json',
      '--parameters-file', name]);
    assert.equal(result.status, 0, result.stderr);
    const outcome=JSON.parse(result.stdout);
    assert.equal(outcome.outcome,'completed');assert.equal(outcome.report.verdict,'verified');
    const input=outcome.report.inputs.find(value=>value.document_id==='parameters');
    assert.equal(input.byte_length,original.length);assert.match(input.revision,/^rev:[0-9a-f]{64}$/u);
    revisions.push(input.revision);
    assert.deepEqual(await readFile(join(project,name)),original);
    assert.equal(result.stdout.includes('message'), false);
  }
  assert.equal(revisions.length,5); // Per-command HMAC revisions are opaque, not deterministic value CIDs.
  await writeFile(join(project, 'wrong-type.json'), '{"message":null}');
  const wrong = check('parameter.sql', 'sql', ['--parameter-declarations-file', 'declarations.json',
    '--parameters-file', 'wrong-type.json']);
  assert.equal(wrong.status, 1);
  const invalid=JSON.parse(wrong.stdout);
  assert.equal(invalid.outcome,'completed');assert.equal(invalid.report.verdict,'invalid');
  assert(invalid.report.reasons.some(reason=>reason.code==='supplied_value_type_mismatch'));
});

test('Native Local rejects legacy Environment overrides before Product startup', async () => {
  // Public Project configuration cannot replace the Product's Environment.
  // Exact wire/CID mismatch admission is covered at the typed Native boundary
  // in local_command_configuration_wbtest.mbt, not by this schema rejection.
  const rejected=join(scratch.path,'legacy-environment-project');
  await mkdir(rejected);
  const configuration=Buffer.from(JSON.stringify({version:'actql-config/0.1',
    state_dir:'./uncreated-state',native:{check_environment:{file:'absent-environment.json',
      evidence_bundle_cid:`sha256:${'0'.repeat(64)}`}}}));
  const path=join(rejected,'actql.config.json');
  await writeFile(path,configuration);
  const result=runNative(['--mode','local','--config',path,'check',
    '--program-file','absent-program.json','--format','json','--json'],rejected);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /InvalidProjectConfiguration/u);
  assert.deepEqual(await readFile(path),configuration);
  assert.deepEqual(await readdir(rejected),['actql.config.json']);
});

test('Native Local refuses duplicate configuration fields', async () => {
  await writeFile(join(project, 'duplicate.json'),
    '{"version":"actql-config/0.1","version":"actql-config/0.1","native":{}}');
  const result=runNative(['--mode','local','--config',join(project,'duplicate.json'),
    'check','--program-file','values.json','--format','json','--json']);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr,/InvalidProjectConfiguration/u);
});

test('Native Local human preparation output does not claim Run acceptance', () => {
  const result=runNative(['check','--program-file','values.json','--format','json']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout,/^ActQL CHECK\nValidation: Valid\nRunnable: yes\nScope: bound input\n/u);
  assert(result.stdout.includes('No Run started; no provider calls.'));
  assert.doesNotMatch(result.stdout,/sha256:|ctx:|rev:|"outcome"|"id"/u);
});

// These are the independently authored 101/1000-row controls used by the
// compilation/explain whitebox case, now driven through the actual CLI Host.
for (const count of [101,1000]) {
  test(`Native Local explains and publishes all authored ${count} rows within original read bounds`, async()=>{
    const document={version:'actql/0.1',id:'cli-static-chain',stages:[{id:'main',inputs:{},
      steps:[{values:{schema:{id:{type:'number',nullable:false}},
        rows:Array.from({length:count},(_,id)=>({id}))},as:'original'},
        {from:'original',filter:'id > 1',as:'filtered'},
        {from:'filtered',select:['id'],as:'selected'}],
      results:{rows:{from:'selected',fields:['id']}}}],
      results:{answer:{from:{stage:'main',result:'rows'}}}};
    const file=`authored-${count}.json`;
    await writeFile(join(project,file),JSON.stringify(document));
    const success=result=>{assert.equal(result.status,0,result.stderr);return JSON.parse(result.stdout);};
    const explanation=success(runNative(['explain','--program-file',file,'--format','json','--json']));
    assert.equal(explanation.version,'actql-plan-view/0.1');
    assert.equal(explanation.provider_io,0);
    const state=success(runNative(['run',file,'--format','json','--json']));
    assert.equal(state.version,'actql-run-state/0.1');
    assert.equal(state.status,'succeeded');assert.equal(typeof state.run_id,'string');
    const delivered=runNative(['result',state.run_id,'--result','answer','--format','jsonl']);
    assert.equal(delivered.status,0,delivered.stderr);
    assert(Buffer.byteLength(delivered.stdout)<=65536);
    assert.deepEqual(delivered.stdout.trimEnd().split('\n').map(line=>JSON.parse(line)),
      Array.from({length:count-2},(_,index)=>({id:index+2})));
  });
}
