// Private Host constructor geometry, not a new Resource or an admission.
// These stages use the existing Source metadata reader and its original
// initialization material. Native publication/Catalog/Mapping admission is
// deliberately outside these Host snapshot and identity quantities.
import {types} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {aliasRequestGeometry} from './source-alias-request.mjs';

const invalid = () => {throw new TypeError('InvalidSourceAliasConstruction');};
const stage = (retained, workspace, bounds) => ({
  nodes: retained.nodes + workspace.nodes,
  text: retained.text + workspace.text,
  wire: retained.wire + workspace.wire,
  retained, workspace, bounds,
});
const ownMethod = (owner, name) => {
  if (owner === null || typeof owner !== 'object' || types.isProxy(owner)) invalid();
  const field = Object.getOwnPropertyDescriptor(owner, name);
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
      types.isProxy(field.value) || types.isAsyncFunction(field.value)) invalid();
  return field.value;
};

// Capture originals before the profile read awaits. A quote never creates a
// reader, changes its material, or grants a caller a construction capability.
export function captureSourceAliasConstruction(configurationReader, moon) {
  if (configurationReader === undefined) return (_geometry, project) => project();
  const prepare = ownMethod(configurationReader, 'prepareNativeInput');
  const quote = ownMethod(moon, 'clientProgramInstalledSourceConstructionCapacity');
  return (geometry, project) => {
    const {retained, workspace} = geometry;
    const projection = Object.freeze({
      capacity() {
        return checked(Reflect.apply(quote, moon, [retained.nodes, retained.text,
          retained.wire, workspace.nodes, workspace.text, workspace.wire]));
      },
      project,
    });
    return Reflect.apply(prepare, configurationReader, [projection]);
  };
}

// Only an already owned immutable DATA graph may cross the quote callback.
// In particular a mutable caller request cannot change under liveness checks
// between geometry and the funded projection. This scan emits no JSON text.
function jsonStringBytes(value) {
  let bytes = 2n;
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code === 34 || code === 92 || code === 8 || code === 9 || code === 10 || code === 12 || code === 13) bytes += 2n;
    else if (code < 32) bytes += 6n;
    else if (code < 128) bytes++;
    else if (code < 2048) bytes += 2n;
    else if (code >= 0xd800 && code <= 0xdbff) {bytes += 4n; index++;}
    else bytes += 3n;
  }
  return bytes;
}

export function sourceAliasDataGeometry(value) {
  let nodes = 0n, entries = 0n, units = 0n, weighted = 0n, depth = 0n, jsonBytes = 0n;
  const ancestors = [];
  function visit(item, level) {
    nodes++;
    if (level > depth) depth = level;
    if (item === null || typeof item === 'boolean') {
      jsonBytes += item === false ? 5n : 4n; return;
    }
    if (typeof item === 'number') {
      if (!Number.isFinite(item) || Object.is(item, -0)) invalid();
      // A finite JS numeric token has at most 25 units. This bounded scalar
      // conversion is not a serialization or copy of the request tree.
      jsonBytes += BigInt(String(item).length); return;
    }
    if (typeof item === 'string') {
      if (!item.isWellFormed()) invalid();
      units += BigInt(item.length); weighted += BigInt(item.length) * (level + 1n);
      jsonBytes += jsonStringBytes(item);
      return;
    }
    if (typeof item !== 'object' || types.isProxy(item) || !Object.isFrozen(item) ||
        ancestors.includes(item) || (!Array.isArray(item) &&
          Object.getPrototypeOf(item) !== Object.prototype && Object.getPrototypeOf(item) !== null)) invalid();
    ancestors.push(item);
    const keys = Reflect.ownKeys(item);
    jsonBytes += 2n; let members = 0n;
    for (const key of keys) {
      if (Array.isArray(item) && key === 'length') continue;
      if (typeof key !== 'string' || !key.isWellFormed()) invalid();
      const field = Object.getOwnPropertyDescriptor(item, key);
      if (!field || !Object.hasOwn(field, 'value') || !field.enumerable) invalid();
      if (Array.isArray(item) && (!/^(0|[1-9][0-9]*)$/u.test(key) || Number(key) >= item.length)) invalid();
      entries++;
      if (members++ !== 0n) jsonBytes++;
      if (!Array.isArray(item)) {
        jsonBytes += jsonStringBytes(key) + 1n;
        units += BigInt(key.length); weighted += BigInt(key.length) * (level + 1n);
      }
      visit(field.value, level + 1n);
    }
    if (Array.isArray(item) && keys.length !== item.length + 1) invalid();
    ancestors.pop();
  }
  visit(value, 0n);
  return {nodes, entries, units, weighted, depth, jsonBytes};
}

