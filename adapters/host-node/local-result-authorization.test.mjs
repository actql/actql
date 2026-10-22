import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm, unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createLocalResultAuthorization} from './local-result-authorization.mjs';
import {sourceReadAccountConfiguration} from './local-account-config.mjs';
import {loadExecutionAuthorizationRuntime} from './authorization.mjs';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import * as resultAccess from '../host-common/result-access.mjs';
import {createResultDeliveryFixture} from '../../scripts/fixtures/result-delivery-acceptance.mjs';
import {openResultDeliveryControl} from '../../packages/run-host-core/index.mjs';
import {createHostObservationConnection, installHostObservation} from '../host-common/observation.mjs';

const scope = `sha256:${'1'.repeat(64)}`;
const facts = {principalId: 'person', resultName: 'main',
  indexKey: {namespaceId: 'local', authorityScopeCid: scope,
    runDefinitionCid: `sha256:${'2'.repeat(64)}`}};

async function fixture(t, options = {}, subject = facts, observation) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-result-account-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const accountConfig = join(directory, 'account.json');
  const configuration = outcome => sourceReadAccountConfiguration({
    connection: 'local-mock', resource: `result/${subject.resultName}`, outcome});
  await writeFile(accountConfig, configuration('allow'));
  const runtime = await loadExecutionAuthorizationRuntime();
  let admissions = 0, evaluations = 0;
  const moon = {...runtime, executionAuthorizationAdmit(wire) {
    admissions++;
    return runtime.executionAuthorizationAdmit(wire);
  }, executionAuthorizationEvaluate(...args) {
    evaluations++;
    return runtime.executionAuthorizationEvaluate(...args);
  }};
  const authorization = {accountConfig, siteKey: 'local-mock', ...options};
  const authorize = createLocalResultAuthorization({moon, authorization, observation,
    principalId: subject.principalId, namespaceId: subject.indexKey.namespaceId,
    authorityScopeCid: subject.indexKey.authorityScopeCid});
  return {authorize, accountConfig, admissions: () => admissions, evaluations: () => evaluations,
    change: outcome => writeFile(accountConfig, configuration(outcome)),
    foreign: () => writeFile(accountConfig, JSON.stringify({
      ...JSON.parse(configuration('allow')), account_id: 'different-account'})),
    remove: () => unlink(accountConfig),
    corrupt: () => writeFile(accountConfig, '{invalid')};
}

test('Local Result reads evaluate the actual current Account without repeated admission', async t => {
  const f = await fixture(t);
  for (let n = 0; n < 6; n++) assert.equal(await f.authorize(facts), true);
  assert.equal(f.admissions(), 1);
  await f.change('deny');
  assert.equal(await f.authorize(facts), false);
  assert.equal(f.admissions(), 2);
  await f.change('allow');
  assert.equal(await f.authorize(facts), true);
  assert.equal(f.admissions(), 3);
  await f.remove();
  assert.equal(await f.authorize(facts), false);
  await f.corrupt();
  assert.equal(await f.authorize(facts), false);
});

test('one public Result operation observes and evaluates its Account tuple once', async t => {
  const f = await fixture(t);
  const original = fs.openSync;
  let reads = 0;
  fs.openSync = function(path, ...args) {
    if (path === f.accountConfig) reads++;
    return Reflect.apply(original, this, [path, ...args]);
  };
  syncBuiltinESMExports();
  try {
    const operation = Object.freeze({...facts, indexKey: Object.freeze({...facts.indexKey})});
    for (let n = 0; n < 6; n++) assert.equal(await f.authorize(facts, operation), true);
    assert.equal(reads, 1);
    assert.equal(f.evaluations(), 1);
    const next = Object.freeze({...facts, indexKey: Object.freeze({...facts.indexKey})});
    assert.equal(await f.authorize(facts, next), true);
    assert.equal(reads, 2);
    assert.equal(f.evaluations(), 2, 'no persistent Allow or evaluation cache across public operations');
    await f.change('deny');
    assert.equal(await f.authorize(facts, Object.freeze({...facts})), false);
    assert.equal(reads, 3);
    assert.equal(f.evaluations(), 3);
  } finally {fs.openSync = original; syncBuiltinESMExports();}
});

test('Local Result Account does not substitute another principal scope or name', async t => {
  const f = await fixture(t);
  for (const wrong of [{...facts, principalId: 'other'},
    {...facts, resultName: 'answer'},
    {...facts, indexKey: {...facts.indexKey, authorityScopeCid: `sha256:${'3'.repeat(64)}`}},
    {...facts, indexKey: {...facts.indexKey, namespaceId: 'other'}}]) {
    assert.equal(await f.authorize(wrong), false);
  }
});

