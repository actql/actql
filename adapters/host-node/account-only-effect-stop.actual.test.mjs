import assert from 'node:assert/strict';
import test from 'node:test';
import {access, mkdir, mkdtemp, readFile, stat} from 'node:fs/promises';
import {join} from 'node:path';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';

// Real source-checkout Host/Common/Store/SQLite. The operator explicitly
// supplies Account Allow, but no Reviewer, signing key or decision callback.
// A requested stop is not permission to apply the Effect without a signer.
test('Account-only actual Host refuses a requested Effect stop without writing or creating a Reviewer', async t => {
  const scratch = new URL('../../_build/account-only-effect-stop/', import.meta.url);
  await mkdir(scratch, {recursive: true});
  const directory = await mkdtemp(join(scratch.pathname, 'host-'));
  const project = scaffoldProject(join(directory, 'project'), 'churn-risk-mock');
  const accountConfiguration = JSON.stringify({version: 'actql-execution-account-config/0.1',
    account_id: 'explicit-test-operator', entries: [{entry_id: 'allow', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {all: true}, exclusions: []}]});
  const cwd = process.cwd(), diagnostics = [];
  let client, primary;
  process.chdir(project.directory);
  t.diagnostic(JSON.stringify({directory: project.directory}));
  try {
    const path = 'mock/data.json';
    const before = await readFile(path), original = await stat(path, {bigint: true});
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', profile: 'mock',
      installation: {directory: '.actql', authorization: {accountConfiguration,
        observe: (event, detail) => diagnostics.push({event, ...detail})}}});
    const execution = await client.startSource(
      "SELECT '001Acme' AS id, 'high' AS risk |> RESULT updates " +
      '|> EFFECT UPDATE salesforce.Account ID id SET (Churn_Risk__c = risk);',
      {format: 'aql', stopBefore: 'commit'});
    const state = await execution.wait();
    t.diagnostic(JSON.stringify({state, diagnostics}));
    assert.notEqual(state.status, 'succeeded');
    assert(diagnostics.some(value => value.code === 'RequestedEffectStopUnavailable'),
      'the existing Effect owner must identify the absent requested-stop capability');
    assert.deepEqual(await readFile(path), before);
    const after = await stat(path, {bigint: true});
    assert.deepEqual([after.dev, after.ino, after.mtimeNs],
      [original.dev, original.ino, original.mtimeNs]);
    await assert.rejects(access('.actql/mock-account'), {code: 'ENOENT'});
    await assert.rejects(access('.actql/checkpoints/journal'), {code: 'ENOENT'});
  } catch (cause) { primary = cause; }
  finally {
    try { await client?.close(); }
    catch (cause) { primary = primary === undefined ? cause
      : new AggregateError([primary, cause], 'Original stop refusal and Host cleanup failed'); }
    process.chdir(cwd);
  }
  if (primary !== undefined) throw primary;
});
