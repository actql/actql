// A fresh process recovers the accepted shared Run, never a fixture Plan.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as moon from '../../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {installNodeClientEffectRun, openClientRequestJournal} from
  '../../../../host-node/client-effect-run.mjs';
import {runCapturedEffectComputation} from '../../../../host-node/entry.mjs';

const input = JSON.parse(readFileSync(0, 'utf8'));
const environment = moon.clientProgramCheckEnvironment(input.environmentWire,
  JSON.parse(input.environmentWire).evidence_bundle_cid,
  false, false, true, false, false, false, false);
assert.ok(environment);
const prepared = moon.clientProgramEffectPreparationReady(
  moon.clientProgramPrepareEffectComputationWithParameters(input.document,
    'json', environment, undefined, []));
assert.ok(prepared);
const cid = digit => `sha256:${digit.repeat(64)}`;
const journal = openClientRequestJournal(input.directory);
let captures = 0;
try {
  const host = installNodeClientEffectRun({moon, journal,
    authorizeRequest: async () => ({executionContextCid: cid('a'),
      hostPolicyCid: cid('b'), createdAt: '2026-09-26T00:00:00.000Z',
      expiresAt: '2098-01-01T00:00:00.000Z'}),
    authorizeRunStart: async () => true,
    async execute({owner}) {
      captures++;
      const setup = moon.clientProgramOpenSourceFreeLocalEffectHost(
        owner, input.registry, input.values, 1n, 0n, 0n, 0n);
      assert.ok(setup);
      const execution = await runCapturedEffectComputation(setup);
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    },
  });
  const handle = await host.accept({prepared, authorityScopeCid: cid('a'),
    requestId: input.requestId, tenantId: 'tenant-a', principalId: 'caller',
    connection: {owner: 'local'}, lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
  const result = await host.start(handle);
  process.stdout.write(JSON.stringify({kind: result.kind, captures, ref: result.ref}));
} finally { journal.close(); }
