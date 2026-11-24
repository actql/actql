// Private Host constructor geometry, not a new Resource or an admission.
// These stages use the existing Source metadata reader and its original
// initialization material. Native publication/Catalog/Mapping admission is
// deliberately outside these Host snapshot and identity quantities.
import {types} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {aliasRequestGeometry} from './source-alias-request.mjs';
import {installedCheckpointBindingCanonicalConstructionGeometry}
  from './installed-check-environment-construction.mjs';
import type {installedCanonicalTextConstructionShape} from './installed-check-environment-construction.mjs';

type Extent = ReturnType<typeof installedCheckpointBindingCanonicalConstructionGeometry>;
type Geometry = Readonly<{retained: Readonly<Extent>; workspace: Readonly<Extent>}>;
type CanonicalInput = Readonly<{nodes: bigint; entries: bigint; units: bigint; weighted: bigint; depth: bigint}>;
type NamespaceEntry = Readonly<{facts: Readonly<{aliases: readonly unknown[]}>}>;
type SourceValue = Extract<SynchronousRuntimeData, object>;
type NativeInputProjection<Result extends SourceValue> = Readonly<{
  capacity(): unknown;
  project(): Result;
}>;
export type ConfigurationReader = Readonly<{
  prepareNativeInput<Result extends SourceValue>(projection: NativeInputProjection<Result>): Result;
}>;

const invalid: () => never = () => {throw new TypeError('InvalidSourceAliasConstruction');};
const stage = <Bounds,>(retained: Extent, workspace: Extent, bounds: Bounds) => ({
  nodes: retained.nodes + workspace.nodes,
  text: retained.text + workspace.text,
  wire: retained.wire + workspace.wire,
  retained, workspace, bounds,
});
const ownMethod = (owner: unknown, name: string): (...args: unknown[]) => unknown => {
  if (owner === null || typeof owner !== 'object' || types.isProxy(owner)) invalid();
  const field = Object.getOwnPropertyDescriptor(owner, name);
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
      types.isProxy(field.value) || types.isAsyncFunction(field.value)) invalid();
  return field.value;
};
// Capture originals before the profile read awaits. A quote never creates a
// reader, changes its material, or grants a caller a construction capability.
export function captureSourceAliasConstruction(configurationReader: undefined, moon: unknown):
  <Result>(geometry: Geometry | undefined, project: () => Result) => Result;
export function captureSourceAliasConstruction(configurationReader: ConfigurationReader, moon: unknown):
  <Result extends SourceValue>(geometry: Geometry, project: () => Result) => Result;
export function captureSourceAliasConstruction(configurationReader: ConfigurationReader | undefined, moon: unknown):
  <Result extends SourceValue>(geometry: Geometry, project: () => Result) => Result;
export function captureSourceAliasConstruction(configurationReader: ConfigurationReader | undefined, moon: unknown) {
  if (configurationReader === undefined) return (_geometry: Geometry | undefined, project: () => unknown) => project();
  const prepare = ownMethod(configurationReader, 'prepareNativeInput') as ConfigurationReader['prepareNativeInput'];
  const quote = ownMethod(moon, 'clientProgramInstalledSourceConstructionCapacity');
  return <Result extends SourceValue>(geometry: Geometry, project: () => Result) => {
    const {retained, workspace} = geometry;
    const projection = Object.freeze({
      capacity() {
        return checked(Reflect.apply(quote, moon, [retained.nodes, retained.text,
          retained.wire, workspace.nodes, workspace.text, workspace.wire]));
      },
      project,
    });
    return Reflect.apply(prepare<Result>, configurationReader, [projection]);
  };
}

// The array and closed-member Set remain with this same initial Source
// material through bundle close. Keep one complete close-error array beside
// them; the fixed Host serializes its existing cleanup flight.
export function sourceMemberCollectionConstructionGeometry(count: bigint) {
  if (typeof count !== 'bigint' || count < 0n) invalid();
  return stage({nodes: 3n * count + 6n, text: 0n, wire: 0n},
    {nodes: 0n, text: 0n, wire: 0n}, {memberCount: count});
}

// Individual Sources retain their original read-access checks. This separate
// synchronous aggregate check owns only its Set and one returned record.
export function sourceReferenceCollectionConstructionGeometry(count: bigint) {
  if (typeof count !== 'bigint' || count < 0n) invalid();
  return stage({nodes: 1n, text: 0n, wire: 0n},
    {nodes: count + 1n, text: 0n, wire: 0n}, {referenceCount: count});
}

// Retain the unique connector Map and final exported array. Each comparison
// may overlap one current Map-values array; duplicate declarations still
// contribute to the complete observed upper extent, not a numeric ceiling.
export function sourceBindingCollectionConstructionGeometry(count: bigint) {
  if (typeof count !== 'bigint' || count < 0n) invalid();
  return stage({nodes: 3n * count + 2n, text: 0n, wire: 0n},
    {nodes: count + 1n, text: 0n, wire: 0n}, {bindingCount: count});
}

