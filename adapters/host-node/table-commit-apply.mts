// Whole-Relation physical dispatch under the existing captured Effect apply
// owner. This is a trusted Host connection, not a public Table installer, a
// second approval/Run owner, or authority derived from operation content.
import {authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {readPinnedEffectTableInput} from './effect-input-export.mjs';
import {readRecoveredTableInput, assertRecoveredTableInputAvailable}
  from './table-capture-recovery.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {settleSavedTableCommit} from './table-commit-outcome.mjs';

import type {assertAuthorizationAccountCurrent} from '../host-common/authorization-gate.mjs';
import type {effectApplicationControl} from '../host-common/effect-application-control.mjs';
import type {createIcebergPhysicalBridge} from '../connectors/local/host/iceberg-process.mjs';
import type {EffectDispatchClaim} from './effect-physical-dispatch.mjs';
import type {prepareRecoveredTableInput} from './table-capture-recovery.mjs';

type Receipt = ReturnType<ReturnType<typeof effectApplicationControl>['admitRowOutcomeReceiptFromResponse']>;
type Settlement = Parameters<typeof settleSavedTableCommit<EffectDispatchClaim, Receipt>>[0];
type CaptureLedger = Parameters<typeof captureClaimedEffectResponse>[0]['ledger'];
type PhysicalBridge = Pick<ReturnType<typeof createIcebergPhysicalBridge>,
  'prepareWrite' | 'status' | 'inspect' | 'cleanup' | 'execute'> & Settlement['bridge'];
type PhysicalWrite = ReturnType<PhysicalBridge['prepareWrite']>;
type Decision = Parameters<typeof assertAuthorizationAccountCurrent>[0];
type Scope = Pick<Decision['tuple'], 'connection' | 'resource'>;
type TablePreview = Readonly<{subjectCid: string}>;
type Binding = ReturnType<Settlement['control']['tablePreviewLedgerBinding']> & Readonly<{rowPreviewCid: string}>;
type SettlementControl = Omit<Settlement['control'], 'tablePreviewLedgerBinding'> & Readonly<{
  tablePreviewLedgerBinding(preview: object): Binding;
}>;
type DispatchControl = SettlementControl & Readonly<{
  admitTablePreviewClaim(preview: object, claim: EffectDispatchClaim): unknown;
}>;
type CapturedControl = SettlementControl & Readonly<{
  tablePreviewInputAvailable(preview: object): boolean;
  tableInputStorageMappingWire(input: object): string;
  tableInputSchemaWire(input: object): string;
  tableInputMatchesSource(input: object, artifact: object, identity: object): boolean;
}>;
type TableVersion = Readonly<{table_uuid: string; generation_cid: string}>;
type Operation = Readonly<{request_cid: string; schema_cid: string; storage_mapping_cid: string}> &
  (Readonly<{action: 'create'; expected_table: null}> | Readonly<{action: 'replace'; expected_table: TableVersion}>);
type TargetObservation = Readonly<{ok?: unknown; result: (TableVersion & Readonly<{
  schema_cid: string; storage_mapping_cid: string;
}>) | null}>;
type CleanupReply = Readonly<{ok?: unknown; result?: Readonly<{pending?: unknown}>}>;
type PreparePorts = Readonly<{
  bridge: PhysicalBridge; reservation: Parameters<PhysicalBridge['prepareWrite']>[0]['reservation'];
  maxBytes: number; signal?: AbortSignal;
}>;
type CapturedInput = PreparePorts & Readonly<{
  control: CapturedControl; store: Parameters<typeof prepareRecoveredTableInput>[0]['store'];
  holding: Parameters<typeof readPinnedEffectTableInput>[0]['holding'];
  tableInput: Readonly<{wire: string}>; identity: object;
  tablePreview: TablePreview; limits: Settlement['limits'];
}>;
type RecoveredInput = PreparePorts & Readonly<{
  control: SettlementControl; recoveredInput: Parameters<typeof readRecoveredTableInput>[0]['prepared'];
}>;
type Material = Readonly<{
  control: SettlementControl; bridge: PhysicalBridge; physical: PhysicalWrite; tablePreview: TablePreview;
  assertAvailable(): void; memberIndex: number; operation: Operation; rowPreviewCid: string;
  requestCid: string; subjectCid: string;
}>;
type MaterialInput = Pick<Material, 'control' | 'bridge' | 'physical' | 'tablePreview' | 'assertAvailable' | 'operation'> &
  Readonly<{binding: Binding}>;
declare const tableCommitPreparation: unique symbol;
type Prepared = Readonly<{[tableCommitPreparation]: true}>;
type OwnedInput = Readonly<{prepared: Prepared; signal?: AbortSignal}>;
type DispatchOwner = Readonly<{
  control: DispatchControl; ledger: CaptureLedger & Settlement['ledger']; prepared: readonly (Prepared | undefined)[];
  scopes: readonly Scope[]; credentialUseCid: string; limits: Settlement['limits'];
}>;
type DispatchFacts = Readonly<{
  members: readonly Readonly<{claims: readonly EffectDispatchClaim[]}>[];
  subjectCid: string; decisions: readonly Decision[]; signal?: AbortSignal;
}>;

const materials = new WeakMap<Prepared, Material>();
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);

