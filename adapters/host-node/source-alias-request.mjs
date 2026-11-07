import {types} from 'node:util';

const invalid = () => {throw new TypeError('InvalidPublicSourcePublication');};
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

// Installation DATA only. This walk neither resolves a Source nor issues a
// binding. All collections and strings copied below have a bounded geometry
// before the snapshot constructor starts. The original must not contain hooks.
export function aliasRequestGeometry(request) {
  if (!object(request)) invalid();
  let nodes = 0n, entries = 0n, units = 0n, depth = 0n;
  const ancestors = [];
  function visit(value, level) {
    nodes++;
    if (nodes > 65536n || level > 64) invalid();
    if (BigInt(level) > depth) depth = BigInt(level);
    if (value === null || typeof value === 'boolean') return;
    if (typeof value === 'string') {
      if (!value.isWellFormed()) invalid();
      units += BigInt(value.length);
    } else if (typeof value === 'number') {
      if (!Number.isFinite(value) || Object.is(value, -0)) invalid();
    } else if (typeof value === 'object') {
      if (types.isProxy(value) || ancestors.includes(value) ||
          (!Array.isArray(value) && ![Object.prototype, null].includes(Object.getPrototypeOf(value)))) invalid();
      ancestors.push(value);
      const keys = Reflect.ownKeys(value);
      for (const key of keys) {
        if (Array.isArray(value) && key === 'length') continue;
        if (typeof key !== 'string' || !key.isWellFormed()) invalid();
        const field = Object.getOwnPropertyDescriptor(value, key);
        if (!field || !Object.hasOwn(field, 'value') || !field.enumerable) invalid();
        if (Array.isArray(value) && (!/^(0|[1-9][0-9]*)$/u.test(key) || Number(key) >= value.length)) invalid();
        entries++; units += BigInt(key.length);
        visit(field.value, level + 1);
      }
      if (Array.isArray(value) && keys.length !== value.length + 1) invalid();
      ancestors.pop();
    } else invalid();
    if (units > 1048576n) invalid();
  }
  visit(request, 0);
  // The Source request slot grammar interprets only these direct singleton
  // forms as references. They are not constant request DATA. Nested records
  // retain their ordinary business meaning.
  for (const key of Object.keys(request)) {
    const value = request[key];
    if (object(value)) {
      const keys = Object.keys(value);
      if (keys.length === 1 && (keys[0] === '$param' || keys[0] === '$binding')) invalid();
    }
  }
  return {nodes, entries, units, depth};
}

export function snapshotAliasRequest(request) {
  aliasRequestGeometry(request);
  function copy(value) {
    if (value === null || typeof value !== 'object') return value;
    if (Array.isArray(value)) return Object.freeze(value.map(copy));
    // Sorting gives exact JSON DATA identity independent of member insertion
    // order, without normalizing any user string or inserting absent fields.
    const result = {};
    for (const key of Object.keys(value).sort()) {
      Object.defineProperty(result, key, {value: copy(value[key]), enumerable: true});
    }
    return Object.freeze(result);
  }
  return copy(request);
}

export function sourceAliasIdentityRow(entry) {
  const row = [entry.name, entry.sourceRef, entry.sourceViewContractCid, entry.schemaContractCid];
  if (Object.hasOwn(entry, 'request')) row.push(entry.request);
  return row;
}
