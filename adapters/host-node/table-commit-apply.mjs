// Whole-Relation physical dispatch under the existing captured Effect apply
// owner. This is a trusted Host connection, not a public Table installer, a
// second approval/Run owner, or authority derived from operation content.
import {authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {readPinnedEffectTableInput} from './effect-input-export.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {settleSavedTableCommit} from './table-commit-outcome.mjs';

const materials = new WeakMap();
const fail = code => { throw Object.assign(new Error(code), {code}); };
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);

const ownMaterial = prepared => {
  const material = materials.get(prepared);
  if (material === undefined) fail('ForeignTableCommitMaterial');
  return material;
};

// The existing process owner supplies physical stop. Keep the preparation
// reachable when cleanup fails: a caller can retry the same Catalog fence and
// file manifest, without recreating input or inferring noncommit from a head.
export function capturedTableCommitPhysicalStatus(prepared) {
  const material = ownMaterial(prepared);
  return material.bridge.status(material.physical);
}

export async function cleanupCapturedTableCommit({prepared, signal}) {
  const material = ownMaterial(prepared);
  const status = material.bridge.status(material.physical);
  if (!status.attempted) {
    // Preparation performed no Catalog I/O or file allocation. Invalidate
    // this unsent material rather than inventing a stopped-writer observation.
    materials.delete(prepared);
    return Object.freeze({ok: true,
      result: Object.freeze({retained: false, pending: false, removed: 0})});
  }
  return material.bridge.cleanup(material.physical, signal);
}

export async function prepareCapturedTableCommit({control, store, holding,
  tableInput, identity, tablePreview, bridge, reservation, maxBytes, limits,
  signal}) {
  const binding = control.tablePreviewLedgerBinding(tablePreview);
  if (tableInput.wire !== binding.operationWire ||
      control.tablePreviewInputAvailable(tablePreview) !== true) {
    fail('ForeignTableCommitInput');
  }
  const rows = await readPinnedEffectTableInput({holding, store, control,
    tableInput, identity, maxBytes, signal});
  signal?.throwIfAborted();
  if (control.tablePreviewInputAvailable(tablePreview) !== true) {
    fail('UnavailableTableCommitInput');
  }
  const operation = JSON.parse(binding.operationWire);
  const mapping = JSON.parse(control.localEffectTableStorageMapping(
    holding.localResultArtifact, limits).wire);
  // Pure bounded preparation, before any durable send claim. No Catalog I/O.
  const physical = bridge.prepareWrite({operation, mapping, rows, reservation});
  const prepared = Object.freeze({});
  materials.set(prepared, Object.freeze({control, bridge, physical,
    tablePreview, memberIndex: binding.memberIndex,
    operation, rowPreviewCid: binding.rowPreviewCid, requestCid: operation.request_cid,
    subjectCid: tablePreview.subjectCid}));
  return prepared;
}

// Called by the existing apply owner's refreshPreflight, after current target
// read authorization. Publication still compares the approved generation
// atomically, so a race after this observation cannot overwrite another head.
export async function refreshCapturedTableTargets({prepared, preflight, signal}) {
  const observedRows = [], guardVersions = [];
  for (const value of prepared) {
    const material = ownMaterial(value);
    signal?.throwIfAborted();
    const observed = await material.bridge.inspect(material.physical, signal);
    if (observed?.ok !== true) fail('TableTargetObservationUnknown');
    const {operation} = material;
    const current = observed.result;
    if (operation.action === 'create') {
      if (current !== null) fail('TableCreateNameConflict');
    } else {
      const expected = operation.expected_table;
      if (current?.table_uuid !== expected.table_uuid ||
          current?.generation_cid !== expected.generation_cid) {
        fail('TableExpectedGenerationConflict');
      }
      if (current.schema_cid !== operation.schema_cid ||
          current.storage_mapping_cid !== operation.storage_mapping_cid) {
        fail('TableSchemaReplacementUnsupported');
      }
      observedRows.push(material.rowPreviewCid);
      guardVersions.push(current.generation_cid);
    }
    if (material.control.tablePreviewInputAvailable(material.tablePreview) !== true) {
      fail('UnavailableTableCommitInput');
    }
  }
  return Object.freeze({...preflight, observedRows: Object.freeze(observedRows),
    guardVersions: Object.freeze(guardVersions)});
}

// Called synchronously by applyCapturedEffectSet.bindDispatch only after its
// current-use checks and journal-authoritative approval. An account allow, a
// copied decision or an approval of another sealed Set cannot send a Table.
export function bindApprovedTableCommitDispatch({control, ledger, prepared,
  scopes, credentialUseCid, limits}, {members, subjectCid, decisions, signal}) {
  if (!Array.isArray(prepared) || prepared.length !== members.length ||
      !Array.isArray(scopes) || scopes.length !== members.length ||
      !cid(credentialUseCid)) fail('InvalidTableCommitDispatch');
  const owned = prepared.map((value, index) => {
    const material = materials.get(value);
    const scope = scopes[index];
    const decision = decisions.find(value =>
      value.tuple?.connection === scope?.connection &&
      value.tuple?.resource === scope?.resource);
    if (material?.control !== control || material.memberIndex !== index ||
        material.subjectCid !== subjectCid || members[index].claims.length !== 1 ||
        members[index].claims[0].canonicalRequestCid !== material.requestCid) {
      fail('ForeignTableCommitDispatch');
    }
    if (!authorizationDispatchFacts(decision) ||
        decision.action !== 'dispatch' || decision.boundary !== 'effect_commit' ||
        decision.tuple.operation !== 'effect' || decision.subjectCid !== subjectCid ||
        decision.basis !== 'resumed' || !cid(decision.checkpointCid) ||
        !cid(decision.resolutionCid)) fail('TableCommitApprovalRequired');
    return material;
  });
  return async ({memberIndex, rowIndex, claim}) => {
    const material = owned[memberIndex];
    if (rowIndex !== 0 || claim !== members[memberIndex]?.claims[0] ||
        material === undefined) fail('ForeignTableCommitDispatch');
    signal?.throwIfAborted();
    if (control.tablePreviewInputAvailable(material.tablePreview) !== true) {
      fail('UnavailableTableCommitInput');
    }
    await captureClaimedEffectResponse({ledger, claim,
      requestCid: material.requestCid,
      execute: () => material.bridge.execute(material.physical,
        {useCid: credentialUseCid, signal})});
    // Only the durably saved, fully matched original Catalog receipt settles
    // the common Ledger. Unknown/error replies preserve reconciliation duty.
    return settleSavedTableCommit({control, ledger,
      tablePreview: material.tablePreview, claim, limits});
  };
}
