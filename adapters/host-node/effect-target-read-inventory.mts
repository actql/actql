// Pure binding of an installed Effect's read inventory. This is preparation
// data, never an approval or a provider dispatch permit.
import {createHash} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';

export type ReadTuple = Readonly<{connection: string; resource: string; operation: 'read'}>;
type PhysicalBinding = Readonly<Record<string, unknown> & {version: string}>;
export type EffectTarget = Readonly<{
  index: number; readTuple: ReadTuple; physicalBindings: readonly PhysicalBinding[];
}>;
type TargetGroup = Omit<EffectTarget, 'physicalBindings'> & {physicalBindings: PhysicalBinding[]};
type InventoryEntry = Readonly<{
  readTuple?: Partial<ReadTuple> | null; physicalBinding?: Record<string, unknown> | null;
}>;
type Scope = Readonly<{
  runDefinitionCid: string; unitId: string; authorityScopeCid: string;
  principalId: string; inventoryCid: string; target: EffectTarget;
}>;


export const EFFECT_TARGET_CONTINUATION = 'actql-effect-target-read-continuation/0.1';
const fail: () => never = () => { throw Object.assign(new Error('InvalidEffectTargetReadInventory'),
  {code: 'InvalidEffectTargetReadInventory'}); };
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 && value.length <= 512;
const freeze = <Value,>(value: Value): Value => {
  if (value !== null && typeof value === 'object') {
    for (const item of Object.values(value)) freeze(item);
    Object.freeze(value);
  }
  return value;
};

export function effectTargetReadInventory(inventory: unknown): Readonly<{targets: readonly EffectTarget[]; inventoryCid: string}> {
  if (!Array.isArray(inventory) || inventory.length === 0 ||
      inventory.length > 1000) fail();
  const wire = canonicalValueJson(inventory, {dataKeys: true});
  if (Buffer.byteLength(wire) > 256 * 1024) fail();
  const groups = new Map<string, TargetGroup>();
  for (const item of JSON.parse(wire) as readonly InventoryEntry[]) {
    const tuple = item?.readTuple;
    if (!text(tuple?.connection) || !text(tuple.resource) ||
        tuple.operation !== 'read' ||
        Object.keys(tuple).sort().join(',') !== 'connection,operation,resource' ||
        item.physicalBinding === null || typeof item.physicalBinding !== 'object' ||
        Array.isArray(item.physicalBinding) ||
        !text(item.physicalBinding.version)) fail();
    const key = canonicalValueJson(tuple);
    let group = groups.get(key);
    if (group === undefined) {
      group = {index: groups.size, readTuple: tuple as ReadTuple, physicalBindings: []};
      groups.set(key, group);
    }
    group.physicalBindings.push(item.physicalBinding as PhysicalBinding);
  }
  const targets = freeze([...groups.values()]);
  // The CID binds the same value-preserving preimage as the retained data.
  // Opaque provider bindings are not configuration identities.
  const preimage = canonicalValueJson({
    version: 'actql-effect-target-read-inventory/0.1', targets}, {dataKeys: true});
  return Object.freeze({targets, inventoryCid: `sha256:${createHash('sha256')
    .update(preimage, 'utf8').digest('hex')}`});
}

export function effectTargetReadScope({runDefinitionCid, unitId,
  authorityScopeCid, principalId, inventoryCid, target}: Scope) {
  return freeze({version: 'actql-effect-target-read-scope/0.1',
    run_definition_cid: runDefinitionCid, unit_id: unitId,
    authority_scope_cid: authorityScopeCid, principal_id: principalId,
    inventory_cid: inventoryCid, target} as const);
}
