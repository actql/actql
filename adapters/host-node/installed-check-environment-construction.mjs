// Construction DATA for the central installed Environment composer. This is
// exclusively JS inventory. Native CheckEnvironment/Catalog admission requires
// its separate original Core recipe; these numbers never fund native work.
import {types as nodeTypes} from 'node:util';
import {sourceJsonWireGeometry} from './installed-source-construction-geometry.mjs';

const invalid = () => {throw new TypeError('InvalidInstalledEnvironmentConstructionGeometry');};
const zero = () => ({nodes: 0n, text: 0n, wire: 0n});
const stage = (retained, workspace, bounds = {}) => ({
  nodes: retained.nodes + workspace.nodes, text: retained.text + workspace.text,
  wire: retained.wire + workspace.wire, retained, workspace, bounds,
});
const sections = Object.freeze(['command_contracts', 'connector_capabilities',
  'connector_catalogs', 'contract_registry', 'mapping_contracts',
  'model_task_contracts', 'schema_snapshots', 'source_views']);
const own = (value, name) => {
  if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
      !Object.isFrozen(value)) invalid();
  const property = Object.getOwnPropertyDescriptor(value, name);
  if (property === undefined) return undefined;
  if (!Object.hasOwn(property, 'value')) invalid();
  return property.value;
};

// NFC is performed by the ACTUAL canonical constructor, never by this quote.
// ASCII is invariant. For non-ASCII, the Unicode decomposition expansion
// ceiling of18 code points (including compatibility decomposition, larger than
// NFC needs) and two UTF16 units/code point bounds normalization backing.
// Six-unit JSON escapes bound its encoding. This conservative Unicode branch
// is separate from the exact ASCII scan, not a whole-wire byte multiplier.
function textShape(value) {
  if (typeof value !== 'string') invalid();
  let output = 2n, normalized = 0n;
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code >= 128) {output += 216n; normalized += 36n;}
    else {
      normalized++;
      output += code === 34 || code === 92 || code === 8 || code === 9 ||
        code === 10 || code === 12 || code === 13 ? 2n : code < 32 ? 6n : 1n;
    }
  }
  return {output, normalized};
}
function shape(value, parent = undefined, depth = 0) {
  if (depth > 256) invalid();
  let nodes = 1n, output, recursive = 0n, normalized = 0n;
  if (value === null) output = 4n;
  else if (typeof value === 'boolean') output = value ? 4n : 5n;
  else if (typeof value === 'number') output = 25n;
  else if (typeof value === 'string') ({output, normalized} = textShape(value));
  else {
    if (typeof value !== 'object' || nodeTypes.isProxy(value) || !Object.isFrozen(value)) invalid();
    const array = Array.isArray(value);
    if (Object.getPrototypeOf(value) !== (array ? Array.prototype : Object.prototype)) invalid();
    for (let frame = parent; frame !== undefined; frame = frame.parent) if (frame.value === value) invalid();
    const frame = {value, parent};
    output = 2n; let count = 0n;
    for (const key of Reflect.ownKeys(value)) {
      if (array && key === 'length') continue;
      if (typeof key !== 'string') invalid();
      const property = Object.getOwnPropertyDescriptor(value, key);
      if (!property || !Object.hasOwn(property, 'value') || !property.enumerable) invalid();
      if (array && (!/^(0|[1-9][0-9]*)$/.test(key) || Number(key) >= value.length)) invalid();
      if (!array && property.value === undefined) continue;
      const child = shape(property.value, frame, depth + 1);
      if (count > 0n) output++;
      if (!array) {const text = textShape(key); output += text.output + 1n; normalized += text.normalized;}
      output += child.output; recursive += child.recursive;
      nodes += child.nodes + 1n; normalized += child.normalized; count++;
    }
    if (array && count !== BigInt(value.length)) invalid();
  }
  return {nodes, output, recursive: recursive + output, normalized};
}
function addCanonical(workspace, measured, calls = 1n, hashes = 0n) {
  // Object.entries/pairs/filter/replacement pairs+array, sort scratch, mapped
  // children and recursion frames. local-account-config has NO key Set.
  workspace.nodes += calls * 9n * measured.nodes + 4n * hashes;
  workspace.text += calls * 2n * (3n * measured.recursive + 2n * measured.output + measured.normalized) +
    hashes * 2n * (64n + 71n);
  workspace.wire += hashes * (3n * measured.output + 128n);
}

/** Before the one actual JSON.parse and recursive freeze, including a partial
 * malformed parse, decoder backing, Object.values arrays/slots and frames.
 * The borrowed String is not copied here. No admission or validity is inferred. */
export function installedEnvironmentParseConstructionGeometry(originalWire) {
  const input = sourceJsonWireGeometry(originalWire);
  // Census record plus fourteen scalar fields; parsed result plus two fields.
  // The same funded freeze traversal computes these counts, with no extra parse.
  return stage({nodes: input.nodes + 18n, text: 2n * input.units, wire: 0n},
    {nodes: 5n * input.nodes + 4n, text: 10n * input.units, wire: 0n},
    {inputUnits: input.units, inputNodes: input.nodes});
}

