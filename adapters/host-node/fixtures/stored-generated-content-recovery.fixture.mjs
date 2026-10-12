// A fresh process opens only the original Store. No Source, encoder, Model or
// dispatch owner is installed, so this cannot recover by repeating computation.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import * as moon from '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../../store-local/publication-store.mjs';
import {issueStoredGeneratedContent} from '../generated-content-holding.mjs';

const descriptor = JSON.parse(await readFile(process.argv[2], 'utf8'));
const runtime = runtimeCore(moon);
const control = runtime.contentGenerationControl;
const store = await openLocalPublicationStore(descriptor.configuration, runtime.publicationControl);
try {
  const candidate = control.recoveryCandidate(descriptor.wire, descriptor.binding, descriptor.limits);
  const description = control.inspect(candidate);
  let checks = 0;
  const value = await issueStoredGeneratedContent({store, control, candidate,
    holdingCid: descriptor.holding.holding_cid,
    workspaceScopeCid: descriptor.binding.workspace_scope_cid,
    effectiveDataPolicyCid: descriptor.binding.effective_data_policy_cid,
    available: () => true, authorize: () => { checks++; return true; }, limits: descriptor.limits});
  assert.ok(value);
  const chunks = [];
  await store.consumePhysicalHolding(descriptor.holding.holding_cid, 0,
    chunk => chunks.push(Buffer.from(chunk)));
  process.stdout.write(JSON.stringify({description, bytes: Buffer.concat(chunks).toString('utf8'),
    checks, storedBytes: store.status().storedBytes}));
} finally {
  await store.close();
}
