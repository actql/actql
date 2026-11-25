// Table-specific projections under the existing capture, Store and Effect
// owners. This module neither recreates Compute nor grants approval/send rights.
import {prepareCompletedEffectfulPublication, prepareCompletedEffectSourceMembers,
  confirmCompletedEffectfulApplySources, type recoverCompletedEffectfulComputation}
  from '../host-common/completed-run-publication.mjs';
import {readRecoveredEffectTableInput} from './effect-source-holdings.mjs';
import {constructEffectfulPublication} from '../host-common/run-publication.mjs';

import type {createIcebergPhysicalBridge} from '../connectors/local/host/iceberg-process.mjs';

type PublicationOptions = Parameters<typeof prepareCompletedEffectfulPublication>[0];
type PublicationInventory = ReturnType<typeof prepareCompletedEffectfulPublication>;
type ContractLimits = Parameters<typeof recoverCompletedEffectfulComputation>[0]['contractLimits'];
type MaterialLimits = ContractLimits & Readonly<{maxWork: number}>;
type Recovered = Pick<Awaited<ReturnType<typeof recoverCompletedEffectfulComputation>>,
  'storedResults' | 'computation' | 'preview' | 'connectorRecovery'>;
type RecoveredPreview = Readonly<{operationWire: string; mappingWire: string; subjectCid: string; then?: never}>;
type CaptureControl = Readonly<{
  tablePreviewLedgerBinding(preview: object): Readonly<{memberIndex: number; operationWire: string}>;
  tableInputStorageMappingWire(input: object): string;
  tableInputSchemaWire(input: object): string;
}>;
type Bridge = Pick<ReturnType<typeof createIcebergPhysicalBridge>, 'admitStorageMapping'>;
type RecoveryControl = PublicationOptions['control'] &
  Parameters<Bridge['admitStorageMapping']>[0]['control'] & Readonly<{
    bindRecoveredTablePreview(preview: PublicationInventory['preview'], memberIndex: number,
      invocation: PublicationInventory['chain']['invocation'], source: PublicationInventory['effectSources'][number],
      capturedRun: PublicationInventory['chain']['capturedRun'], scope: unknown, mappingWire: string,
      authorityCid: string, contractLimits: ContractLimits, tableLimits: MaterialLimits): RecoveredPreview;
    checkRecoveredTableSchemaWire(preview: RecoveredPreview, wire: string, limits: MaterialLimits): string;
    recoveredTablePreviewMatchesSource(preview: RecoveredPreview, source: PublicationInventory['effectSources'][number]): boolean;
}>;
type RecoveredTableStore = PublicationOptions['store'] & Parameters<typeof readRecoveredEffectTableInput>[0]['store'];
type RecoveryOwner = Readonly<{recovered: Recovered; store: RecoveredTableStore;
  control: RecoveryControl; source: ReturnType<typeof prepareCompletedEffectSourceMembers>[number]}>;
type PreparedInput = Readonly<{tablePreview: RecoveredPreview; operationWire: string; mappingWire: string; schemaWire: string}>;
type RecoveryOptions = Omit<RecoveryOwner, 'source'> & Readonly<{
  memberIndex: number; requestScope: unknown; contractLimits: ContractLimits; tableLimits: MaterialLimits;
  bridge: Bridge; signal?: AbortSignal; recoveryResources?: Parameters<typeof constructEffectfulPublication>[0];
}>;

const owners = new WeakMap<PreparedInput, RecoveryOwner>();
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const exactKeys = (value: unknown, fields: readonly string[]): value is Record<string, unknown> => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join() === fields.slice().sort().join();

export function capturedTableRecoveryRecord({control, tableInput, tablePreview}: Readonly<{
  control: CaptureControl; tableInput: Readonly<{wire: string}>; tablePreview: object;
}>) {
  const binding = control.tablePreviewLedgerBinding(tablePreview);
  if (binding.operationWire !== tableInput.wire) fail('ForeignTableRecoveryInput');
  const mappingWire = control.tableInputStorageMappingWire(tableInput);
  return Object.freeze({memberIndex: binding.memberIndex, kind: 'table_commit',
    observationCid: (JSON.parse(binding.operationWire) as Readonly<{request_cid: string}>).request_cid,
    wire: JSON.stringify({mapping_wire: mappingWire, operation_wire: binding.operationWire,
      schema_wire: control.tableInputSchemaWire(tableInput)})});
}

