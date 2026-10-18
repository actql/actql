import assert from 'node:assert/strict';
import test from 'node:test';
import {existsSync} from 'node:fs';
import {connectEmbeddedLocal, assertInitialControlHostPreparation}
  from './embedded-local.mjs';

// Actual installed module and matching ABI/Checkpoint import prerequisites.
// No operational startup envelope is supplied by this component fixture, and
// no Common execution runtime, Host Store, Provider or Run may be opened.
const runtime = new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url);

test('absent actual startup refuses before options getters or Common import', async () => {
  assert.equal(existsSync(runtime), false, 'This counter requires an absent Common execution runtime');
  let observations = 0;
  const options = new Proxy({}, {
    get() {observations++; assert.fail('Do not read unadmitted options');},
    ownKeys() {observations++; assert.fail('Do not copy unadmitted options');},
    getOwnPropertyDescriptor() {observations++; assert.fail('Do not snapshot unadmitted options');},
  });
  await assert.rejects(connectEmbeddedLocal(options), {code: 'NodeInitialControlAdmissionUnavailable'});
  assert.equal(observations, 0);
  assert.equal(existsSync(runtime), false);
});

test('missing startup does not select a profile or observe an installation supplier', async () => {
  let profiles = 0, installations = 0;
  const options = {get profile() {profiles++; return 'mock';},
    get installation() {installations++; return {registerModelProviders() {
      assert.fail('No Provider setup without the original startup');
    }};}};
  await assert.rejects(connectEmbeddedLocal(options), {code: 'NodeInitialControlAdmissionUnavailable'});
  assert.equal(profiles, 0); assert.equal(installations, 0);
});

test('module namespace or a public function does not reconstruct the original candidate pair', () => {
  const host = {}, installation = {};
  for (const supplier of [undefined, () => {}, connectEmbeddedLocal]) {
    assert.throws(() => assertInitialControlHostPreparation({host, installation,
      generation: host, supplier, moduleLifetime: {}}),
    {code: 'InstalledHostPreparationChanged'});
  }
});
