// Private geometry of the existing synchronous Host constructors. These
// functions issue neither a Resource nor admission and never parse JSON.
import {types as nodeTypes} from 'node:util';
const invalid = () => {throw new TypeError('InvalidInstalledSourceConstructionGeometry');};

export function sourceJsonWireGeometry(wire, payloadOnly = false) {
  if (typeof wire !== 'string' || typeof payloadOnly !== 'boolean') invalid();
  let nodes = 1n, depth = 0n, maximum = 0n, weighted = 0n, units = 0n;
  let retainedNodes = 1n, retainedText = 0n;
  let quoted = false, escaped = false;
  for (let index = 0; index < wire.length; index++) {
    const code = wire.charCodeAt(index);
    // The SAME wire observation also bounds the one returned native JSON
    // tree. Punctuation/escapes inside a String are not retained value nodes.
    // Raw String payload bytes bound decoded UTF8 (escapes only contract);
    // treating each surrogate unit separately is conservative, never repair.
    if (quoted && (code !== 34 || escaped)) {
      retainedText += code < 128 ? 1n : code < 2048 ? 2n : 3n;
    } else if (!quoted) {
      if (code === 123 || code === 91) retainedNodes += 2n;
      else if (code === 58 || code === 44) retainedNodes++;
    }
    // Include punctuation inside strings and every escape. This also bounds
    // values hidden in detached JSON strings, without decoding those strings.
    if (code === 123 || code === 91) nodes += 2n;
    else if (code === 58 || code === 44 || code === 92) nodes++;
    if (!quoted && (code === 123 || code === 91)) {
      depth++;
      if (depth > maximum) maximum = depth;
    }
    // Only the Alias Profile constructor selects payload demand: its reader
    // already retains the whole wire. RFC JSON whitespace outside a String
    // produces no parsed/snapshot/escaped String. Every inside-String unit,
    // escape and non-whitespace token still contributes before JSON.parse.
    if (!payloadOnly || quoted || code !== 32 && code !== 9 && code !== 10 && code !== 13) {
      weighted += depth + 1n;
      if (payloadOnly) units++;
    }
    if (quoted) {
      if (escaped) escaped = false;
      else if (code === 92) escaped = true;
      else if (code === 34) quoted = false;
    } else if (code === 34) quoted = true;
    else if ((code === 125 || code === 93) && depth > 0n) depth--;
  }
  return {nodes, units: payloadOnly ? units : BigInt(wire.length), weighted, depth: maximum,
    retained: {nodes: retainedNodes, text: retainedText, wire: 0n}};
}

// Literal wrapper vocabulary added by rowSourceCheckEnvironment. Include
// optional members even when absent; input base fields are counted separately.
const environmentEnvelope = '{"schema_snapshots":[],"connector_capabilities":[],"source_views":[],"contract_registry":[],"connector_catalogs":[],"connector_manifest":{"version":"actql-connectors/0.1","connectors":[]},"mapping_contracts":[],"command_contracts":[],"evidence_bundle_cid":"sha256:' + '0'.repeat(64) + '"}';
export function sourceEnvironmentConstructionGeometry(baseWire, declared, mappings = []) {
  const base = sourceJsonWireGeometry(baseWire);
  let nodes = base.nodes, units = base.units, weighted = base.weighted;
  let depth = base.depth, members = 0n;
  const add = wire => {
    const measured = sourceJsonWireGeometry(wire);
    nodes += measured.nodes; units += measured.units; weighted += measured.weighted;
    if (measured.depth > depth) depth = measured.depth;
  };
  // These exact original strings are the inputs of JSON.parse in the existing
  // Environment producer. No complete declaration is reparsed to measure them.
  for (const name of ['evidence_schemas', 'evidence_capabilities', 'view_bodies', 'contracts', 'command_bodies']) {
    const wires = declared[name] ?? (name === 'command_bodies' ? [] : undefined);
    if (!Array.isArray(wires)) invalid();
    for (const wire of wires) {add(wire); members++;}
  }
  if (!Array.isArray(mappings)) invalid();
  for (const wire of mappings) {add(wire); members++;}
  add(declared.catalog); add(declared.manifest_entry); add(environmentEnvelope);
  // Parsed input trees; body/environment/final root spreads; byCid map output
  // and in-place sort scratch. Their elements borrow the same parsed nodes.
  const parsed = nodes, rootSpreads = 3n * base.nodes, byCid = 2n * members;
  // checkpoints.mjs canonicalJson: Object.entries array + its pairs, filter
  // array, replacement pairs/map array, key array/Set, sort scratch, mapped
  // child-text array and recursion frames. Each family is bounded by nodes.
  const entries = nodes, originalPairs = nodes, filtered = nodes,
    replacementPairs = nodes, replacementArray = nodes, keys = nodes,
    keySet = nodes, sort = nodes, children = nodes, frames = nodes;
  // JSON escaping consumes at most six units per input unit; numeric output
  // needs at most25 units/value. Three extra wrapper levels cover insertion into
  // the complete Environment. Recursive map/join/wrapping retains three text
  // generations; hash input and final canonical output are also covered.
  const output = 6n * units + 25n * nodes;
  const recursiveText = 6n * (weighted + 3n * units) + 25n * nodes * (depth + 4n);
  const decodedText = 2n * units;
  const canonicalText = 2n * (3n * recursiveText + 2n * output);
  const hashWire = 3n * output;
  const workspace = {nodes: parsed + rootSpreads + byCid + entries + originalPairs + filtered +
    replacementPairs + replacementArray + keys + keySet + sort + children + frames,
    text: decodedText + canonicalText, wire: hashWire};
  // Only the closed pure producer's frozen result escapes: one record and
  // two String values. Workspace includes its conservative temporary overlap.
  const retained = {nodes: 3n, text: 2n * (output + 71n), wire: 0n};
  return {...workspace, retained, workspace};
}

