import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {tmpdir, userInfo} from 'node:os';
import {test} from 'node:test';
import {connectEmbeddedLocal} from '../adapters/host-node/embedded-local.mjs';
import {typedJsonLiteralSuccesses} from './fixtures/typed-json-literal-input.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';

test('installed Host publishes every typed JSON root and empty Result', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-typed-json-public-', label: 'Typed JSON installed Host'});
  const directory = scratch.path;
  const events = [];
  const keys = generateKeyPairSync('ed25519');
  const authorization = {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'typed-json-public', entries: [{entry_id: 'write', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
      principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({
      type: 'pkcs8', format: 'pem'})},
    observe: (name, detail) => events.push({name, code: detail?.code}),
  };
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory, authorization}});
  try {
    for (const input of typedJsonLiteralSuccesses) {
      const execution = await client.aql(input.text, {format: input.format,
        requestId: input.name});
      const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
      assert.equal(state.status, 'succeeded', JSON.stringify({directory, events}));
      assert.deepEqual(await execution.result('answer').all(), input.expected);
      assert.deepEqual((await execution.result('answer').describe()).columns, input.columns);
    }
  } finally { await client.close(); }
  scratch.passed();
});
