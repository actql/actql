import assert from 'node:assert/strict';
import test from 'node:test';
import {access, mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as common from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openAIChatStaticOriginals} from '../../packages/provider-ai-sdk/_internal/openai-chat.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';

// Real ordinary source-checkout Host/Common/SQLite/Store and loaded SDK module
// originals. Registration below is an explicit no-I/O provider: these cases
// exercise Host installation/currentness/cleanup, not a Model Call or funding.
function registration(registered) {
  return actual => {
    assert.strictEqual(actual, common);
    registered();
    return [{providerId: 'models/ordinary-sdk', sdkStaticOriginals: openAIChatStaticOriginals,
      validatePrompt: () => true, invoke() {assert.fail('No Model invocation in a registration check');}}];
  };
}

test('ordinary real Host binds SDK originals without preload and closes reopens independent installations', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-ordinary-model-runtime-'));
  const cwd = process.cwd();
  let first, second, registrations = 0, primary;
  process.chdir(directory);
  t.diagnostic(JSON.stringify({directory}));
  const registerModelProviders = registration(() => registrations++);
  const open = name => connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory: join(directory, name), registerModelProviders}});
  try {
    first = await open('first');
    second = await open('second');
    assert.equal(registrations, 2);
    assert.deepEqual(await first.sql('SELECT 1 AS id').all(), [{id: 1}]);
    await first.close(); first = undefined;
    assert.deepEqual(await second.sql('SELECT 2 AS id').all(), [{id: 2}]);
    first = await open('first');
    assert.equal(registrations, 3, 'A reopened Host adopts the current registration again');
    assert.deepEqual(await first.sql('SELECT 3 AS id').all(), [{id: 3}]);
  } catch (cause) {primary = cause;}
  finally {
    for (const client of [first, second]) {
      try {await client?.close();}
      catch (cause) {primary = primary === undefined ? cause
        : new AggregateError([primary, cause], 'Original Model registration and Host cleanup failed');}
    }
    process.chdir(cwd);
  }
  if (primary !== undefined) throw primary;
  for (const name of ['first', 'second']) {
    await assert.rejects(access(join(directory, name, 'publication/owner/owner.json')), {code: 'ENOENT'});
  }
});

test('ordinary real Host preserves a partial Provider registration failure and can reopen after original cleanup', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-ordinary-model-partial-'));
  const cwd = process.cwd();
  let client, fail = true, registrations = 0, primary;
  process.chdir(directory);
  t.diagnostic(JSON.stringify({directory}));
  const original = new Error('OriginalSecondProviderRegistrationFailed');
  const retained = registration(() => registrations++);
  const registerModelProviders = actual => {
    const entries = retained(actual);
    if (fail) entries.push({get providerId() {throw original;},
      validatePrompt: () => true, invoke() {assert.fail('No Model invocation');}});
    return entries;
  };
  const options = {mode: 'local', owner: 'local',
    installation: {directory: join(directory, 'host'), registerModelProviders}};
  try {
    await assert.rejects(connectEmbeddedLocal(options), cause => cause === original);
    assert.equal(registrations, 1);
    await assert.rejects(access(join(directory, 'host/publication/owner/owner.json')), {code: 'ENOENT'});
    fail = false;
    client = await connectEmbeddedLocal(options);
    assert.equal(registrations, 2);
    assert.deepEqual(await client.sql('SELECT 4 AS id').all(), [{id: 4}]);
  } catch (cause) {primary = cause;}
  finally {
    try {await client?.close();}
    catch (cause) {primary = primary === undefined ? cause
      : new AggregateError([primary, cause], 'Partial registration and original Host cleanup failed');}
    process.chdir(cwd);
  }
  if (primary !== undefined) throw primary;
  await assert.rejects(access(join(directory, 'host/publication/owner/owner.json')), {code: 'ENOENT'});
});
