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

const scope = `sha256:${'1'.repeat(64)}`;
const facts = {principalId: 'person', resultName: 'main',
  indexKey: {namespaceId: 'local', authorityScopeCid: scope,
    runDefinitionCid: `sha256:${'2'.repeat(64)}`}};

async function fixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-result-account-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const accountConfig = join(directory, 'account.json');
  const configuration = outcome => sourceReadAccountConfiguration({
    connection: 'local-mock', resource: 'result/main', outcome});
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
  const authorize = createLocalResultAuthorization({moon, authorization,
    principalId: 'person', namespaceId: 'local', authorityScopeCid: scope});
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

test('Local Result cannot replace its installed Account with another valid Account', async t => {
  const f = await fixture(t);
  assert.equal(await f.authorize(facts), true);
  await f.foreign();
  assert.equal(await f.authorize(facts), false);
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