const ownMaterial = (prepared: Prepared | undefined) => {
  const material = materials.get(prepared!);
  if (material === undefined) fail('ForeignTableCommitMaterial');
  return material;
};

// The existing process owner supplies physical stop. Keep the preparation
// reachable when cleanup fails: a caller can retry the same Catalog fence and
// file manifest, without recreating input or inferring noncommit from a head.
export function capturedTableCommitPhysicalStatus(prepared: Prepared) {
  const material = ownMaterial(prepared);
  return material.bridge.status(material.physical);
}

export async function cleanupCapturedTableCommit({prepared, signal}: OwnedInput) {
  const material = ownMaterial(prepared);
  const status = material.bridge.status(material.physical);
  if (!status.attempted) {
    // Preparation performed no Catalog I/O or file allocation. Invalidate
    // this unsent material rather than inventing a stopped-writer observation.
    // A recovered operation may have earlier staging under another process:
    // this result covers only this new preparation and deletes no such files.
    materials.delete(prepared);
    return Object.freeze({ok: true,
      result: Object.freeze({retained: false, pending: false, removed: 0})});
  }
  return material.bridge.cleanup(material.physical, signal) as Promise<CleanupReply | null | undefined>;
}

export async function prepareCapturedTableCommit({control, store, holding,
  tableInput, identity, tablePreview, bridge, reservation, maxBytes, limits,
  signal}: CapturedInput) {
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
  const operation = JSON.parse(binding.operationWire) as Operation;
  const mapping = JSON.parse(control.tableInputStorageMappingWire(tableInput));
  // Pure bounded preparation, before any durable send claim. No Catalog I/O.
  const schemaWire = control.tableInputSchemaWire(tableInput);
  const physical = bridge.prepareWrite({operation, mapping, rows, reservation, schemaWire});
  return retainMaterial({control, bridge, physical, tablePreview, binding,
    operation, assertAvailable: () => {
      if (control.tablePreviewInputAvailable(tablePreview) !== true) {
        fail('UnavailableTableCommitInput');
      }
    }});
}

// A recovered content view never masquerades as a live Compute input. Its
// exact capture/Store owners supply availability; common apply supplies the
// current approval and durable dispatch claim before execute.
export async function prepareRecoveredTableCommit({control, recoveredInput,
  bridge, reservation, maxBytes, signal}: RecoveredInput) {
  assertRecoveredTableInputAvailable(recoveredInput);
  const {tablePreview, operationWire, mappingWire, schemaWire} = recoveredInput;
  const binding = control.tablePreviewLedgerBinding(tablePreview);
  if (binding.operationWire !== operationWire) fail('ForeignTableCommitInput');
  const rows = await readRecoveredTableInput({prepared: recoveredInput, maxBytes, signal});
  signal?.throwIfAborted();
  assertRecoveredTableInputAvailable(recoveredInput);
  const operation = JSON.parse(operationWire) as Operation, mapping = JSON.parse(mappingWire);
  const physical = bridge.prepareWrite({operation, mapping, rows, reservation, schemaWire});
  return retainMaterial({control, bridge, physical, tablePreview, binding, operation,
    assertAvailable: () => assertRecoveredTableInputAvailable(recoveredInput)});
}