const aliasIdentityDomain = 'actql-installed-query-alias-generation/0.1';
export function sourceAliasIdentityConstructionGeometry(aliases) {
  if (!Array.isArray(aliases)) invalid();
  const input = sourceAliasDataGeometry(aliases);
  const {nodes: n, entries: e, units: u, weighted, depth} = input;
  const count = BigInt(aliases.length);
  const identityWireUnits = 6n * u + 25n * n + BigInt(aliasIdentityDomain.length) + 7n;
  // Keep the existing provider identity vectors. A profile containing aliases
  // also canonicalizes them before the separate exact-DATA row preimage. NFC
  // can expand one UTF16 unit to at most three in canonical decomposition;
  // recomposition does not increase that bound. One enclosing profile level
  // contributes to the recursive text overlap, without normalizing the exact
  // alias identity row itself.
  const canonicalOutputUnits = 18n * u + 25n * n;
  const recursiveUnits = 18n * (weighted + u) + 25n * n * (depth + 2n);
  const entryArrays = n + e, originalPairs = e, filtered = n + e;
  const normalizedPairs = e, replacementArrays = n + e, sort = e;
  const children = n + e, frames = n;
  const identityRows = 1n + count + count + 5n * count;
  const identityEnvelope = 3n, serializerFrames = n, hashControls = 4n;
  return stage({nodes: 2n, text: 2n * 71n, wire: 0n}, {
    nodes: entryArrays + originalPairs + filtered + normalizedPairs + replacementArrays +
      sort + children + frames + identityRows + identityEnvelope + serializerFrames + hashControls,
    // Canonical normalization, recursive child/join/wrapper Strings, both
    // final preimages/builders, digest hex/prefix and decimal length prefixes.
    text: 2n * (3n * u + 3n * recursiveUnits + 2n * canonicalOutputUnits +
      2n * identityWireUnits + 64n + 71n + 40n),
    // UTF8 input backing plus SHA256 state/block/digest. Existing provider
    // metadata outside the alias subtree remains its original reader's duty.
    wire: 3n * (canonicalOutputUnits + identityWireUnits) + 128n,
  }, {input, identityWireUnits, canonicalOutputUnits});
}

// Validate borrowed metadata without invoking getters, proxies, toJSON or
// caller methods. Immutability is DATA stability, not Source authority: only
// the caller's already original reader supplies construction funding.
export function sourceAliasBorrowedGeometry(aliases) {
  if (!Array.isArray(aliases) || types.isProxy(aliases) || !Object.isFrozen(aliases) || aliases.length > 1024) invalid();
  for (let index = 0; index < aliases.length; index++) {
    const element = Object.getOwnPropertyDescriptor(aliases, String(index));
    if (!element || !Object.hasOwn(element, 'value')) invalid();
    const entry = element.value;
    if (entry === null || typeof entry !== 'object' || types.isProxy(entry) || !Object.isFrozen(entry) ||
        Array.isArray(entry) || Object.getPrototypeOf(entry) !== Object.prototype) invalid();
    const keys = Reflect.ownKeys(entry);
    const request = Object.hasOwn(entry, 'request');
    if (keys.length !== (request ? 5 : 4)) invalid();
    for (const key of keys) {
      if (!['name', 'sourceRef', 'sourceViewContractCid', 'schemaContractCid', 'request'].includes(key)) invalid();
      const field = Object.getOwnPropertyDescriptor(entry, key);
      if (!field || !Object.hasOwn(field, 'value') || !field.enumerable) invalid();
    }
    if (!['name', 'sourceRef', 'sourceViewContractCid', 'schemaContractCid'].every(name =>
          Object.hasOwn(entry, name) && typeof entry[name] === 'string') ||
        entry.name.length === 0 || entry.name.length > 1024 ||
        entry.sourceRef.length === 0 || entry.sourceRef.length > 4096 ||
        !/^sha256:[0-9a-f]{64}$/u.test(entry.sourceViewContractCid) ||
        !/^sha256:[0-9a-f]{64}$/u.test(entry.schemaContractCid)) invalid();
    // Enforce the same depth/node/text/direct-slot limits before the generic
    // immutable scan. Frozen manual DATA never bypasses snapshot semantics.
    if (request) aliasRequestGeometry(entry.request);
  }
  const input = sourceAliasDataGeometry(aliases);
  if (input.jsonBytes > 1024n * 1024n) throw new TypeError('InvalidPublicSourcePublication');
  return input;
}

// All per-Source request trees are borrowed from their one installed profile
// snapshot. Only the aggregate outer array and duplicate-name collections are
// new here. The source inventory itself is already owned and frozen in place.
export function sourceAliasCollectionConstructionGeometry(sources) {
  if (!Array.isArray(sources) || types.isProxy(sources) || !Object.isFrozen(sources)) invalid();
  let count = 0n, bytes = 2n, groups = 0n;
  for (let index = 0; index < sources.length; index++) {
    const element = Object.getOwnPropertyDescriptor(sources, String(index));
    if (!element || !Object.hasOwn(element, 'value')) invalid();
    const source = element.value;
    if (source === null || typeof source !== 'object' || types.isProxy(source) || !Object.isFrozen(source)) invalid();
    const field = Object.getOwnPropertyDescriptor(source, 'queryAliases');
    if (!field || !Object.hasOwn(field, 'value')) invalid();
    const input = sourceAliasBorrowedGeometry(field.value);
    count += BigInt(field.value.length);
    if (field.value.length !== 0) {
      bytes += input.jsonBytes - 2n + (groups++ === 0n ? 0n : 1n);
    }
  }
  if (count > 1024n || bytes > 1024n * 1024n) throw new TypeError('InvalidPublicSourcePublication');
  const aliases = 1n + count, result = 2n;
  const names = 1n + count, duplicateSet = 1n + count;
  const iterators = 2n + BigInt(sources.length);
  return stage({nodes: aliases + result, text: 0n, wire: 0n},
    {nodes: names + duplicateSet + iterators, text: 0n, wire: 0n}, {aliasCount: count});
}
