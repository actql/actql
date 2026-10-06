// Pure binding of an installed Effect's read inventory. This is preparation
// data, never an approval or a provider dispatch permit.
import {createHash} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';

export const EFFECT_TARGET_CONTINUATION = 'actql-effect-target-read-continuation/0.1';
const fail = () => { throw Object.assign(new Error('InvalidEffectTargetReadInventory'),
  {code: 'InvalidEffectTargetReadInventory'}); };
const text = value => typeof value === 'string' && value.length > 0 && value.length <= 512;
const freeze = value => {
  if (value !== null && typeof value === 'object') {
    for (const item of Object.values(value)) freeze(item);
    Object.freeze(value);
  }
  return value;
};

export function effectTargetReadInventory(inventory) {
  if (!Array.isArray(inventory) || inventory.length === 0 ||
      inventory.length > 1000) fail();
  const wire = canonicalValueJson(inventory, {dataKeys: true});
  if (Buffer.byteLength(wire) > 256 * 1024) fail();
  const groups = new Map();
  for (const item of JSON.parse(wire)) {
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
      group = {index: groups.size, readTuple: tuple, physicalBindings: []};
      groups.set(key, group);
    }
    group.physicalBindings.push(item.physicalBinding);
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
  authorityScopeCid, principalId, inventoryCid, target}) {
  return freeze({version: 'actql-effect-target-read-scope/0.1',
    run_definition_cid: runDefinitionCid, unit_id: unitId,
    authority_scope_cid: authorityScopeCid, principal_id: principalId,
    inventory_cid: inventoryCid, target});
}
