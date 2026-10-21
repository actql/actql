import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
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
