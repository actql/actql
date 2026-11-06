// Installed Native ingress and bounded Pure row-demand controls. Source
// execution, approval and full recovery remain separate acceptance subjects.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {cp, mkdir, readFile, writeFile} from 'node:fs/promises';
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
await cp(fileURLToPath(new URL('./fixtures/native-local-cli', import.meta.url)), scratch.path,
  {recursive: true});
const emptyPath = join(scratch.path, 'empty-path');
await mkdir(emptyPath);
console.log(`Native CLI binary sha256:${createHash('sha256').update(await readFile(executable)).digest('hex')}`);
const originalEnvironment=await readFile(join(scratch.path,'environment.json'));
verifyNativeLocalCheckEnvironmentOriginal(originalEnvironment);
const sqlite=process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY,
  crypto=process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY;
assert(sqlite && crypto,'Select both admitted installed Local runtime libraries');
const libraries={sqliteLibrary:sqlite,cryptoLibrary:crypto};
await mkdir(join(scratch.path,'managed'),{mode:0o700});
const permission=(entry_id,resource,operation)=>({entry_id,outcome:'allow',
  principal:{any_of:['operator']},connection:{any_of:['cli']},
  resource:{any_of:[resource]},operation:{any_of:[operation]},exclusions:[]});
await writeFile(join(scratch.path,'account.json'),JSON.stringify({
  version:'actql-execution-account-config/0.1',account_id:'operator',entries:[
    permission('submit','run','submit'),permission('run-read','run','read'),
    permission('result-read','result/answer','read')],
})+'\r\n');
const configuration=JSON.parse(await readFile(join(scratch.path,'actql.config.json'),'utf8'));
configuration.account_config='account.json';
configuration.native.local={account_id:'operator',principal:'operator',connection:'cli',
  state_parent:scratch.path,state_name:'host',managed_root:join(scratch.path,'managed'),
  sqlite_library:libraries.sqliteLibrary,signature_library:libraries.cryptoLibrary,
  submission_ttl_ms:60000,journal_record_limit:8,journal_snapshot_bytes:8388608,
  installation_files:['run-installation.json','read-installation.json'],
  run_file:'run-installation.json',read_file:'read-installation.json'};
const originalConfiguration=Buffer.from(JSON.stringify(configuration)+'\r\n');
await writeFile(join(scratch.path,'actql.config.json'),originalConfiguration);
const adopted=runNative(['--mode','local','--config-root',scratch.path,
  '--config-file','actql.config.json','adopt','--json']);
assert.equal(adopted.status,0,adopted.stderr);
assert.equal(JSON.parse(adopted.stdout).kind,'local_host_adopted');
assert.equal(JSON.parse(adopted.stdout).accountId,'operator');
assert.equal(Object.hasOwn(JSON.parse(adopted.stdout),'run'),false);
after(async()=>{
  assert.deepEqual(await readFile(join(scratch.path,'environment.json')),originalEnvironment);
  assert.deepEqual(await readFile(join(scratch.path,'actql.config.json')),originalConfiguration);
  scratch.passed();
});

function check(file, format = 'json', options = [], global = [], configuration = 'actql.config.json') {
  const args = ['--mode', 'local', '--config-root', scratch.path,
    '--config-file', configuration, ...global, 'check', '--program-file', file,
    '--format', format, '--json', ...options];
  return runNative(args);
}

function runNative(args) {
  const launcher = process.env.ACTQL_TEST_NATIVE_CLIENT_LAUNCHER;
  const result = spawnSync(launcher ? process.execPath : executable,
    launcher ? [launcher, ...args] : args,
    {cwd:scratch.path,env:{PATH:emptyPath,LANG:'C'},
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
    assert.equal(input.byte_length,(await readFile(join(scratch.path,file))).length);
    assert.match(input.revision,/^rev:[0-9a-f]{64}$/u);
    for(const key of ['run','verified','programDefinitionCid','parameterValuesCid'])
      assert.equal(Object.hasOwn(report,key),false,key);
  });
}

