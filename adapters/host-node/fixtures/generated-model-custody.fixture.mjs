// Read only the existing encrypted fixed-input custody in a fresh process.
// No Source/encoder/Model sender is installed and no Run outcome is changed.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {loadPrivateEvidenceKey, openContinuationEvidence} from '../local-continuation-evidence.mjs';
import {createPublicationContractControlFixture} from '../../host-common/publication-contract-control.fixture.mjs';
import * as moon from '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../../store-local/publication-store.mjs';
import {issueStoredGeneratedContent} from '../generated-content-holding.mjs';

const [root, expectedRun] = process.argv.slice(2);
const checkpointRoot = join(root, 'checkpoints');
const database = new DatabaseSync(join(checkpointRoot, 'journal', 'checkpoint-journal.sqlite3'), {readOnly: true});
const row = database.prepare(`SELECT originals_json, checkpoint_originals_json FROM resume_model_scopes
  WHERE json_extract(inventory_json, '$.runDefinitionCid') = ?`).get(expectedRun);
assert.ok(row, 'original checked Model inventory remains discoverable');
const originals = JSON.parse(row.checkpoint_originals_json || row.originals_json);
database.close();
const receipt = JSON.parse(originals.fixedInputReceiptWire);
assert.equal(receipt.runDefinitionCid, expectedRun);
const key = await loadPrivateEvidenceKey(checkpointRoot);
const unused = () => { throw new Error('ReadOnlyCustodyMustNotSelectRetirement'); };
const evidence = openContinuationEvidence({stateDirectory: checkpointRoot, ...key,
  contractControl: createPublicationContractControlFixture(),
  preparation: unused, isTerminalRunOutcome: unused});
try {
  const held = await evidence.open(receipt.ownerId);
  assert.equal(held.requestCid, expectedRun);
  const bytes = await held.bytes('captured_input', receipt.cid, {maxBytes: 3 * 1024 * 1024});
  const snapshot = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
  assert.ok(snapshot.contentGeneration);
  // The authenticated fixed input supplies the original descriptor, not fresh
  // reference authority. The installing fixture explicitly admits current
  // access; the existing Store and common issuer independently confirm custody.
  const recovery = snapshot.contentGeneration;
  const runtime = runtimeCore(moon);
  const control = runtime.contentGenerationControl;
  const store = await openLocalPublicationStore({directory: join(root, 'publication'),
    storeAuthorityCid: recovery.binding.content_store_cid,
    capacityBytes: 512 * 1024 * 1024, maxObjectBytes: 1000000,
    maxObjects: 10000, maxContractNodes: 10000, maxContractDepth: 64,
    privateEvidenceKey: key.key}, runtime.publicationControl);
  try {
    const limits = {maxBytes: 16384, maxNodes: 256, maxDepth: 32, maxTextUnits: 16384};
    const candidate = control.recoveryCandidate(recovery.referenceWire, recovery.binding, limits);
    const live = () => Date.now() < Date.parse(recovery.binding.expires_at);
    const reference = await issueStoredGeneratedContent({store, control, candidate,
      holdingCid: recovery.byteHoldingCid,
      workspaceScopeCid: recovery.binding.workspace_scope_cid,
      effectiveDataPolicyCid: recovery.binding.effective_data_policy_cid,
      available: live, authorize: live, limits});
    assert.ok(reference);
    const chunks = [];
    await store.consumePhysicalHolding(recovery.byteHoldingCid, 0,
      chunk => chunks.push(Buffer.from(chunk)));
    process.stdout.write(JSON.stringify({receipt, snapshot,
      recoveredReferenceWire: control.inspect(candidate).wire,
      recoveredBytes: Buffer.concat(chunks).toString('utf8')}));
  } finally {
    await store.close();
  }
} finally {
  await evidence.close();
  key.key.fill(0);
}