export function sourceRegistrationRangeConstructionGeometry(paths: bigint, sources: bigint) {
  if (typeof paths !== 'bigint' || paths < 0n || typeof sources !== 'bigint' || sources < 0n) invalid();
  return stage({nodes: 4n * sources + 3n, text: 0n, wire: 0n},
    {nodes: 3n * paths + 2n * sources + 6n, text: 0n, wire: 0n}, {registrationCount: sources});
}

// Only an already owned immutable DATA graph may cross the quote callback.
// In particular a mutable caller request cannot change under liveness checks
// between geometry and the funded projection. This scan emits no JSON text.
function jsonStringBytes(value: string) {
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

export function sourceAliasDataGeometry(value: unknown) {
  if (value !== null && typeof value === 'object') {
    if (types.isProxy(value) || !Object.isFrozen(value)) invalid();
  }
  let nodes = 0n, entries = 0n, units = 0n, weighted = 0n, depth = 0n, jsonBytes = 0n;
  const ancestors: object[] = [];
  function visit(item: unknown, level: bigint) {
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
  const result = Object.freeze({nodes, entries, units, weighted, depth, jsonBytes});
  return result;
}

const aliasIdentityDomain = 'actql-installed-query-alias-generation/0.1';
function canonicalSourceConstructionWorkspace(input: CanonicalInput) {
  const {nodes: n, entries: e, units: u, weighted, depth} = input;
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
  const serializerFrames = n, hashControls = 4n;
  return {
    nodes: entryArrays + originalPairs + filtered + normalizedPairs + replacementArrays +
      sort + children + frames + serializerFrames + hashControls,
    // Canonical normalization, recursive child/join/wrapper Strings, final
    // preimage/builders, digest hex/prefix and decimal length prefixes.
    text: 2n * (3n * u + 3n * recursiveUnits + 2n * canonicalOutputUnits +
      64n + 71n + 40n),
    wire: 3n * canonicalOutputUnits + 128n,
    canonicalOutputUnits,
  };
}

export function sourceNamespaceConstructionGeometry(range: readonly NamespaceEntry[], aliases: readonly unknown[], name: string, environmentCid: string, selector = false) {
  const headerKeys = 'version' + (selector ? 'namespace' : 'name') + 'environmentCid' + 'registrations';
  const version = selector ? 'actql-source-selector-namespace/0.1' : 'actql-source-namespace/0.1';
  const headerValues = BigInt(version.length + name.length + environmentCid.length);
  const input = {nodes: 5n, entries: 4n + BigInt(range.length),
    units: BigInt(headerKeys.length) + headerValues,
    weighted: BigInt(headerKeys.length) + 2n * headerValues, depth: 1n};
  let aliasCount = 0n;
  for (const item of range) {
    const facts = item.facts;
    const value = sourceAliasDataGeometry(facts);
    aliasCount += BigInt(facts.aliases.length);
    // Alias identity rows only remove object keys and borrow the same request
    // tree. Two copies cover its namespace preimage and equality comparison.
    const copies = selector ? 1n : 2n;
    input.nodes += copies * value.nodes; input.entries += copies * value.entries;
    input.units += copies * value.units;
    input.weighted += copies * (value.weighted + 2n * value.units);
    input.depth = input.depth > value.depth + 2n ? input.depth : value.depth + 2n;
  }
  if (selector) {
    // Selector identities replace the aliases field by the actual admitted
    // Environment CID; reserve its existing textual codec before that read.
    const extra = BigInt(range.length) * BigInt('environmentCid'.length + 71);
    input.units += extra; input.weighted += 4n * extra;
  } else {
    const compared = sourceAliasDataGeometry(aliases);
    input.nodes += compared.nodes; input.entries += compared.entries;
    input.units += compared.units; input.weighted += compared.weighted + 2n * compared.units;
    input.depth = input.depth > compared.depth + 2n ? input.depth : compared.depth + 2n;
    aliasCount += BigInt(aliases.length);
  }
  const canonical = canonicalSourceConstructionWorkspace(input);
  const count = BigInt(range.length);
  return stage({nodes: selector ? 6n * count + 6n : aliasCount + 5n, text: 71n, wire: 0n},
    {nodes: canonical.nodes + 10n * count + 15n * aliasCount + 10n,
      text: canonical.text, wire: canonical.wire}, {registrationCount: count});
}

export function sourceAliasIdentityConstructionGeometry(aliases: unknown) {
  if (!Array.isArray(aliases)) invalid();
  const input = sourceAliasDataGeometry(aliases);
  const count = BigInt(aliases.length);
  const identityWireUnits = 6n * input.units + 25n * input.nodes + BigInt(aliasIdentityDomain.length) + 7n;
  const canonical = canonicalSourceConstructionWorkspace(input);
  const identityRows = 1n + count + count + 5n * count, identityEnvelope = 3n;
  return stage({nodes: 2n, text: 2n * 71n, wire: 0n}, {
    nodes: canonical.nodes + identityRows + identityEnvelope,
    text: canonical.text + 4n * identityWireUnits,
    wire: canonical.wire + 3n * identityWireUnits,
  }, {input, identityWireUnits, canonicalOutputUnits: canonical.canonicalOutputUnits});
}

// Same Source material, before completion: prepare the actual configurations,
// gate slots and authorization-binding rows that Checkpoints consume later.
// The two CIDs per binding have their existing SHA256 textual extent (71),
// never a grant or an invented CID value. Account admission still issues them.
export function sourceCheckpointInventoryConstructionGeometry(count: bigint, sourceRefUnits: bigint, sourceRefShape?: ReturnType<typeof installedCanonicalTextConstructionShape>) {
  if (typeof count !== 'bigint' || count < 0n ||
      typeof sourceRefUnits !== 'bigint' || sourceRefUnits < 0n) invalid();
  const keyUnits = BigInt('source_ref'.length + 'configuration_cid'.length + 'context_cid'.length);
  const outerKey = BigInt('source_authorization_bindings'.length);
  const leafUnits = sourceRefUnits + 2n * 71n * count;
  const canonical = sourceRefShape === undefined ? canonicalSourceConstructionWorkspace({nodes: 4n * count + 2n,
    entries: 4n * count + 1n, units: leafUnits + keyUnits * count + outerKey,
    weighted: 4n * leafUnits + 3n * keyUnits * count + outerKey, depth: 3n})
    : installedCheckpointBindingCanonicalConstructionGeometry(count,
      sourceRefShape.output, sourceRefShape.normalized);
  // Five arrays, three fixed-width records per Source, result and borrow
  // record. The current connection Set/sort and later validation/sort occupy
  // separate phases under this same complete retained envelope.
  // Keep future validation array/Set, binding sort and canonical/hash overlap
  // in the retained reservation: Source completion precedes Checkpoint setup.
  // This debt stays until the actual Checkpoint -> Source close order retires
  // the same material; there is no post-completion growth or new Resource.
  return stage({nodes: 17n * count + 15n + 3n * count + 3n + canonical.nodes,
    text: canonical.text, wire: canonical.wire},
  {nodes: 0n, text: 0n, wire: 0n}, {sourceCount: count});
}

// Validate borrowed metadata without invoking getters, proxies, toJSON or
// caller methods. Immutability is DATA stability, not Source authority: only
// the caller's already original reader supplies construction funding.
export function sourceAliasBorrowedGeometry(aliases: unknown) {
  if (!Array.isArray(aliases) || types.isProxy(aliases) || !Object.isFrozen(aliases) || aliases.length > 1024) invalid();
  for (let index = 0; index < aliases.length; index++) {
    const element = Object.getOwnPropertyDescriptor(aliases, String(index));
    if (!element || !Object.hasOwn(element, 'value')) invalid();
    const entry = element.value as Readonly<Record<string, unknown>>;
    if (entry === null || typeof entry !== 'object' || types.isProxy(entry) || !Object.isFrozen(entry) ||
        Array.isArray(entry) || Object.getPrototypeOf(entry) !== Object.prototype) invalid();
    const keys = Reflect.ownKeys(entry);
    const request = Object.hasOwn(entry, 'request');
    if (keys.length !== (request ? 5 : 4)) invalid();
    for (const key of keys) {
      if (!['name', 'sourceRef', 'sourceViewContractCid', 'schemaContractCid', 'request'].includes(key as string)) invalid();
      const field = Object.getOwnPropertyDescriptor(entry, key);
      if (!field || !Object.hasOwn(field, 'value') || !field.enumerable) invalid();
    }
    if (!['name', 'sourceRef', 'sourceViewContractCid', 'schemaContractCid'].every(name =>
          Object.hasOwn(entry, name) && typeof entry[name] === 'string') ||
        (entry.name as string).length === 0 || (entry.name as string).length > 1024 ||
        (entry.sourceRef as string).length === 0 || (entry.sourceRef as string).length > 4096 ||
        !/^sha256:[0-9a-f]{64}$/u.test(entry.sourceViewContractCid as string) ||
        !/^sha256:[0-9a-f]{64}$/u.test(entry.schemaContractCid as string)) invalid();
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
export function sourceAliasCollectionConstructionGeometry(sources: unknown) {
  if (!Array.isArray(sources) || types.isProxy(sources) || !Object.isFrozen(sources)) invalid();
  let count = 0n, bytes = 2n, groups = 0n;
  for (let index = 0; index < sources.length; index++) {
    const element = Object.getOwnPropertyDescriptor(sources, String(index));
    if (!element || !Object.hasOwn(element, 'value')) invalid();
    const source: unknown = element.value;
    if (source === null || typeof source !== 'object' || types.isProxy(source) || !Object.isFrozen(source)) invalid();
    const field = Object.getOwnPropertyDescriptor(source, 'queryAliases');
    if (!field || !Object.hasOwn(field, 'value')) invalid();
    const input = sourceAliasBorrowedGeometry(field.value);
    count += BigInt((field.value as readonly unknown[]).length);
    if ((field.value as readonly unknown[]).length !== 0) {
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
