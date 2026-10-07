// Runs unchanged inside the existing normal packed Node installation. No
// repository implementation import, generated expected identity or new owner.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {connect} from '@actql/node';

const canonical = value => value !== null && typeof value === 'object'
  ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
  : JSON.stringify(value);
const hash = wire => 'sha256:' + createHash('sha256').update(wire).digest('hex');

test('installed Node package snapshots Host policy before loading Local and binds its effective identity', async t => {
  const base = JSON.parse(await readFile(new URL('./spec/local-check-environment.json',
    import.meta.resolve('@actql/local-node')), 'utf8'));
  const selected = {...base.host_policy_profile.capacity,
    max_effect_items: 1234, max_graph_construction_nodes: 23};
  const supplied = {...selected};
  let reads = 0;
  Object.defineProperty(supplied, 'max_effect_items', {enumerable: true, configurable: true,
    get() {reads++; return 1234;}});
  const directory = await mkdtemp(join(tmpdir(), 'actql-packed-host-policy-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const pending = connect({mode: 'local', owner: 'local',
    installation: {directory, hostCapacityPolicy: supplied}});
  assert.equal(reads, 1, '[host-policy:node-pre-await]');
  Object.defineProperty(supplied, 'max_effect_items', {value: 4321});
  const client = await pending;
  t.after(() => client.close());
  const effective = {max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000, ...selected};
  const scope = hash(JSON.stringify({version: 'actql-local-owner-scope/0.1', root: directory,
    principalId: userInfo().username, hostCapacityPolicyCid: hash(canonical(effective))}));
  const run = await client.aql('SELECT 1 AS n', {format: 'sql', requestId: 'packed-policy'});
  assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
  assert.deepEqual(await run.result('answer').all(), [{n: 1}]);
  assert.equal(run.ref.authorityScopeCid, scope);
  assert.equal(client.profile.scopeRef, scope);
  assert.equal(reads, 1);
  await assert.rejects(connect({mode: 'local', owner: 'local', installation:
    {directory, hostCapacityPolicy: {...selected, max_effect_items: 4321}}}),
  {message: 'InstalledHostConfigurationMismatch'});
});