export async function prepareRecoveredTableInput({recovered, store, control,
  memberIndex, requestScope, contractLimits, tableLimits, bridge, signal, recoveryResources}: RecoveryOptions) {
  signal?.throwIfAborted();
  if (typeof bridge?.admitStorageMapping !== 'function') fail('MissingTableMappingValidator');
  const publicationOptions: PublicationOptions = {execution: null,
    store, control, storedResults: recovered.storedResults,
    computation: recovered.computation, preview: recovered.preview};
  const inventory = prepareCompletedEffectfulPublication(publicationOptions);
  const source = prepareCompletedEffectSourceMembers(publicationOptions)
    .find(value => value.memberIndex === memberIndex);
  const records = recovered.connectorRecovery.filter(value => value.memberIndex === memberIndex);
  if (source === undefined || records.length !== 1 || records[0].kind !== 'table_commit') {
    fail('MissingTableRecoveryMaterial');
  }
  const saved: unknown = JSON.parse(records[0].wire);
  if (!exactKeys(saved, ['mapping_wire', 'operation_wire', 'schema_wire']) ||
      typeof saved.mapping_wire !== 'string' || typeof saved.operation_wire !== 'string' ||
      typeof saved.schema_wire !== 'string') {
    fail('InvalidTableRecoveryMaterial');
  }
  const mapping = bridge.admitStorageMapping({control,
    mappingWire: saved.mapping_wire, limits: tableLimits}) as Readonly<{wire: string}> | undefined;
  if (mapping?.wire !== saved.mapping_wire) fail('ForeignTableRecoveryMapping');
  // The prior Store return cut only temporary constructor workspace. Re-enter
  // its SAME retained Read before the whole captured-context inverse; its
  // typed original and current/cleanup fences are not a replacement budget.
  const tablePreview = recoveryResources === undefined
    ? control.bindRecoveredTablePreview(inventory.preview, memberIndex,
      inventory.chain.invocation, source.source, inventory.chain.capturedRun,
      requestScope, mapping.wire, store.storeAuthorityCid, contractLimits, tableLimits)
    : constructEffectfulPublication(recoveryResources, inventory.chain.capturedRun,
      control, control.bindRecoveredTablePreview, [inventory.preview, memberIndex,
        inventory.chain.invocation, source.source, inventory.chain.capturedRun,
        requestScope, mapping.wire, store.storeAuthorityCid, contractLimits, tableLimits]);
  if (tablePreview.operationWire !== saved.operation_wire ||
      records[0].observationCid !== JSON.parse(tablePreview.operationWire).request_cid) {
    fail('ForeignTableRecoveryOperation');
  }
  const schemaWire = control.checkRecoveredTableSchemaWire(tablePreview,
    saved.schema_wire, tableLimits);
  await confirmCompletedEffectfulApplySources({store, control,
    computation: recovered.computation, preview: recovered.preview});
  prepareCompletedEffectfulPublication({execution: null, store, control,
    storedResults: recovered.storedResults, computation: recovered.computation,
    preview: recovered.preview});
  signal?.throwIfAborted();
  const prepared = Object.freeze({tablePreview,
    operationWire: tablePreview.operationWire, mappingWire: tablePreview.mappingWire,
    schemaWire});
  owners.set(prepared, {recovered, store, control, source});
  return prepared;
}

// Synchronous current-owner validation at the final dispatch boundary. This
// is not a physical custody observation or authorization; preparation/read and
// the recovered apply owner separately confirm the actual Store holdings.
export function assertRecoveredTableInputAvailable(prepared: PreparedInput) {
  const owner = owners.get(prepared);
  if (owner === undefined) fail('ForeignRecoveredTableInput');
  const {recovered, store, control} = owner;
  prepareCompletedEffectfulPublication({execution: null, store, control,
    storedResults: recovered.storedResults, computation: recovered.computation,
    preview: recovered.preview});
}

export async function readRecoveredTableInput({prepared, maxBytes, signal}: Readonly<{
  prepared: PreparedInput; maxBytes: number; signal?: AbortSignal;
}>): Promise<readonly unknown[]> {
  const owner = owners.get(prepared);
  if (owner === undefined) fail('ForeignRecoveredTableInput');
  const {recovered, store, control, source} = owner;
  // Recheck current owners and custody after awaits and before physical read.
  assertRecoveredTableInputAvailable(prepared);
  await confirmCompletedEffectfulApplySources({store, control,
    computation: recovered.computation, preview: recovered.preview});
  const assertAvailable = () => assertRecoveredTableInputAvailable(prepared);
  assertAvailable();
  return readRecoveredEffectTableInput({store, control, source: source.source,
    artifact: source.artifact, tablePreview: prepared.tablePreview, maxBytes, signal,
    assertAvailable});
}
