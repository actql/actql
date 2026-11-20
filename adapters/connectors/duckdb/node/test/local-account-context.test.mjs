import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {localHostAccountContext} from '../examples/local-account-context.mjs';
import {loadExecutionAuthorizationRuntime} from '../../../../host-node/authorization.mjs';
import {createLocalAuthorizationGate} from '../../../../host-node/local-account-config.mjs';

// Independent Account corpus preimages and CIDs. Only the Host-private fixed
// context preimage is hashed here; Account identity is never derived by this test.
const originalWire = '{"version":"actql-execution-account-config/0.1","account_id":"local:operator","entries":[{"entry_id":"files","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["local-files"]},"resource":{"all":true},"operation":{"all":true},"exclusions":[]}]}';
const originalCid = 'sha256:e240525257340428cc9117b0b0e84a000996791f43b230abdb553e55223bec12';
const deniedCid = 'sha256:8511f88f45fbdd0c2e1d9cd474819ccc9d5b638bf467bbc578bc938da47f76ab';
const hash = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const contextCid = hash('{"account_id":"local:operator","host":"actql-local-host","principal":"operator"}');
const bindingCid = cid => hash(`{"configuration_cid":"${cid}","context_cid":"${contextCid}","principal":"operator"}`);

test('DuckDB Host current context binds the original Common Account identity', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-duckdb-account-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  await writeFile(path, originalWire);
  const moon = await loadExecutionAuthorizationRuntime();
  const current = await localHostAccountContext({accountConfig: path, principal: 'operator'}, moon);
  assert.equal(current.configuration.configurationCid, originalCid);
  assert.equal(current.configuration.text, originalWire);
  assert.equal(current.context.contextCid, contextCid);
  assert.equal(current.authorizationContextCid, bindingCid(originalCid));
});

test('changed entries under the same account name change the Host binding and gate identity', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-duckdb-account-change-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  const config = {accountConfig: path, principal: 'operator'};
  const moon = await loadExecutionAuthorizationRuntime();
  await writeFile(path, originalWire);
  const first = await localHostAccountContext(config, moon);
  const account = first.configuration.admitConfiguration(moon, originalWire);
  assert.strictEqual(first.configuration.admitConfiguration(moon, originalWire), account);
  const deniedWire = originalWire.replace('"allow"', '"deny"');
  await writeFile(path, deniedWire);
  const second = await localHostAccountContext(config, moon);
  assert.equal(first.configuration.accountId, second.configuration.accountId);
  assert.equal(first.context.contextCid, second.context.contextCid);
  assert.equal(second.configuration.configurationCid, deniedCid);
  assert.equal(second.authorizationContextCid, bindingCid(deniedCid));
  assert.notEqual(first.authorizationContextCid, second.authorizationContextCid);
  assert.equal(JSON.parse(moon.executionAuthorizationAccountJson(
    first.configuration.admitConfiguration(moon, deniedWire))).configuration_cid, deniedCid);
  for (const [current, action] of [[first, 'dispatch'], [second, 'deny']]) {
    const gate = await createLocalAuthorizationGate({accountConfiguration: current.configuration.text,
      configurationCid: current.configuration.configurationCid,
      admitConfiguration: current.configuration.admitConfiguration, context: current.context});
    try {
      assert.equal(gate.configurationCid, current.configuration.configurationCid);
      const decision = await gate.authorize('preparation', {
        connection: 'local-files', resource: 'records', operation: 'read',
      }, {subjectCid: 'sha256:' + 'a'.repeat(64)});
      assert.equal(decision.action, action);
    } finally {gate.close();}
  }
  assert.throws(() => first.configuration.admitConfiguration({...moon}, originalWire),
    /ForeignLocalHostAccountRuntime/);
});

test('missing unreadable and rejected Account configurations remain distinct and non-authorizing', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-duckdb-account-missing-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json'), moon = await loadExecutionAuthorizationRuntime();
  const missing = await localHostAccountContext({principal: 'operator'}, moon);
  const unreadable = await localHostAccountContext({principal: 'operator', accountConfig: path}, moon);
  assert.equal(missing.configuration, undefined);
  assert.equal(missing.unreadable, false);
  assert.equal(unreadable.configuration, undefined);
  assert.equal(unreadable.unreadable, true);
  assert.notEqual(missing.authorizationContextCid, unreadable.authorizationContextCid);
  await writeFile(path, '{"account_id":"local:operator"}');
  const rejected = await localHostAccountContext({principal: 'operator', accountConfig: path}, moon);
  assert.equal(rejected.unreadable, false);
  assert.equal(rejected.configuration.configurationCid, undefined);
  assert.notEqual(rejected.authorizationContextCid, missing.authorizationContextCid);
  await assert.rejects(createLocalAuthorizationGate({accountConfiguration: rejected.configuration.text,
    configurationCid: rejected.configuration.configurationCid,
    admitConfiguration: rejected.configuration.admitConfiguration, context: rejected.context}),
  {code: 'ExecutionAuthorizationConfigurationRejected'});
});