function retainMaterial({control, bridge, physical, tablePreview, binding,
  operation, assertAvailable}: MaterialInput) {
  const prepared = Object.freeze({}) as Prepared;
  materials.set(prepared, Object.freeze({control, bridge, physical,
    tablePreview, assertAvailable, memberIndex: binding.memberIndex,
    operation, rowPreviewCid: binding.rowPreviewCid, requestCid: operation.request_cid,
    subjectCid: tablePreview.subjectCid}));
  return prepared;
}

// Called by the existing apply owner's refreshPreflight, after current target
// read authorization. Publication still compares the approved generation
// atomically, so a race after this observation cannot overwrite another head.
export async function refreshCapturedTableTargets<Preflight extends object>({prepared, preflight, signal}: Readonly<{
  prepared: readonly (Prepared | undefined)[]; preflight: Preflight; signal?: AbortSignal;
}>) {
  const observedRows = [], guardVersions = [];
  for (const value of prepared) {
    const material = ownMaterial(value);
    signal?.throwIfAborted();
    const observed = await material.bridge.inspect(material.physical, signal) as TargetObservation | null | undefined;
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
    material.assertAvailable();
  }
  return Object.freeze({...preflight, observedRows: Object.freeze(observedRows),
    guardVersions: Object.freeze(guardVersions)});
}

// Called synchronously by the live/recovered apply owner's bindDispatch after its
// current-use checks and journal-authoritative approval. An account allow, a
// copied decision or an approval of another sealed Set cannot send a Table.
export function bindApprovedTableCommitDispatch({control, ledger, prepared,
  scopes, credentialUseCid, limits}: DispatchOwner, {members, subjectCid, decisions, signal}: DispatchFacts) {
  if (!Array.isArray(prepared) || prepared.length !== members.length ||
      !Array.isArray(scopes) || scopes.length !== members.length ||
      !cid(credentialUseCid)) fail('InvalidTableCommitDispatch');
  const owned = prepared.map((value, index) => {
    const material = materials.get(value!);
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
        decision!.action !== 'dispatch' || decision!.boundary !== 'effect_commit' ||
        decision!.tuple.operation !== 'effect' || decision!.subjectCid !== subjectCid ||
        decision!.basis !== 'resumed' || !cid(decision!.checkpointCid) ||
        !cid(decision!.resolutionCid)) fail('TableCommitApprovalRequired');
    // Semantic Preview/request CIDs cannot distinguish legitimate copies
    // authored under different scopes. Admit the actual claim against the
    // exact typed Preview before any durable send claim or provider call.
    control.admitTablePreviewClaim(material.tablePreview, members[index].claims[0]);
    return material;
  });
  return async ({memberIndex, rowIndex, claim}: Readonly<{
    memberIndex: number; rowIndex: number; claim: EffectDispatchClaim;
  }>) => {
    const material = owned[memberIndex];
    if (rowIndex !== 0 || claim !== members[memberIndex]?.claims[0] ||
        material === undefined) fail('ForeignTableCommitDispatch');
    signal?.throwIfAborted();
    material.assertAvailable();
    control.admitTablePreviewClaim(material.tablePreview, claim);
    await captureClaimedEffectResponse({ledger, claim,
      requestCid: material.requestCid,
      execute: () => material.bridge.execute(material.physical,
        {useCid: credentialUseCid, signal})});
    // Only the durably saved, fully matched original Catalog receipt settles
    // the common Ledger. Unknown/error replies preserve reconciliation duty.
    return settleSavedTableCommit({control, ledger, bridge: material.bridge,
      tablePreview: material.tablePreview, claim, limits});
  };
}
