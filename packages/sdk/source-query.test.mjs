import {submissionEpoch, originalSubmission, readySubmissionAttempt, heldSubmissionAttempt} from './submission-fixture.mjs';
import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {mkdir, copyFile, readFile, writeFile, lstat, readlink, realpath} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {CLIENT_PACKAGES, packedClientPackage, packedNpmCache} from '../../scripts/packed-client-packages.mjs';
import {connect, getSubmissionInput, getSubmissionOutcome, explainSubmission, RequestHeld} from './index.mjs';
import {validRunState, validRunWaitContract} from '@actql/client-wire';

const cid = x => `sha256:${x.repeat(64)}`;
const ref = {namespaceId: 'query-test', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')};
const profile = {submissionEpoch, version: 'actql-client-host/0.1', mode: 'remote',
  owner: 'remote', durability: 'durable', scopeRef: 'query-scope',
  capabilities: [], limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const time = '2026-10-07T00:00:00.000Z';
function succeeded(names = ['answer']) {
  return {version: 'actql-run-state/0.1', run_id: 'run-query',
    // This double represents a published observation at revision1. It does
    // not supply a missing producer revision or infer one from terminal status.
    status: 'succeeded', revision: 1, updated_at: time,
    next_action: {kind: 'read_result', results: names}, result_available: true,
    result_availability: Object.fromEntries(names.map(name => [name,
      {state: 'available', observed_at: time, reason: 'confirmed_present'}]))};
}
async function fixture(t, overrides = {}, token = 'token') {
  const calls = [];
  mock.method(globalThis, 'fetch', async (url, init) => {
    const operation = url.pathname.split('/').at(-1);
    const body = JSON.parse(init.body);
    calls.push({operation, body});
    if (overrides[operation]) return overrides[operation](body, init);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'submit-intent') return Response.json(readySubmissionAttempt(body, {ref, durability: 'durable', revision: 1}));
    if (operation === 'attach') {
      return Response.json({ref, durability: 'durable', revision: 1});
    }
    if (operation === 'wait') return Response.json(succeeded());
    if (operation === 'read') return new Response('{"id":1}\n\x1e');
    assert.fail(`Unexpected operation ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const client = await connect({mode: 'remote', endpoint: 'https://host.example/', token});
  t.after(() => client.close());
  return {client, calls, count: name => calls.filter(x => x.operation === name).length};
}

test('short queries eagerly submit once and share a native Promise Result', async t => {
  const f = await fixture(t);
  const query = f.client.sql('SELECT 1 AS id');
  assert.ok(query instanceof Promise);
  assert.match(query.requestId, /^[0-9a-f-]{36}$/u);
  const [first, second, third] = await Promise.all([query, query,
    Promise.resolve(query).then(result => result)]);
  assert.equal(first, second); assert.equal(first, third);
  assert.equal(first.then, undefined);
  assert.deepEqual(first.ref, {run: ref, resultName: 'answer'});
  assert.deepEqual(first.execution.ref, ref);
  assert.equal(await query.finally(() => {}), first);
  assert.equal(await query.catch(() => assert.fail('unexpected rejection')), first);
  assert.deepEqual(await query.all(), [{id: 1}]);
  assert.deepEqual(await query.all(), [{id: 1}]);
  assert.equal(f.count('submit-intent'), 1); assert.equal(f.count('wait'), 1);
  assert.equal(f.calls.find(call => call.operation === 'submit-intent').body.readOnly, true);
  assert.equal(f.count('read'), 2);
  const reads = f.calls.filter(x => x.operation === 'read');
  assert.notEqual(reads[0].body.attemptId, reads[1].body.attemptId);
  assert.equal(getSubmissionInput(first).requestId, query.requestId);
});

test('query invocation snapshots parameters and selection before async credentials', async t => {
  let release, notify;
  const paused = new Promise(resolve => {release = resolve;});
  const started = new Promise(resolve => {notify = resolve;});
  let tokens = 0;
  const f = await fixture(t, {wait: () => Response.json(succeeded(['original', 'other']))},
    async () => { if (++tokens === 2) {notify(); await paused;} return 'token'; });
  const params = {format: 'a parameter', signal: 'another', nested: {id: 1}};
  const options = {submissionRef: originalSubmission('saved'), result: 'original',
    parameterDeclarations: {id: {type: 'number'}}};
  const query = f.client.aql('SELECT 1 AS id |> RESULT original', params, options);
  await started;
  params.nested.id = 99; options.result = 'other';
  options.requestId = 'changed'; options.parameterDeclarations.id.type = 'string';
  release();
  const result = await query;
  assert.equal(query.requestId, 'saved'); assert.equal(result.ref.resultName, 'original');
  const submitted = f.calls.find(x => x.operation === 'submit-intent').body;
  assert.equal(submitted.input.format, 'aql-text');
  assert.equal(submitted.parameters.nested.id, 1);
  assert.equal(submitted.parameters.format, 'a parameter');
  assert.equal(submitted.input.parameterDeclarations.id.type, 'number');
});

test('startSource returns the admitted Execution without starting a wait or read', async t => {
  const f = await fixture(t);
  const execution = await f.client.startSource('{}', {format: 'json', submissionRef: originalSubmission('low')});
  assert.deepEqual(execution.ref, ref);
  assert.equal(f.count('wait'), 0); assert.equal(f.count('read'), 0);
  assert.deepEqual(await execution.result('answer').all(), [{id: 1}]);
});

test('submission uncertainty keeps its original input and never resubmits', async t => {
  const f = await fixture(t, {'submit-intent': () => {throw new Error('lost reply');}});
  const query = f.client.sql('SELECT 1 AS id', undefined, {submissionRef: originalSubmission('unknown')});
  let original;
  await assert.rejects(query, error => {
    original = error;
    assert.equal(error.code, 'SubmissionUnknown');
    assert.equal(error.execution, undefined);
    assert.equal(getSubmissionInput(error).requestId, 'unknown');
    assert.equal(explainSubmission(error).observation, 'acceptance_unknown');
    return true;
  });
  await assert.rejects(query.all(), error => error === original);
  await assert.rejects(query, error => error === original);
  assert.equal(f.count('submit-intent'), 1); assert.equal(f.count('wait'), 0);
});

test('a held query preserves the pre-Run observation without a fake Execution', async t => {
  const held = {kind: 'held', requestId: 'held', prepareAttemptId: 'prepare',
    state: 'waiting_checkpoint', durability: 'durable',
    lookupExpiresAt: '2026-10-08T00:00:00.000Z',
    checkpoint: {checkpointId: 'checkpoint', checkpointCid: cid('c'),
      kind: 'run_scope', expiresAt: '2026-10-08T00:00:00.000Z'}};
  const f = await fixture(t, {'submit-intent': body => Response.json(heldSubmissionAttempt(body, held))});
  const query = f.client.aql('SELECT 1 AS id', undefined, {submissionRef: originalSubmission('held')});
  let original;
  await assert.rejects(query, error => {
    original = error; assert.ok(error instanceof RequestHeld);
    assert.equal(error.execution, undefined); assert.equal(error.executionRef, undefined);
    assert.equal(getSubmissionInput(error).requestId, 'held'); return true;
  });
  await assert.rejects(query, error => error === original);
  assert.equal(f.count('submit-intent'), 1); assert.equal(f.count('wait'), 0);
});

for (const status of ['preparing', 'running', 'resuming', 'failed', 'cancelled',
  'waiting_checkpoint', 'needs_reconciliation']) {
  const unstable = ['preparing', 'running', 'resuming'].includes(status);
  test(unstable ? `short query refuses ${status} as an unstable wait reply`
    : `short query preserves ${status} and does not claim a Result`, async t => {
    const state = {...succeeded(), status, result_available: false,
      result_availability: {answer: {state: 'unavailable', observed_at: time,
        reason: 'not_published'}}, next_action: {kind: 'none'}};
    if (status === 'waiting_checkpoint') {
      state.checkpoint = {checkpoint_id: 'checkpoint', checkpoint_cid: cid('c'), kind: 'run_scope'};
      state.next_action = {kind: 'resolve_checkpoint', checkpoint_id: 'checkpoint'};
    }
    if (status === 'needs_reconciliation') state.next_action = {kind: 'reconcile', effects: ['write']};
    const f = await fixture(t, {wait: () => Response.json(state)});
    const query = f.client.sql('SELECT 1 AS id');
    let original;
    await assert.rejects(query, error => {
      original = error;
      assert.deepEqual(error.executionRef, ref);
      if (unstable) {
        // This is a valid status projection, but wait must return a stable
        // waiting or terminal projection. A malformed reply is not pending
        // execution evidence and cannot issue a Result or a retry.
        assert.equal(validRunState(state), true);
        assert.equal(validRunWaitContract(state, null), false);
        assert.equal(error.code, 'QueryObservationUnknown');
        assert.equal(error.cause?.code, 'InvalidHostRunState');
        assert.equal(error.observation, undefined);
      } else {
        assert.equal(error.observation.status, status);
        assert.equal(error.code, ['failed', 'cancelled'].includes(status)
          ? 'ExecutionUnsuccessful' : ['waiting_checkpoint', 'needs_reconciliation'].includes(status)
          ? 'ExecutionBlocked' : 'ExecutionPending');
      }
      assert.equal(JSON.stringify(error).includes('observation'), false);
      assert.equal(JSON.stringify(error).includes('result_availability'), false); return true;
    });
    await assert.rejects(query, error => error === original);
    assert.equal(f.count('submit-intent'), 1); assert.equal(f.count('wait'), 1);
    assert.equal(f.count('read'), 0);
  });
}

test('multiple Results require explicit selection and selecting one preserves the Run', async t => {
  const f = await fixture(t, {wait: () => Response.json(succeeded(['first', 'second']))});
  await assert.rejects(f.client.sql('SELECT 1 AS id'), {code: 'ResultSelectionRequired'});
  const selected = await f.client.sql('SELECT 1 AS id', undefined, {result: 'second'});
  assert.equal(selected.ref.resultName, 'second');
  assert.equal(f.count('read'), 0);
});

test('unknown Result availability keeps its original Execution', async t => {
  const state = succeeded(); state.result_available = false;
  state.next_action = {kind: 'refresh_availability', results: ['answer']};
  state.result_availability.answer = {state: 'unknown', observed_at: time,
    reason: 'verification_pending'};
  const f = await fixture(t, {wait: () => Response.json(state)});
  await assert.rejects(f.client.sql('SELECT 1 AS id'), error => {
    assert.equal(error.code, 'ResultUnavailable'); assert.deepEqual(error.execution.ref, ref); return true;
  });
  assert.equal(f.count('read'), 0);
});

test('a collection shortcut snapshots its limits before the query finishes', async t => {
  let release;
  const paused = new Promise(resolve => {release = resolve;});
  const f = await fixture(t, {wait: async () => {await paused; return Response.json(succeeded());},
    read: () => new Response('{"id":1}\n{"id":2}\n\x1e')});
  const query = f.client.sql('SELECT 1 AS id');
  const options = {maxRows: 1};
  const collection = query.all(options);
  options.maxRows = 100;
  release();
  await assert.rejects(collection, {code: 'ResultRetainedLimit', rowsYielded: 0});
  assert.equal(f.count('submit-intent'), 1); assert.equal(f.count('read'), 1);
});

test('collection shortcuts retain inherited and non-enumerable read ceilings', async t => {
  const f = await fixture(t, {read: () => new Response('{"id":1}\n{"id":2}\n\x1e')});
  const query = f.client.sql('SELECT 1 AS id');
  const inherited = Object.create({maxRows: 1});
  const hidden = Object.defineProperty({}, 'maxRows', {value: 1});
  await assert.rejects(query.all(inherited), {code: 'ResultRetainedLimit'});
  await assert.rejects(query.all(hidden), {code: 'ResultRetainedLimit'});
  assert.equal(f.count('submit-intent'), 1); assert.equal(f.count('read'), 2);
});

test('wait failure retains a real Execution without retry or private JSON causes', async t => {
  const f = await fixture(t, {wait: () => {throw new Error('private wait response');}});
  await assert.rejects(f.client.sql('SELECT 1 AS id'), error => {
    assert.equal(error.code, 'QueryObservationUnknown');
    assert.deepEqual(error.execution.ref, ref);
    assert.equal(error.observation, undefined);
    assert.doesNotMatch(JSON.stringify(error), /private wait|cause|capabilities/u);
    return true;
  });
  assert.equal(f.count('submit-intent'), 1); assert.equal(f.count('wait'), 1);
  assert.equal(f.count('read'), 0);
});

test('invalid short-query options refuse submission and do not guess legacy options', async t => {
  const f = await fixture(t);
  await assert.rejects(f.client.sql('SELECT 1', [], {}), {code: 'InvalidQueryParameters'});
  await assert.rejects(f.client.sql('SELECT 1', undefined, {format: 'json'}),
    {code: 'InvalidQueryOptions'});
  await assert.rejects(f.client.sql('SELECT 1', undefined, {result: ''}), {code: 'InvalidResultName'});
  assert.equal(f.count('submit-intent'), 0);
  // Names resembling options remain ordinary second-argument parameters.
  await f.client.sql('SELECT 1', {requestId: 'a value', result: 'a value'});
  const sent = f.calls.find(x => x.operation === 'submit-intent').body;
  assert.deepEqual(sent.parameters, {requestId: 'a value', result: 'a value'});
  assert.notEqual(sent.submissionRef.nonce, 'a value');
});

test('an ignored rejected query produces one ordinary unhandled rejection', () => {
  const module = new URL('./source-query.mjs', import.meta.url).href;
  const code = `import {sourceQuery} from ${JSON.stringify(module)};
    let observed = 0;
    process.on('unhandledRejection', () => {observed++;});
    sourceQuery(() => Promise.reject(new Error('lost')), Error, () => {}, () => {}, 'sql', 'SELECT 1');
    setTimeout(() => {if(observed !== 1) process.exitCode = 1;}, 30);`;
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', code],
    {encoding: 'utf8', timeout: 10000});
  assert.equal(child.status, 0, child.stderr);
});

test('short-query public types preserve Result and low-level Execution roles', async t => {
  const repository = fileURLToPath(new URL('../../', import.meta.url));
  // Exercise the same nested scratch layout as CI: without a consumer manifest,
  // npm walks up to this repository and replaces its workspace dependencies.
  const parent = join(repository, '_build');
  await mkdir(parent, {recursive: true});
  const scratch = await createOwnedScratch({parent,
    prefix: 'actql-short-query-types-', label: 'packed short-query public types'});
  const artifacts = join(scratch.path, 'artifacts');
  const application = join(scratch.path, 'application');
  await mkdir(artifacts);
  await mkdir(application);
  const environment = {...process.env, npm_config_cache: packedNpmCache(scratch.path)};
  delete environment.NODE_PATH;
  const rootIdentity = async () => ({
    manifest: await readFile(join(repository, 'package.json'), 'utf8'),
    lock: await readFile(join(repository, 'package-lock.json'), 'utf8'),
    packages: await Promise.all(CLIENT_PACKAGES.map(async name => {
      const path = join(repository, 'node_modules', '@actql', name);
      try {
        const state = await lstat(path);
        return {name, device: state.dev, inode: state.ino, mode: state.mode,
          target: state.isSymbolicLink() ? await readlink(path) : null};
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
        return {name, absent: true};
      }
    })),
  });
  const originalRoot = await rootIdentity();
  t.after(async () => assert.deepEqual(await rootIdentity(), originalRoot,
    'the private consumer must not mutate repository manifests or workspace installations'));
  const run = (command, args, cwd, timeout = 30000) => {
    const result = spawnSync(command, args, {cwd, env: environment,
      encoding: 'utf8', timeout, maxBuffer: 16 * 1024 * 1024});
    assert.equal(result.error, undefined, result.error?.message);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    return result.stdout;
  };
  assert.equal(await realpath(run('npm', ['prefix'], application).trim()),
    await realpath(repository), 'the absent manifest reproduces ancestor selection without installing');
  await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n');
  assert.equal(await realpath(run('npm', ['prefix'], application).trim()),
    await realpath(application), 'the explicit consumer owns npm installation');
  for (const name of CLIENT_PACKAGES) {
    await packedClientPackage({repository, name, destination: artifacts,
      pack: () => run('npm', ['pack', '--json', '--pack-destination', artifacts],
        join(repository, 'packages', name), 180000)});
  }
  run('npm', ['install', '--offline', '--ignore-scripts', '--no-audit',
    '--no-fund', '--no-save', ...CLIENT_PACKAGES.map(name =>
      join(artifacts, `actql-${name}-0.0.0-development.tgz`))], application);
  const fixture = join(application, 'source-query.typecheck.mts');
  await copyFile(new URL('./source-query.typecheck.mts', import.meta.url), fixture);
  const result = spawnSync(process.execPath, [
    fileURLToPath(new URL('../../node_modules/typescript/bin/tsc', import.meta.url)),
    '--strict', '--target', 'ES2022', '--module', 'NodeNext',
    '--moduleResolution', 'NodeNext', '--noEmit',
    fixture,
  ], {cwd: application, env: environment, encoding: 'utf8', timeout: 30000});
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  scratch.passed();
});

test('a throwing query-option accessor rejects without transport or reevaluation', async t => {
  const f = await fixture(t);
  let calls = 0;
  const query = f.client.sql('SELECT 1', undefined, {get requestId() {
    calls++; throw new Error('caller option failure');
  }});
  assert.ok(query instanceof Promise);
  await assert.rejects(query, {message: 'caller option failure'});
  assert.equal(calls, 1); assert.equal(f.count('submit-intent'), 0);
});

for (const [method, kind] of [['all', 'schema'], ['all', 'options'],
  ['one', 'options'], ['scalar', 'options']]) {
  test(`${method}: ${kind} capture cannot orphan a rejected eager submission`, () => {
    const module = new URL('./source-query.mjs', import.meta.url).href;
    const code = `import assert from 'node:assert/strict';
      import {sourceQuery} from ${JSON.stringify(module)};
      let observed = 0, captured = 0;
      process.on('unhandledRejection', () => {observed++;});
      for (const code of ['SubmissionUnknown', 'RequestHeld']) {
        const original = Object.assign(new Error(code), {code});
        let reject;
        const admission = new Promise((_resolve, no) => {reject = no;});
        const query = sourceQuery(() => admission, Error, () => {}, () => {}, 'sql', 'SELECT 1');
        const argument = ${JSON.stringify(kind)} === 'schema'
          ? {'~standard': {version: 2, vendor: 'test', validate() {}}}
          : {get maxRows() {captured++; throw new Error('capture failure');}};
        const collected = query[${JSON.stringify(method)}](argument);
        assert.ok(collected instanceof Promise);
        reject(original);
        await assert.rejects(collected, error => error === original);
      }
      assert.equal(captured, ${kind === 'options' ? 2 : 0});
      setTimeout(() => {assert.equal(observed, 0);}, 30);`;
    const child = spawnSync(process.execPath, ['--input-type=module', '-e', code],
      {encoding: 'utf8', timeout: 10000});
    assert.equal(child.status, 0, `${child.stdout}\n${child.stderr}`);
  });
}

test('collection argument failures reject after query success without reading', async t => {
  const f = await fixture(t), query = f.client.sql('SELECT 1 AS id');
  const argumentFailure = new Error('read option getter');
  let accessed = 0;
  const options = {get maxRows() {accessed++; throw argumentFailure;}};
  const all = query.all(options), one = query.one(options), scalar = query.scalar(options);
  assert.equal(accessed, 3, 'Arguments are captured before any query wait');
  await assert.rejects(all, error => error === argumentFailure);
  await assert.rejects(one, error => error === argumentFailure);
  await assert.rejects(scalar, error => error === argumentFailure);
  await assert.rejects(query.all({'~standard': {}}), {code: 'InvalidResultSchema'});
  const result = await query;
  assert.deepEqual(result.ref.run, ref);
  assert.equal(f.count('submit-intent'), 1); assert.equal(f.count('read'), 0);
});

test('short query and collection retain the exact original before a lost reply', async t => {
  const f = await fixture(t, {'submit-intent': () => {throw new Error('lost reply');}});
  const original = f.client.newSubmission({nonce: 'saved-exact-query'});
  const parameters = {nested: ['e\u0301', 'é', '\r', '\n', '\r\n']};
  const text = "SELECT 'e\u0301\r\n' AS value";
  const query = f.client.aql(text, parameters, {submissionRef: original});
  const collected = query.all();
  const saved = getSubmissionInput(query);
  assert.deepEqual(saved.submissionRef, original);
  assert.equal(saved.input.text, text);
  assert.equal(getSubmissionInput(collected), saved);
  parameters.nested[0] = 'changed after call';
  let failure;
  await assert.rejects(query, error => {
    failure = error;
    assert.equal(error.code, 'SubmissionUnknown');
    assert.equal(getSubmissionInput(error), saved);
    assert.deepEqual(saved.parameters.nested, ['e\u0301', 'é', '\r', '\n', '\r\n']);
    return true;
  });
  await assert.rejects(collected, error => error === failure);
  assert.equal(f.count('submit-intent'), 1);
  assert.equal(f.count('wait'), 0);
  assert.equal(f.count('read'), 0);
});

test('query observation loss retains the actual accepted submission outcome', async t => {
  const f = await fixture(t, {wait: () => {throw new Error('wait reply lost');}});
  const original = f.client.newSubmission({nonce: 'accepted-observation-loss'});
  const query = f.client.sql('SELECT 1', undefined, {submissionRef: original});
  const saved = getSubmissionInput(query);
  await assert.rejects(query, error => {
    assert.equal(error.code, 'QueryObservationUnknown');
    assert.equal(getSubmissionInput(error), saved);
    assert.equal(getSubmissionOutcome(error).kind, 'ready');
    assert.deepEqual(getSubmissionOutcome(error).submissionRef, original);
    assert.deepEqual(getSubmissionOutcome(error).admission.ref, ref);
    return true;
  });
  assert.equal(f.count('submit-intent'), 1);
  assert.equal(f.count('wait'), 1);
  assert.equal(f.count('read'), 0);
});

test('public aql spelling reaches submit without rewriting its source', async t => {
  const f=await fixture(t);
  const execution=await f.client.startSource('SELECT @id AS id', {
    format:'aql', parameters:{id:1}, parameterDeclarations:{id:{type:'number',nullable:false}},
  });
  assert.ok(execution);
  const sent=f.calls.find(x=>x.operation==='submit-intent').body;
  assert.equal(sent.input.format,'aql');
  assert.equal(sent.input.text,'SELECT @id AS id');
  assert.deepEqual(sent.input.parameterDeclarations,{id:{type:'number',nullable:false}});
  assert.deepEqual(sent.parameters,{id:1});
  assert.equal(f.count('submit-intent'),1);
});
