import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {mkdtemp, writeFile, rm, readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {heldValuesProgram, writeSyntheticHistoricalHeldValues} from '../../scripts/fixtures/synthetic-historical-held-values.mjs';
import {createLocalReadAuthorizations} from './local-result-authorization.mjs';
import {sourceReadAccountConfiguration} from './local-account-config.mjs';
import {loadExecutionAuthorizationRuntime} from './authorization.mjs';

// Execute the actual installed Host's public-entry function, not a duplicate
// route implementation or a full embedded/Common Host qualification.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declarations = [];
function visit(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclarator') declarations.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value !== null && typeof value === 'object') visit(value);
  }
}
visit(ast);
const host = declarations.filter(node => node.id.name === 'hostOperations');
assert.equal(host.length, 1);
const entry = host[0].init.properties.find(node => node.key?.name === 'authorizeConnection').value;
const selection = declarations.find(node => node.id.name === 'runReadOperations');
function entrance(authorizeLocalRun) {
  return new Function('checkpointOperation', 'checkpointConnection', 'hostConnection',
    'authorizeLocalRun', 'namespaceId', 'authorityScopeCid',
    `${selection === undefined ? '' : 'const runReadOperations = ' + source.slice(selection.init.start, selection.init.end) + ';'}
      return (${source.slice(entry.start, entry.end)});`)(new Set(['checkpoints']), () => true,
    value => value.principalId === 'person' && value.connection?.owner === 'local',
    authorizeLocalRun, 'local', 'sha256:' + '1'.repeat(64));
}
const facts = {principalId: 'person', connection: {mode: 'local', owner: 'local'},
  ref: {namespaceId: 'local', authorityScopeCid: 'sha256:' + '1'.repeat(64),
    runDefinitionCid: 'sha256:' + '2'.repeat(64)}};

// Execute only this original fixture adapter with explicit issuer/Journal
// ports. This is not a real Common, durable Journal or ordinary Host test.
test('cancel fixture publishes its state through the same original Journal frame', () => {
  const text = readFileSync(new URL('./client-cancel-response-loss.fixture.mjs', import.meta.url), 'utf8');
  const properties = [];
  const scan = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'observeRun') properties.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(scan);
      else if (value !== null && typeof value === 'object') scan(value);
    }
  };
  scan(parse(text, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(properties.length, 1);
  const fn = properties[0].value;
  const original = {runDefinition: {}, resultNames: ['answer'], revision: 12,
    dispatchReserved: true, preDispatchFailureConfirmed: false,
    cancellationRequested: false, physicalStartReserved: true, physicalCloseConfirmed: false};
  const moon = {}, control = {runDefinitionRunId(value) { assert.equal(value, original.runDefinition); return 'original'; }};
  const state = Object.freeze({run_id: 'original', status: 'running', result_availability: {}});
  const cancellation = Object.freeze({revision: 12, cancellation_requested: false, physical_stop: 'unknown'});
  const failure = new Error('Original Journal publication failure');
  let publishes = 0, reject = false;
  const journal = {
    lookupRunDefinition(ref, requestControl, publicationControl) {
      assert.equal(ref, facts.ref); assert.equal(requestControl, moon); assert.equal(publicationControl, control);
      return original;
    },
    publishRunState(frame, observed, requestControl, publicationControl) {
      publishes++;
      assert.equal(frame, original); assert.equal(requestControl, moon); assert.equal(publicationControl, control);
      assert.equal(Object.hasOwn(observed, 'control'), false, 'The Journal owns the same original control projection');
      assert.equal(observed.result_availability, state.result_availability);
      assert.equal(Object.hasOwn(observed, 'revision'), false, 'The Journal alone issues the observation revision');
      if (reject) throw failure;
      return JSON.stringify({...observed, control: cancellation, revision: 19});
    },
  };
  const observe = new Function('assert', 'journal', 'moon', 'publicationControl',
    'issueInstalledUnpublishedRunState', 'issueInstalledRunControlObservation',
    'return function ' + text.slice(fn.start, fn.end))(assert, journal, moon, control, () => state,
    () => assert.fail('The fixture must not repeat the Journal control issuer'));
  const actual = observe({ref: facts.ref});
  assert.equal(publishes, 1); assert.equal(actual.revision, 19);
  assert.deepEqual(actual.control, cancellation); assert.equal(Object.isFrozen(actual), true);
  reject = true;
  assert.throws(() => observe({ref: facts.ref}), error => error === failure);
  assert.equal(publishes, 2);
});

