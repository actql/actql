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

// The same actual Local canonicalizer's scalar preflight. It constructs no
// normalized String, JSON token, body or CID before its caller reserves.
export function installedCanonicalTextConstructionShape(value) {
  return textShape(value);
}

// The existing Checkpoint binding has three fixed String fields per Source.
// Account admission later supplies two SHA256 CIDs (71 UTF16 units each), or
// the shorter null configuration. No prospective CID or body is constructed.
export function installedCheckpointBindingCanonicalConstructionGeometry(count, sourceOutput, sourceNormalized) {
  if ([count, sourceOutput, sourceNormalized].some(value => typeof value !== 'bigint' || value < 0n) ||
      sourceOutput < 2n * count) invalid();
  const keyUnits = BigInt('source_ref'.length + 'configuration_cid'.length + 'context_cid'.length);
  const outerKey = BigInt('source_authorization_bindings'.length);
  const leaves = sourceOutput + 2n * 73n * count;
  // Object braces, three quoted keys, colons and commas. Recursive counts
  // include the actual scalar tokens, row, Array and outer object once each.
  const rows = leaves + (keyUnits + 13n) * count;
  const array = 2n + rows + (count === 0n ? 0n : count - 1n);
  const output = array + outerKey + 5n;
  const measured = {nodes: 8n * count + 3n, output,
    recursive: leaves + rows + array + output,
    normalized: sourceNormalized + (2n * 71n + keyUnits) * count + outerKey};
  const workspace = zero();
  addCanonical(workspace, measured, 1n, 1n);
  return workspace;
}
function shape(value, parent = undefined, depth = 0) {
  if (depth > 256) invalid();
  let nodes = 1n, output, recursive = 0n, normalized = 0n, fields = 0n;
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
    fields = count;
  }
  return {nodes, output, recursive: recursive + output, normalized, fields};
}
function addCanonical(workspace, measured, calls = 1n, hashes = 0n) {
  // Object.entries/pairs/filter/replacement pairs+array, sort scratch, mapped
  // children and recursion frames. local-account-config has NO key Set.
  workspace.nodes += calls * 9n * measured.nodes + 4n * hashes;
  workspace.text += calls * 2n * (3n * measured.recursive + 2n * measured.output + measured.normalized) +
    hashes * 2n * (64n + 71n);
  workspace.wire += hashes * (3n * measured.output + 128n);
}

// The composer invokes these synchronous canonical/hash constructors in
// sequence. Their returned keys/CIDs may coexist; their private entries,
// sorting, recursive text and hash buffers do not survive each return.
function addSequentialCanonical(workspace, largest, measured, calls = 1n, hashes = 0n) {
  const current = zero();
  addCanonical(current, measured, 1n, hashes === 0n ? 0n : 1n);
  for (const field of ['nodes', 'text', 'wire']) {
    if (current[field] > largest[field]) largest[field] = current[field];
  }
  // Conservatively keep ALL complete returned encodings, even those consumed
  // by hashing or released selector/dedup Maps. No coalescing discounts them.
  workspace.text += 2n * calls * measured.output + 2n * hashes * (64n + 71n);
  workspace.nodes += 4n * hashes;
}

/** Before the one actual JSON.parse and recursive freeze, including a partial
 * malformed parse, decoder backing, Object.values arrays/slots and frames.
 * The borrowed String is not copied here. No admission or validity is inferred. */
export function installedEnvironmentParseConstructionGeometry(originalWire) {
  const input = sourceJsonWireGeometry(originalWire);
  // Native JSON.parse does not parse detached JSON text inside String values.
  // The existing same-wire scan separately bounds the actual returned tree;
  // all text and malformed-prefix decoding remain in the byte/text envelope.
  const nodes = input.retained.nodes;
  // Census record plus fifteen scalar fields; parsed result plus two fields.
  // The same funded freeze traversal computes these counts, with no extra parse.
  return stage({nodes: nodes + 19n, text: 2n * input.units, wire: 0n},
    {nodes: 5n * nodes + 4n, text: 10n * input.units, wire: 0n},
    {inputUnits: input.units, inputNodes: nodes});
}

// Observe this already-owned immutable graph once. These two synchronous
// native constructors have separate actual returns: the full-wire comparison
// retains only the original document reference; the body/CID phase retains a
// shallow root and result/index records, borrowing the same parsed children.
// Source's existing native-input owner reconciles each actual closed phase.
export function installedEnvironmentDocumentConstructionStages(frozenDocument) {
  const measured = shape(frozenDocument), comparison = zero(), body = zero();
  addCanonical(comparison, measured);
  addCanonical(body, measured, 1n, 1n);
  return Object.freeze({
    comparison: stage({nodes: 2n, text: 0n, wire: 0n}, comparison),
    body: stage({nodes: measured.fields + 20n, text: 2n * 71n, wire: 0n}, body),
  });
}