const viewFields = ['resource', 'resource_kind', 'schema_wire', 'schema_cid',
  'request_schema_wire', 'facts_wire', 'acquisition_wire',
  'data_classification', 'resource_identity_wire'];
export function sourceAuthoredViewConstructionGeometry(views) {
  if (!Array.isArray(views) || nodeTypes.isProxy(views) || !Object.isFrozen(views)) invalid();
  let fields = 0n, units = 0n;
  for (let index = 0; index < views.length; index++) {
    const element = Object.getOwnPropertyDescriptor(views, String(index));
    if (!element || !Object.hasOwn(element, 'value')) invalid();
    const view = element.value;
    if (view === null || typeof view !== 'object' || nodeTypes.isProxy(view) || !Object.isFrozen(view)) invalid();
    for (const name of viewFields) {
      const field = Object.getOwnPropertyDescriptor(view, name);
      if (field === undefined || field.value === undefined && Object.hasOwn(field, 'value')) continue;
      if (!Object.hasOwn(field, 'value') || typeof field.value !== 'string') invalid();
      fields++; units += BigInt(name.length + field.value.length);
    }
  }
  const count = BigInt(views.length);
  // Existing captureDeclarationViews: descriptor records, selected records,
  // snapshot array and their field entries; original strings remain borrowed.
  const descriptors = fields, selected = count + fields, snapshot = 1n + count;
  // {views:[{String:String}]} has fixed depth3, no embedded schema parse.
  const output = 6n * units + 4n * fields + 3n * count + BigInt('{"views":[]}'.length);
  return {nodes: descriptors + selected + snapshot,
    text: 2n * (4n * output), wire: 0n};
}

export function sourceEnvironmentRetainedGeometry(environment) {
  if (!environment || nodeTypes.isProxy(environment) || !Object.isFrozen(environment)) invalid();
  const wire = Object.getOwnPropertyDescriptor(environment, 'wire');
  const cid = Object.getOwnPropertyDescriptor(environment, 'evidenceCid');
  if (!wire || !cid || !Object.hasOwn(wire, 'value') || !Object.hasOwn(cid, 'value') ||
      typeof wire.value !== 'string' || typeof cid.value !== 'string') invalid();
  return {nodes: 3n, text: 2n * BigInt(wire.value.length + cid.value.length), wire: 0n};
}

// The final Host composer parses the selected complete role documents, checks
// their original CIDs, and merges only their inert declaration metadata. Text
// bytes are not Value nodes. Keep the existing sixteen overlapping tree roles,
// with the recursive canonical text and hash workspace priced separately.
export function sourceEnvironmentCompositionGeometry(wires) {
  if (!Array.isArray(wires)) invalid();
  let nodes = 0n, units = 0n, weighted = 0n, depth = 0n;
  for (const wire of wires) {
    if (wire === undefined) continue;
    const measured = sourceJsonWireGeometry(wire);
    nodes += measured.nodes; units += measured.units; weighted += measured.weighted;
    if (measured.depth > depth) depth = measured.depth;
  }
  // Input parse/body records, admitted originals, merged section arrays/maps,
  // selector records and canonical entry/pair/sort/child/frame families borrow
  // the same value trees. The original source/declaration prefix stays separate.
  const output = 6n * units + 25n * nodes;
  const recursiveText = 6n * (weighted + 3n * units) + 25n * nodes * (depth + 4n);
  const retained = {nodes: 16n * nodes,
    text: 2n * (units + output + 4n * 71n), wire: 3n * output};
  return {nodes: 16n * nodes,
    text: 2n * units + 2n * (3n * recursiveText + 2n * output),
    wire: 3n * output, retained};
}