/** After funded parse/freeze: canonical encoding comparison, shallow body
 * rest-spread removing evidence_bundle_cid, body CID hashing, retained record.
 * Whole document geometry safely bounds that smaller body without reconstructing
 * it in the quote. Native admission is NOT included, even if this JS stage runs
 * immediately before it. Both verification calls/failure prefixes coexist. */
export function installedEnvironmentDocumentConstructionGeometry(frozenDocument) {
  const measured = shape(frozenDocument), workspace = zero();
  addCanonical(workspace, measured, 2n, 1n);
  workspace.nodes += 3n * measured.nodes + 12n;
  // The nominal original index retains one four-field record and one entry.
  return stage({nodes: measured.nodes + 8n + 6n, text: 2n * 71n, wire: 0n}, workspace,
    {canonicalWireUnits: measured.output, nativeAdmissionIncluded: false});
}

/** Receives exact already-owned frozen bodies, with evidence CID removed.
 * Nominal issuer/runtime checks and complete semantic admission belong to the
 * caller. No object or String equality grants reuse here. Every invocation
 * sums actual member work, even equal bodies shared by Source and Effect.
 * Native admission of a NEW merged output is a later separate stage. */
export function installedEnvironmentCompositionConstructionGeometry(
  frozenBaseBody, frozenSourceBody = undefined, frozenEffectBody = undefined,
) {
  const base = shape(frozenBaseBody), workspace = zero();
  // Allowed-key Set, keys/validation arrays, body/member wrappers and control.
  workspace.nodes += 4n * base.nodes + 16n;
  const basePolicy = own(frozenBaseBody, 'host_policy_profile');
  let members = 0n, memberNodes = 0n, memberOutput = 0n, memberRecursive = 0n;
  let memberNormalized = 0n, manifestNodes = 0n;
  for (const body of [frozenSourceBody, frozenEffectBody]) {
    if (body === undefined) continue;
    const bodyShape = shape(body);
    workspace.nodes += 3n * bodyShape.nodes + 8n;
    // Original validation canonicalizes both policy bodies per supplied input.
    if (basePolicy !== undefined) addCanonical(workspace, shape(basePolicy));
    const policy = own(body, 'host_policy_profile');
    if (policy !== undefined) addCanonical(workspace, shape(policy));
    if (frozenSourceBody === undefined || frozenEffectBody === undefined) continue;
    for (const section of sections) {
      const values = own(body, section);
      if (!Array.isArray(values)) continue; // semantic validation refuses before merge
      for (let index = 0; index < values.length; index++) {
        const member = own(values, String(index)), measured = shape(member);
        // Selector conflict canonicalization (at most once), dedup canonical
        // key, and CID sort hash. Count all3 even sections without selectors.
        addCanonical(workspace, measured, 3n, 1n);
        members++; memberNodes += measured.nodes; memberOutput += measured.output;
        memberRecursive += measured.recursive; memberNormalized += measured.normalized;
        // Composite source_ref + NUL + read_mode selector may retain text.
        workspace.text += 2n * (measured.output + 1n);
      }
    }
    const manifest = own(body, 'connector_manifest');
    if (manifest !== undefined) {
      const measured = shape(manifest);
      // Conflict/dedup/sort families for its connectors; whole manifest bounds
      // the disjoint connector forest, with fixed version/array vocabulary.
      addCanonical(workspace, measured, 3n, measured.nodes);
      manifestNodes += measured.nodes; memberNodes += measured.nodes;
      memberOutput += measured.output; memberRecursive += measured.recursive;
      memberNormalized += measured.normalized;
    }
  }
  if (frozenSourceBody === undefined || frozenEffectBody === undefined) {
    return stage({nodes: 2n + 40n, text: 0n, wire: 0n}, workspace,
      {merged: false, nativeAdmissionIncluded: false});
  }
  // Keep every member as an upper bound: equal-body coalescing never reduces
  // the quote. Base fields remain, plus section arrays and optional manifest.
  const output = base.output + memberOutput + 4n * members + 512n;
  const merged = {nodes: base.nodes + memberNodes + 2n * members + 32n,
    output, recursive: base.recursive + memberRecursive + 4n * output,
    normalized: base.normalized + memberNormalized};
  // Merged body hash and final {..body,evidence_bundle_cid} canonical encoding.
  const envelope = {...merged, nodes: merged.nodes + 2n, output: output + 100n,
    recursive: merged.recursive + 100n, normalized: merged.normalized + 96n};
  addCanonical(workspace, merged, 1n, 1n);
  addCanonical(workspace, envelope);
  // Spread arrays, Maps/entries, retained-values arrays, sort records/CIDs,
  // map results, selector Maps and all callback/control/freeze frame overlap.
  workspace.nodes += 24n * (members + manifestNodes) + 6n * merged.nodes + 64n;
  workspace.text += 2n * 71n * members;
  workspace.nodes += 4n; // Three original references and their temporary array.
  return stage({// New merged census (record +14 fields), pre-admission candidate (record
    // +4 fields), and original index (record +4 fields +entry) coexist.
    // Scoped range/finish/release closures, six range/phase scalars, original
    // retirement fields and up to nine input/three provider rollback slots.
    nodes: base.nodes + 3n * members + manifestNodes + 48n + 26n + 40n,
    text: 2n * (envelope.output + 71n), wire: 0n}, workspace,
    {merged: true, members, mergedWireUnits: envelope.output, nativeAdmissionIncluded: false});
}
