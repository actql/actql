// Fresh-process probe for recorded Effect claims and final Set evidence.
// It reads the real Store and SQLite Ledger; it never opens a write Site.
import {readFileSync} from 'node:fs';
import * as moon from
  '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {recoverCompletedEffectfulComputation} from
  '../../host-common/completed-run-publication.mjs';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from
  '../../store-local/publication-store.mjs';
import {openEffectLedger} from '../effect-ledger.mjs';
import {issueAuthorizedEffectSetReceipt} from
  '../effect-response-recovery.mjs';

const input = JSON.parse(readFileSync(0, 'utf8'));
const core = runtimeCore(moon);
const control = core.publicationControl;
const store = await openLocalPublicationStore({
  directory: input.directory,
  storeAuthorityCid: input.storeAuthorityCid,
  capacityBytes: input.capacityBytes,
  maxObjectBytes: input.maxObjectBytes,
  maxObjects: input.maxObjects,
  maxContractNodes: input.maxContractNodes,
  maxContractDepth: input.maxContractDepth,
  privateEvidenceKey: Buffer.alloc(32, 4),
}, control);
let ledger;
let failure;
try {
  const runDefinition = control.admit('run_definition',
    input.runDefinitionWire, input.limits);
  const recovered = await recoverCompletedEffectfulComputation({
    store, control, runDefinition, contractLimits: input.limits,
  });
  ledger = openEffectLedger({moon, root: input.ledgerRoot,
    authorityScopeCid: input.authorityScopeCid,
    callerRequestId: input.callerRequestId, maxEntryBytes: 4096});
  const scope = core.effectApplicationControl.logicalRequestScope(
    input.authorityScopeCid, input.callerRequestId, 256);
  const admittedPreview = control.effectComputationPreviewLedgerIdentity(
    recovered.preview);
  const recorded = ledger.recoverRecordedClaims({
    preview: admittedPreview, scope,
    programId: input.programId, nodeId: input.nodeId,
    maxRows: input.maxRows, maxWork: input.maxWork,
  });
  const issued = await issueAuthorizedEffectSetReceipt({
    ledger, preview: admittedPreview, publicationPreview: recovered.preview,
    commonMoon: moon, authorizeEvidenceRead: async () => true,
    members: recorded.members.map(member => ({
      rowOwners: member.claims.map(claim => ({claim})), replayed: true,
    })),
    limits: input.limits,
  });
  const answer = {
    capturedRunCid: recovered.computation.capturedRun.identity,
    localInventory: JSON.parse(recovered.computation.capturedRun.wire)
      .effect_source_local_inventory,
    effectIdentities: JSON.parse(control.effectComputationPreviewWire(
      recovered.preview)).effects.map(
      member => member.effect_identity_cid),
    setReceiptCid: issued.set.identity,
    setStatus: JSON.parse(issued.set.wire).status,
    rowCounts: recorded.members.map(member => member.claims.length),
  };
  for (const result of recovered.storedResults.results) {
    if (result.prepared.status().pending) {
      await result.prepared.release();
    }
  }
  process.stdout.write(JSON.stringify(answer));
} catch (error) {
  failure = error;
  throw error;
} finally {
  ledger?.close();
  try { await store.close(); }
  catch (error) { if (failure === undefined) throw error; }
}
