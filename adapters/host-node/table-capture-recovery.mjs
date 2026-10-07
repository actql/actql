// Table-specific projections under the existing capture, Store and Effect
// owners. This module neither recreates Compute nor grants approval/send rights.
import {prepareCompletedEffectfulPublication, confirmCompletedEffectfulApplySources}
  from '../host-common/completed-run-publication.mjs';
import {readRecoveredEffectTableInput} from './effect-input-export.mjs';

const owners = new WeakMap();
const fail = code => { throw Object.assign(new Error(code), {code}); };
const exactKeys = (value, fields) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join() === fields.slice().sort().join();

export function capturedTableRecoveryRecord({control, tableInput, tablePreview}) {
  const binding = control.tablePreviewLedgerBinding(tablePreview);
  if (binding.operationWire !== tableInput.wire) fail('ForeignTableRecoveryInput');
  const mappingWire = control.tableInputStorageMappingWire(tableInput);
  return Object.freeze({memberIndex: binding.memberIndex, kind: 'table_commit',
    observationCid: JSON.parse(binding.operationWire).request_cid,
    wire: JSON.stringify({mapping_wire: mappingWire, operation_wire: binding.operationWire})});
}

export async function prepareRecoveredTableInput({recovered, store, control,
  memberIndex, requestScope, contractLimits, tableLimits, signal}) {
  signal?.throwIfAborted();
  const inventory = prepareCompletedEffectfulPublication({execution: null,
    store, control, storedResults: recovered.storedResults,
    computation: recovered.computation, preview: recovered.preview});
  const source = inventory.effectSourceMembers.find(value => value.memberIndex === memberIndex);
  const records = recovered.connectorRecovery.filter(value => value.memberIndex === memberIndex);
  if (source === undefined || records.length !== 1 || records[0].kind !== 'table_commit') {
    fail('MissingTableRecoveryMaterial');
  }
  const saved = JSON.parse(records[0].wire);
  if (!exactKeys(saved, ['mapping_wire', 'operation_wire']) ||
      typeof saved.mapping_wire !== 'string' || typeof saved.operation_wire !== 'string') {
    fail('InvalidTableRecoveryMaterial');
  }
  const tablePreview = control.bindRecoveredTablePreview(inventory.preview, memberIndex,
    inventory.chain.invocation, source.source, inventory.chain.capturedRun,
    requestScope, saved.mapping_wire, store.storeAuthorityCid, contractLimits, tableLimits);
  if (tablePreview.operationWire !== saved.operation_wire ||
      records[0].observationCid !== JSON.parse(tablePreview.operationWire).request_cid) {
    fail('ForeignTableRecoveryOperation');
  }
  await confirmCompletedEffectfulApplySources({store, control,
    computation: recovered.computation, preview: recovered.preview});
  prepareCompletedEffectfulPublication({execution: null, store, control,
    storedResults: recovered.storedResults, computation: recovered.computation,
    preview: recovered.preview});
  signal?.throwIfAborted();
  const prepared = Object.freeze({tablePreview,
    operationWire: tablePreview.operationWire, mappingWire: tablePreview.mappingWire});
  owners.set(prepared, {recovered, store, control, source});
  return prepared;
}

export async function readRecoveredTableInput({prepared, maxBytes, signal}) {
  const owner = owners.get(prepared);
  if (owner === undefined) fail('ForeignRecoveredTableInput');
  const {recovered, store, control, source} = owner;
  // Recheck current owners and custody after awaits and before physical read.
  prepareCompletedEffectfulPublication({execution: null, store, control,
    storedResults: recovered.storedResults, computation: recovered.computation,
    preview: recovered.preview});
  await confirmCompletedEffectfulApplySources({store, control,
    computation: recovered.computation, preview: recovered.preview});
  const assertAvailable = () => prepareCompletedEffectfulPublication({execution: null,
    store, control, storedResults: recovered.storedResults,
    computation: recovered.computation, preview: recovered.preview});
  assertAvailable();
  return readRecoveredEffectTableInput({store, control, source: source.source,
    artifact: source.artifact, tablePreview: prepared.tablePreview, maxBytes, signal,
    assertAvailable});
}
