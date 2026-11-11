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
import {parse} from 'acorn';

const scope = `sha256:${'1'.repeat(64)}`;
const facts = {principalId: 'person', resultName: 'main',
  indexKey: {namespaceId: 'local', authorityScopeCid: scope,
    runDefinitionCid: `sha256:${'2'.repeat(64)}`}};

test('installed Host forwards the same observation projection into its read authorization factory', async () => {
  const source = fs.readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const calls = [];
  function visit(node) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.name === 'createLocalReadAuthorizations') calls.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  }
  visit(parse(source, {sourceType: 'module', ecmaVersion: 'latest'}));
  assert.equal(calls.length, 1);
  const call = new Function('createLocalReadAuthorizations', 'moon', 'authorization',
    'principalId', 'namespaceId', 'authorityScopeCid', 'observation',
    `return ${source.slice(calls[0].start, calls[0].end)};`);
  const observation = installHostObservation(createHostObservationConnection({deliver() {}}));
  try {
    const moon = {}, authorization = {};
    let captured;
    const result = Object.freeze({});
    assert.equal(call(options => {captured = options; return result;}, moon, authorization,
      facts.principalId, facts.indexKey.namespaceId, scope, observation), result);
    assert.deepEqual(captured, {moon, authorization, principalId: facts.principalId,
      namespaceId: facts.indexKey.namespaceId, authorityScopeCid: scope, observation});
    assert.equal(captured.observation, observation);
  } finally {await observation.close();}
});

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

test('an asynchronous observation callback cannot retain Allow across its later Account mutation', async t => {
  let account, enter, mutate, changed, finish;
  const entered = new Promise(resolve => {enter = resolve;});
  const mutation = new Promise(resolve => {mutate = resolve;});
  const mutated = new Promise(resolve => {changed = resolve;});
  const finished = new Promise(resolve => {finish = resolve;});
  const observation = installHostObservation(createHostObservationConnection({
    include: ['run'], correlation: false, measurements: {include: ['duration']},
    async deliver(record) {
      if (record.event !== 'segment_started') return;
      enter();
      await mutation;
      await account.change('deny');
      changed();
      await finished;
    },
  }));
  try {
    account = await fixture(t, {}, facts, observation);
    const operation = Object.freeze({...facts, indexKey: Object.freeze({...facts.indexKey})});
    await observation.run('result', undefined, async () => {
      assert.equal(await account.authorize(facts, operation), true);
      await entered;
      assert.equal(observation.applicationCallbackState().active, true);
      assert.equal(await account.authorize(facts, operation), true);
      assert.equal(account.evaluations(), 1, 'unchanged Account is not evaluated again');
      mutate();
      await mutated;
      assert.equal(await account.authorize(facts, operation), false,
        'the still-running callback can change policy after an earlier current observation');
      assert.equal(account.evaluations(), 2);
      finish();
    });
  } finally {mutate(); finish(); await observation.close();}
});

test('completed observation callbacks retain one Account evaluation and pure stages perform no extra read', async t => {
  let delivered;
  const delivery = new Promise(resolve => {delivered = resolve;});
  const observation = installHostObservation(createHostObservationConnection({
    include: ['run'], correlation: false, measurements: {include: ['duration']},
    deliver: () => {delivered();},
  }));
  const account = await fixture(t, {}, facts, observation);
  const original = fs.openSync;
  let reads = 0;
  fs.openSync = function(path, ...args) {
    if (path === account.accountConfig) reads++;
    return Reflect.apply(original, this, [path, ...args]);
  };
  syncBuiltinESMExports();
  try {
    const operation = Object.freeze({...facts, indexKey: Object.freeze({...facts.indexKey})});
    await observation.run('result', undefined, async () => {
      const originalState = observation.applicationCallbackState();
      assert.equal(await account.authorize(facts, operation), true);
      for (let n = 0; n < 3; n++) {
        await Promise.resolve();
        assert.equal(observation.applicationCallbackState(), originalState);
        assert.equal(await account.authorize(facts, operation), true);
      }
      assert.equal(reads, 1, 'pure helpers and awaits are not callback boundaries');
      await delivery;
      await new Promise(resolve => setImmediate(resolve));
      const settled = observation.applicationCallbackState();
      assert.equal(settled.active, false);
      assert.notEqual(settled, originalState);
      assert(Object.isFrozen(settled));
      for (let n = 0; n < 6; n++) assert.equal(await account.authorize(facts, operation), true);
      assert.equal(reads, 2, 'one current observation after the actual completed callback');
      assert.equal(account.admissions(), 1);
      assert.equal(account.evaluations(), 1);
    });
  } finally {
    fs.openSync = original; syncBuiltinESMExports();
    await observation.close();
  }
});

