import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm, unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createLocalResultAuthorization} from './local-result-authorization.mjs';
import {sourceReadAccountConfiguration} from './local-account-config.mjs';
import {loadExecutionAuthorizationRuntime} from './authorization.mjs';

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
  let admissions = 0;
  const moon = {...runtime, executionAuthorizationAdmit(wire) {
    admissions++;
    return runtime.executionAuthorizationAdmit(wire);
  }};
  const authorization = {accountConfig, siteKey: 'local-mock', ...options};
  const authorize = createLocalResultAuthorization({moon, authorization,
    principalId: 'person', namespaceId: 'local', authorityScopeCid: scope});
  return {authorize, admissions: () => admissions,
    change: outcome => writeFile(accountConfig, configuration(outcome)),
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

test('Local Result Account does not substitute another principal scope or name', async t => {
  const f = await fixture(t);
  for (const wrong of [{...facts, principalId: 'other'},
    {...facts, resultName: 'answer'},
    {...facts, indexKey: {...facts.indexKey, authorityScopeCid: `sha256:${'3'.repeat(64)}`}},
    {...facts, indexKey: {...facts.indexKey, namespaceId: 'other'}}]) {
    assert.equal(await f.authorize(wrong), false);
  }
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