test('a Result sink callback observes changed Deny without repeating an unchanged Account evaluation', async t => {
  const f = await fixture(t);
  const operation = Object.freeze({...facts, indexKey: Object.freeze({...facts.indexKey})});
  const atCallback = sinkCallbackCount => ({...facts, delivery: {sinkCallbackCount}});
  assert.equal(await f.authorize(atCallback(0), operation), true);
  for (let n = 1; n < 4; n++) assert.equal(await f.authorize(atCallback(n), operation), true);
  assert.equal(f.admissions(), 1);
  assert.equal(f.evaluations(), 1, 'unchanged original Account retains its one evaluation');
  await f.change('deny');
  assert.equal(await f.authorize(atCallback(4), operation), false,
    'an application sink callback can change Account before the next dispatch');
  assert.equal(f.admissions(), 2);
  assert.equal(f.evaluations(), 2);
  assert.equal(await f.authorize(atCallback(4), operation), false);
  assert.equal(f.evaluations(), 2);
});

test('an observation delivery callback invalidates the same Result operation Account observation', async t => {
  let account, delivered;
  const delivery = new Promise(resolve => {delivered = resolve;});
  const observation = installHostObservation(createHostObservationConnection({
    include: ['run'], correlation: false, measurements: {include: ['duration']},
    async deliver(record) {
      if (record.event !== 'segment_started') return;
      await account.change('deny');
      delivered();
    },
  }));
  try {
    account = await fixture(t, {}, facts, observation);
    const operation = Object.freeze({...facts, indexKey: Object.freeze({...facts.indexKey})});
    await observation.run('result', undefined, async () => {
      assert.equal(await account.authorize(facts, operation), true);
      await delivery;
      assert.equal(await account.authorize(facts, operation), false,
        'application observation delivery can change Account before the next protected dispatch');
    });
    assert.equal(account.admissions(), 2);
    assert.equal(account.evaluations(), 2);
  } finally {await observation.close();}
});

const deliverySubject = {principalId: 'principal', resultName: 'answer', purpose: 'download',
  indexKey: {namespaceId: 'namespace', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${'9'.repeat(64)}`}};

for (const boundary of ['write', 'finish']) {
  test(`actual Result ${boundary} callback Deny stops the next dispatch or success`, async t => {
    const account = await fixture(t, {}, deliverySubject);
    let callbacks = 0;
    const delivery = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
      rows: ['{"value":7}', '{"value":8}'], authorize: account.authorize,
      [boundary === 'write' ? 'afterWrite' : 'afterFinish']: async () => {
        if (++callbacks === 1) await account.change('deny');
      },
    });
    await assert.rejects(delivery.deliver(), {code: 'ResultDeliveryDenied'});
    assert.equal(delivery.state.grantUses, 1, 'a refusal does not refund the original claim');
    assert.equal(delivery.state.records.some(wire => JSON.parse(wire).state === 'succeeded'), false);
    assert.equal(callbacks, 1);
    if (boundary === 'write') {
      assert.equal(delivery.state.chunks.length, 1, 'no second byte dispatch after callback Deny');
      assert.equal(delivery.state.finishes, 0);
    } else {assert.equal(delivery.state.finishes, 1);}
    assert.equal(account.evaluations(), 2, 'one original Allow and one actually changed Deny');
  });
}

test('actual Result callbacks retain one heavy evaluation for unchanged Account and separate the next operation', async t => {
  const account = await fixture(t, {}, deliverySubject);
  const delivery = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
    rows: ['{"value":7}', '{"value":8}'], authorize: account.authorize,
  });
  await delivery.deliver();
  assert.equal(account.admissions(), 1);
  assert.equal(account.evaluations(), 1);
  assert(delivery.state.chunks.length > 1, 'exercise more than one sink dispatch');
  await account.change('deny');
  await assert.rejects(delivery.deliver(), {code: 'ResultAccessDenied'});
  assert.equal(account.admissions(), 2);
  assert.equal(account.evaluations(), 2);
  assert.equal(delivery.state.grantUses, 1);
});

test('Local Result cannot replace its installed Account with another valid Account', async t => {
  const f = await fixture(t);
  assert.equal(await f.authorize(facts), true);
  await f.foreign();
  assert.equal(await f.authorize(facts), false);
});

test('a retained Result decision invalidates after the same owner observes a policy change', async t => {
  const f = await fixture(t);
  const operation = Object.freeze({...facts});
  assert.equal(await f.authorize(facts, operation), true);
  await f.change('deny');
  assert.equal(await f.authorize(facts, Object.freeze({...facts})), false);
  assert.equal(await f.authorize(facts, operation), false,
    'an already observed policy revision is not unchanged operation state');
});

test('Local Result Delegate needs the existing immediate configured answer', async t => {
  const f = await fixture(t);
  await f.change('delegate');
  assert.equal(await f.authorize(facts), false);
  const configured = await fixture(t, {answeringAuthorities: ['reviewer'],
    decide: view => ({decision: 'permit', subject: view.subject,
      authority: 'reviewer', claims: []})});
  await configured.change('delegate');
  assert.equal(await configured.authorize(facts), true);
});

test('Local Result Delegate rechecks the Account after an asynchronous answer', async t => {
  let f;
  f = await fixture(t, {answeringAuthorities: ['reviewer'], decide: async view => {
    await f.change('deny');
    return {decision: 'permit', subject: view.subject, authority: 'reviewer', claims: []};
  }});
  await f.change('delegate');
  await assert.rejects(f.authorize(facts), {code: 'AuthorizationCurrentAccountChanged'});
});