// The existing SDK writer uses dataKeys:true: it checks text and numbers but
// does not normalize keys or values. Measure that ACTUAL writer, including
// parent entries and completed sibling encodings while one child recurses.
// The original frozen graph is borrowed; no encoding is constructed here.
function dataWriterShape(value, depth = 0) {
  if (depth > 256) invalid();
  let output, peakNodes = 4n, peakText = 0n;
  const text = value => {
    let units = 2n;
    for (let i = 0; i < value.length; i++) {
      const code = value.charCodeAt(i);
      units += code === 34 || code === 92 || code === 8 || code === 9 ||
        code === 10 || code === 12 || code === 13 ? 2n : code < 32 ? 6n : 1n;
    }
    return units;
  };
  if (value === null) output = 4n;
  else if (typeof value === 'boolean') output = value ? 4n : 5n;
  else if (typeof value === 'number') output = 25n;
  else if (typeof value === 'string') output = text(value);
  else {
    if (typeof value !== 'object' || nodeTypes.isProxy(value) || !Object.isFrozen(value)) invalid();
    const array = Array.isArray(value);
    if (Object.getPrototypeOf(value) !== (array ? Array.prototype : Object.prototype)) invalid();
    let fields = 0n, largestNodes = 0n, largestText = 0n;
    output = 2n;
    for (const key of Reflect.ownKeys(value)) {
      if (array && key === 'length') continue;
      const property = Object.getOwnPropertyDescriptor(value, key);
      if (typeof key !== 'string' || !property || !Object.hasOwn(property, 'value') || !property.enumerable) invalid();
      if (property.value === undefined && !array) continue;
      const child = dataWriterShape(property.value, depth + 1);
      if (fields > 0n) output++;
      if (!array) output += text(key) + 1n;
      output += child.output; fields++;
      if (child.peakNodes > largestNodes) largestNodes = child.peakNodes;
      if (child.peakText > largestText) largestText = child.peakText;
    }
    // Conservatively coexist all entries/pairs/filter/replacement/key/Set/
    // sort/map arrays at this level, plus the largest active child. Earlier
    // sibling constructor workspaces have returned; their texts remain below.
    peakNodes = (array ? fields + 4n : 12n * fields + 16n) + largestNodes;
    peakText = 6n * output + largestText;
  }
  if (2n * output > peakText) peakText = 2n * output;
  return {output, peakNodes, peakText};
}

export function installedEnvironmentDataWriterConstructionGeometry(original, hash = false) {
  const measured = dataWriterShape(original);
  return stage({nodes: hash ? 4n : 48n, text: hash ? 2n * 71n : 2n * measured.output, wire: 0n},
    {nodes: measured.peakNodes + 8n, text: measured.peakText + (hash ? 2n * 135n : 0n),
      wire: hash ? 3n * measured.output + 128n : 0n});
}

export function installedEnvironmentMemberSortConstructionGeometry(originals) {
  let nodes = 0n, text = 0n, wire = 0n;
  for (const original of originals) {
    const measured = installedEnvironmentDataWriterConstructionGeometry(original, true);
    if (measured.nodes > nodes) nodes = measured.nodes;
    if (measured.text > text) text = measured.text;
    if (measured.wire > wire) wire = measured.wire;
  }
  return stage({nodes: 2n, text: 0n, wire: 0n},
    {nodes: nodes + BigInt(originals.length) + 4n, text: text + 2n * 71n, wire});
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
  const base = shape(frozenBaseBody), workspace = zero(), canonical = zero();
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
    if (basePolicy !== undefined) addSequentialCanonical(workspace, canonical, shape(basePolicy));
    const policy = own(body, 'host_policy_profile');
    if (policy !== undefined) addSequentialCanonical(workspace, canonical, shape(policy));
    if (frozenSourceBody === undefined || frozenEffectBody === undefined) continue;
    for (const section of sections) {
      const values = own(body, section);
      if (!Array.isArray(values)) continue; // semantic validation refuses before merge
      for (let index = 0; index < values.length; index++) {
        const member = own(values, String(index)), measured = shape(member);
        // Selector conflict canonicalization (at most once), dedup canonical
        // key, and CID sort hash. Count all3 even sections without selectors.
        addSequentialCanonical(workspace, canonical, measured, 3n, 1n);
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
      addSequentialCanonical(workspace, canonical, measured, 3n, measured.nodes);
      manifestNodes += measured.nodes; memberNodes += measured.nodes;
      memberOutput += measured.output; memberRecursive += measured.recursive;
      memberNormalized += measured.normalized;
    }
  }
  if (frozenSourceBody === undefined || frozenEffectBody === undefined) {
    for (const field of ['nodes', 'text', 'wire']) workspace[field] += canonical[field];
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
  addSequentialCanonical(workspace, canonical, merged, 1n, 1n);
  addSequentialCanonical(workspace, canonical, envelope);
  // Spread arrays, Maps/entries, retained-values arrays, sort records/CIDs,
  // map results, selector Maps and all callback/control/freeze frame overlap.
  workspace.nodes += 24n * (members + manifestNodes) + 6n * merged.nodes + 64n;
  workspace.text += 2n * 71n * members;
  workspace.nodes += 4n; // Three original references and their temporary array.
  for (const field of ['nodes', 'text', 'wire']) workspace[field] += canonical[field];
  return stage({// New merged census (record +14 fields), pre-admission candidate (record
    // +4 fields), and original index (record +4 fields +entry) coexist.
    // Scoped range/finish/release closures, six range/phase scalars, original
    // retirement fields and up to nine input/three provider rollback slots.
    nodes: base.nodes + 3n * members + manifestNodes + 48n + 26n + 40n,
    text: 2n * (envelope.output + 71n), wire: 0n}, workspace,
    {merged: true, members, mergedWireUnits: envelope.output, nativeAdmissionIncluded: false});
}