test('historical fixture rejects missing duplicate or nondelegating run entries before state I/O', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-held-delegate-',
    label: 'Historical write-delegate selection controls'});
  const read = {entry_id: 'read-original', outcome: 'allow'};
  const delegate = {entry_id: 'run-acceptance', outcome: 'delegate'};
  for (const entries of [[read], [read, delegate, delegate],
    [read, {...delegate, outcome: 'allow'}]]) {
    await assert.rejects(writeSyntheticHistoricalHeldValues({directory: join(scratch.path, 'unstarted-state'),
      document: JSON.stringify(heldValuesProgram), requestId: 'unaccepted-fixture-request',
      runtimeRootUrl: new URL('../../', import.meta.url),
      expressionContractUrl: pathToFileURL(join(scratch.path, 'unprovided-contract.json')),
      authorization: {accountConfiguration: JSON.stringify({account_id: 'authored-fixture', entries})}}),
    {code: 'ERR_ASSERTION'});
  }
  assert.deepEqual(await readdir(scratch.path), []);
  await scratch.passed();
});

test('public Run observation entry requires its actual Account read exactly once', async () => {
  let calls = 0;
  const authorize = entrance(async value => {
    calls++;
    assert.equal(value.principalId, facts.principalId);
    assert.deepEqual(value.indexKey, facts.ref);
    return false;
  });
  for (const operation of ['status', 'wait', 'attach', 'run-plan', 'inspect-run',
    'owner-observations', 'lookup-request', 'lookup-submission']) {
    const before = calls;
    assert.equal(await authorize({...facts, operation}), false);
    assert.equal(calls - before, 1);
  }
});

test('public named Result and pure check entries do not substitute a Run-read permission', async () => {
  const authorize = entrance(() => assert.fail('a distinct permission owns this operation'));
  for (const operation of ['result-describe', 'read', 'delivery-attempt', 'check', 'plan', 'connect']) {
    assert.equal(await authorize({...facts, operation}), true);
  }
  assert.equal(await authorize({...facts, operation: 'status', principalId: 'foreign'}), false);
});

test('actual Account keeps Run-read and named-Result-read distinct and current', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-run-account-'));
  t.after(() => rm(directory, {recursive: true}));
  const accountConfig = join(directory, 'account.json');
  const configuration = (run, result) => {
    const value = JSON.parse(sourceReadAccountConfiguration({connection: 'local-mock',
      resource: 'run', entryId: 'run-read', outcome: run}));
    value.entries.push(JSON.parse(sourceReadAccountConfiguration({connection: 'local-mock',
      resource: 'result/main', entryId: 'result-read', outcome: result})).entries[0]);
    value.entries.sort((left, right) => left.entry_id < right.entry_id ? -1
      : left.entry_id > right.entry_id ? 1 : 0);
    return JSON.stringify(value);
  };
  await writeFile(accountConfig, configuration('allow', 'deny'), {mode: 0o600});
  const runtime = await loadExecutionAuthorizationRuntime();
  const initial = JSON.parse(runtime.executionAuthorizationAccountJson(
    runtime.executionAuthorizationAdmit(configuration('allow', 'deny'))));
  assert.equal(initial.state, 'admitted', JSON.stringify(initial));
  let evaluations = 0;
  const moon = {...runtime, executionAuthorizationEvaluate(...args) {
    evaluations++;
    return runtime.executionAuthorizationEvaluate(...args);
  }};
  const authority = createLocalReadAuthorizations({moon,
    authorization: {accountConfig, siteKey: 'local-mock'}, principalId: 'person',
    namespaceId: facts.ref.namespaceId, authorityScopeCid: facts.ref.authorityScopeCid});
  const request = {principalId: facts.principalId, indexKey: facts.ref, purpose: 'inspect'};
  assert.equal(await authority.run(request), true);
  assert.equal(evaluations, 1);
  assert.equal(await authority.result({...request, resultName: 'main'}), false);
  assert.equal(evaluations, 2);
  await writeFile(accountConfig, configuration('deny', 'allow'));
  assert.equal(await authority.run(request), false);
  const resultRequest = Object.freeze({...request, resultName: 'main'});
  assert.equal(await authority.result(resultRequest, resultRequest), true);
  const before = evaluations;
  await authority.result(resultRequest, resultRequest);
  assert.equal(evaluations, before, 'unchanged internal consumption evaluates nothing again');
  await writeFile(accountConfig, configuration('deny', 'deny'));
  assert.equal(await authority.run(request), false);
  assert.equal(await authority.result(resultRequest, resultRequest), false,
    'the same Account owner already observed this policy change');
  assert.equal(await authority.run({...request, principalId: 'foreign'}), false);
  assert.equal(await authority.run({...request, indexKey: {...facts.ref, namespaceId: 'foreign'}}), false);
});