test('Native Local rejects wrong text form without a JSON fallback', () => {
  const result = check('values.json', 'aql-text');
  assert.equal(result.status, 1);
  const outcome=JSON.parse(result.stdout);
  assert.equal(outcome.version,'actql-check-outcome/0.1');
  assert.equal(outcome.outcome,'completed');
  assert.equal(outcome.report.verdict,'invalid');
  assert.equal(outcome.report.inputs.find(input=>input.document_id==='source').format,'aql');
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
  await writeFile(join(scratch.path, 'parameter.sql'), 'SELECT @message AS message\n');
  await writeFile(join(scratch.path, 'declarations.json'), JSON.stringify({message: {type: 'string'}}));
  const revisions = [];
  for (const [index, value] of ['e\u0301', 'é', '\r', '\n', '\r\n'].entries()) {
    const name = `parameters-${index}.json`;
    const original=Buffer.from(JSON.stringify({message:value}));
    await writeFile(join(scratch.path,name),original);
    const result = check('parameter.sql', 'sql', ['--parameter-declarations-file', 'declarations.json',
      '--parameters-file', name]);
    assert.equal(result.status, 0, result.stderr);
    const outcome=JSON.parse(result.stdout);
    assert.equal(outcome.outcome,'completed');assert.equal(outcome.report.verdict,'verified');
    const input=outcome.report.inputs.find(value=>value.document_id==='parameters');
    assert.equal(input.byte_length,original.length);assert.match(input.revision,/^rev:[0-9a-f]{64}$/u);
    revisions.push(input.revision);
    assert.deepEqual(await readFile(join(scratch.path,name)),original);
    assert.equal(result.stdout.includes('message'), false);
  }
  assert.equal(revisions.length,5); // Per-command HMAC revisions are opaque, not deterministic value CIDs.
  await writeFile(join(scratch.path, 'wrong-type.json'), '{"message":null}');
  const wrong = check('parameter.sql', 'sql', ['--parameter-declarations-file', 'declarations.json',
    '--parameters-file', 'wrong-type.json']);
  assert.equal(wrong.status, 1);
  const invalid=JSON.parse(wrong.stdout);
  assert.equal(invalid.outcome,'completed');assert.equal(invalid.report.verdict,'invalid');
  assert(invalid.report.reasons.some(reason=>reason.code==='supplied_value_type_mismatch'));
});

test('Native Local validates environment custody instead of trusting a declared CID', async () => {
  const original = await readFile(join(scratch.path, 'actql.config.json'), 'utf8');
  const configuration = JSON.parse(original);
  configuration.native.check_environment.evidence_bundle_cid = `sha256:${'0'.repeat(64)}`;
  await writeFile(join(scratch.path, 'wrong-environment.json'), JSON.stringify(configuration));
  const result = check('values.json', 'json', [], [], 'wrong-environment.json');
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /InvalidLocalCheckEnvironment/u);
});

test('Native Local refuses duplicate configuration fields', async () => {
  await writeFile(join(scratch.path, 'duplicate.json'),
    '{"version":"actql-config/0.1","version":"actql-config/0.1","native":{}}');
  const result = check('values.json', 'json', [], [], 'duplicate.json');
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
});

test('Native Local human preparation output does not claim Run acceptance', () => {
  const result = runNative(['--mode', 'local', '--config-root', scratch.path,
    '--config-file', 'actql.config.json', 'check', '--program-file', 'values.json', '--format', 'json']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout,/^Local check \(no Run admitted\):\n/u);
  const outcome=JSON.parse(result.stdout.slice(result.stdout.indexOf('\n')+1));
  assert.equal(outcome.version,'actql-check-outcome/0.1');
  assert.equal(outcome.report.verdict,'verified');
  assert.equal(result.stdout.includes('"id"'), false);
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
    await writeFile(join(scratch.path,file),JSON.stringify(document));
    const invoke=args=>runNative(['--mode','local','--config-root',scratch.path,
      '--config-file','actql.config.json',...args]);
    const success=result=>{assert.equal(result.status,0,result.stderr);return JSON.parse(result.stdout);};
    const explanation=success(invoke(['explain','--program-file',file,'--format','json','--json']));
    assert.equal(explanation.version,'actql-plan-view/0.1');
    assert.equal(explanation.provider_io,0);
    const submission=success(invoke(['new-submission','--request-id',`authored-${count}`]));
    const submissionFile=`submission-${count}.json`,refFile=`run-${count}.json`;
    await writeFile(join(scratch.path,submissionFile),JSON.stringify(submission));
    const published=success(invoke(['start','--program-file',file,'--submission-ref-file',
      submissionFile,'--operation-attempt-id',`start-${count}`]));
    assert.equal(published.kind,'local_run_published');
    assert.deepEqual(published.resultNames,['answer']);
    await writeFile(join(scratch.path,refFile),JSON.stringify(published.ref));
    const delivered=invoke(['read','--submission-ref-file',submissionFile,'--ref-file',refFile,
      '--result-name','answer','--purpose','inspection','--format','jsonl',
      '--attempt-id',`read-${count}`,'--max-output-bytes','65536']);
    assert.equal(delivered.status,0,delivered.stderr);
    assert(Buffer.byteLength(delivered.stdout)<=65536);
    assert.deepEqual(delivered.stdout.trimEnd().split('\n').map(line=>JSON.parse(line)),
      Array.from({length:count-2},(_,index)=>({id:index+2})));
  });
}