test('a synchronous observation context callback invalidates another active Result observation', async t => {
  let account, mutate = false;
  const observation = installHostObservation(createHostObservationConnection({
    include: ['run'], deliver() {},
    currentContext() {
      if (mutate) fs.writeFileSync(account.accountConfig,
        sourceReadAccountConfiguration({connection: 'local-mock', resource: 'result/main', outcome: 'deny'}));
    },
  }));
  try {
    account = await fixture(t, {}, facts, observation);
    const operation = Object.freeze({...facts, indexKey: Object.freeze({...facts.indexKey})});
    assert.equal(await account.authorize(facts, operation), true);
    mutate = true;
    await observation.run('result', undefined, async () => {
      assert.equal(await account.authorize(facts, operation), false);
    });
    assert.equal(account.evaluations(), 2);
  } finally {await observation.close();}
});

test('a copied observation projection cannot supply Result currentness', async t => {
  const observation = installHostObservation(createHostObservationConnection({deliver() {}}));
  try {
    await assert.rejects(fixture(t, {}, facts, Object.freeze({...observation})),
      {message: 'ForeignHostObservationProjection'});
  } finally {await observation.close();}
});

const deliverySubject = {principalId: 'principal', resultName: 'answer', purpose: 'download',
  indexKey: {namespaceId: 'namespace', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${'9'.repeat(64)}`}};

test('actual observation delivery Deny stops Result output without refunding the original claim', async t => {
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
    account = await fixture(t, {}, deliverySubject, observation);
    const result = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
      rows: ['{"value":7}', '{"value":8}'], authorize: account.authorize,
      async beforeAppend(record) {
        if (JSON.parse(record.wire).state === 'streaming') await delivery;
      },
    });
    await assert.rejects(observation.run('result', undefined, () => result.deliver()),
      {code: 'ResultDeliveryDenied'});
    assert.equal(result.state.grantUses, 1, 'Deny cannot refund the actual prior claim');
    assert.deepEqual(result.state.chunks, [], 'no Result bytes dispatched after observation callback Deny');
    assert.equal(result.state.finishes, 0);
    assert.equal(result.state.records.some(wire => JSON.parse(wire).state === 'succeeded'), false);
    assert.equal(account.evaluations(), 2, 'only original Allow and changed Deny');
  } finally {await observation.close();}
});

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

test('Delivery lookup consumes a changed Account observed by another public operation', async t => {
  const account = await fixture(t, {}, deliverySubject);
  let enter, release, paused = false, lookups = 0;
  const entered = new Promise(resolve => {enter = resolve;});
  const gate = new Promise(resolve => {release = resolve;});
  const delivery = createResultDeliveryFixture(resultAccess, openResultDeliveryControl(), {
    authorize: account.authorize,
    async lookup(found) {
      lookups++;
      if (paused) {enter(); await gate;}
      return found;
    },
  });
  await delivery.deliver();
  const input = {...deliverySubject, attemptId: 'same-logical-attempt'};
  const before = account.evaluations();
  assert.equal((await resultAccess.inspectAuthorizedDeliveryAttempt(delivery.service, input)).kind, 'found');
  assert.equal(account.admissions(), 1);
  assert.equal(account.evaluations(), before + 1,
    'unchanged same-operation checks retain one heavy Account evaluation');
  const beforePending = account.evaluations();
  paused = true;
  const pending = resultAccess.inspectAuthorizedDeliveryAttempt(delivery.service, input);
  try {
    await entered;
    assert.equal(account.evaluations(), beforePending + 1);
    await account.change('deny');
    // A distinct real public lookup observes current Deny before Store I/O.
    await assert.rejects(resultAccess.inspectAuthorizedDeliveryAttempt(delivery.service, input),
      {code: 'ResultAccessDenied'});
    assert.equal(lookups, 2);
    release();
    await assert.rejects(pending, {code: 'ResultAccessDenied'});
    assert.equal(account.admissions(), 2, 'only original Allow and changed Account are admitted');
    assert.equal(account.evaluations(), beforePending + 3,
      'only the changed policy is re-evaluated for each affected public operation');
    assert.equal(lookups, 2);
    assert.equal(delivery.state.grantUses, 1, 'lookup refusal does not refund or issue a delivery claim');
  } finally {release(); await pending.catch(() => {});}
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
