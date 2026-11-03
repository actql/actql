// Constructor DATA for loadDeclaredProjectCatalog's first JS projection only.
// The SAME installed SourceInitialization owner reserves this geometry BEFORE
// JSON.parse(entryWire). The raw catalog read/Core admission/entry String must
// already be funded. No Resource, capacity grant, parse or receipt is created.
import {sourceJsonWireGeometry} from './installed-source-construction-geometry.mjs';
import {types as nodeTypes} from 'node:util';

// Exact keys of the saved-view record passed to the first native restore.
// Optional fields co-count even when absent. Original identifier Strings are
// borrowed; canonical schema/optional body Strings and schema CID are owned.
const savedViewTemplate = '{"resource":"","resource_kind":"","schema_wire":"","schema_cid":"","request_schema_wire":"","facts_wire":"","acquisition_wire":"","resource_identity_wire":"","data_classification":""}';
const restoreEnvelope = '{"views":[]}';
const optionalWireKeys = 'request_schema_wirefacts_wireacquisition_wireresource_identity_wire';

// Same canonicalJson(dataKeys:true) constructor families as the Environment
// recipe. In particular this mode never NFC-normalizes opaque member names.
// Geometry is a bound, not a claim that the unparsed input has any shape.
function canonicalConstruction({nodes, units, weighted, depth}) {
  const entries = nodes, originalPairs = nodes, filtered = nodes;
  const replacementPairs = nodes, replacementArray = nodes, keys = nodes;
  const keySet = nodes, sort = nodes, children = nodes, frames = nodes;
  // Escapes consume <=6 UTF16 units/input unit; numbers need <=25 units.
  // Weighted input length counts the actual original ancestor contributions.
  // map/join/wrapping text coexist, plus final output and its last builder.
  const outputUnits = 6n * units + 25n * nodes;
  const recursiveUnits = 6n * weighted + 25n * nodes * (depth + 1n);
  return {
    nodes: entries + originalPairs + filtered + replacementPairs +
      replacementArray + keys + keySet + sort + children + frames,
    text: 2n * (3n * recursiveUnits + 2n * outputUnits),
    wire: 0n,
    outputUnits,
  };
}

/**
 * Pre-parse stage-1 peak from the exact borrowed catalog entry String.
 * `nodes` is the existing SourceInitialization logical JS-constructor count;
 * `text` is BYTES of UTF16 backing (two bytes/unit), `wire` is owned byte
 * backing. All quantities are bigint, never measurements or authority.
 * `bounds` describes construction bounds, not accepted item counts. `input`
 * is the scalar scan geometry; it does not admit even well-formed JSON.
 *
 * Covers JSON.parse, entry validation, saved views/schema CIDs/optional wires,
 * alias/data/file-binding descriptors, seven parallel native quote arrays,
 * and canonical `{views: savedViews}` for the FIRST native restore. Retained
 * and temporary families coexist through failure; top-level fields SUM both.
 *
 * EXCLUDES native restore/export, its returned declaration JSON parse, scope
 * CID (which also uses directory/dataFile/whole original catalog), derived File
 * facts/version CIDs, physical override restores, update mappings, Environment
 * construction and final source descriptors. Each needs its own later staged
 * quote using its actual retained originals. This is not whole-loader funding.
 */
export function declaredProjectCatalogEntryConstructionGeometry(entryWire) {
  const input = sourceJsonWireGeometry(entryWire);
  const n = input.nodes, u = input.units;
  // The actual loader checks list length <=128 before processing any view.
  const views = n < 128n ? n : 128n;
  const members = views;

  // Schema plus optional body subtrees are disjoint parts of the same entry.
  // One canonical pass stores their text; a second recomputes schema text for
  // CID hashing. Two complete forests safely co-count their exact overlap.
  const canonical = canonicalConstruction(input);
  const savedBodyUnits = canonical.outputUnits;
  const savedCidUnits = 71n * views;
  const generatedKeyUnits = BigInt(optionalWireKeys.length) * views;
  const restoreInputUnits = u + savedBodyUnits + savedCidUnits +
    BigInt(savedViewTemplate.length) * views + BigInt(restoreEnvelope.length);
  // Root record, array, each saved record and its nine possible String fields.
  // Detached JSON bodies are now Strings, not reparsed trees at this stage.
  const restoreNodes = 2n + 10n * views;
  const restore = canonicalConstruction({nodes: restoreNodes,
    units: restoreInputUnits, weighted: 4n * restoreInputUnits, depth: 3n});

  // Actual co-held JS outputs: parsed tree; saved records and properties;
  // views/publicViews; alias spread records; data Map + spread bindings;
  // bound Set and file-binding spreads; seven parallel native argument arrays.
  const parsedTree = n;
  const savedRecords = views + 9n * views;
  const savedViews = 1n + views, publicViews = 1n + views;
  const aliases = 1n + members + n, data = 1n + members + n;
  const bound = 1n + 2n * members, fileBindings = 1n + members + n;
  const nativeArrays = 7n + 7n * views;
  const restoreRecordAndWire = 3n;
  const retained = {
    nodes: parsedTree + savedRecords + savedViews + publicViews + aliases +
      data + bound + fileBindings + nativeArrays + restoreRecordAndWire,
    // Parsed keys/values own decoded text. Saved identifier fields borrow it.
    text: 2n * (u + savedBodyUnits + savedCidUnits + generatedKeyUnits + restore.outputUnits),
    wire: 0n,
  };

  // Validation Object.keys arrays/fields and their closed-schema vocabulary,
  // fixed optional-name/required-file-name arrays, path/alias duplicate Sets,
  // per-view map/hash callbacks, spread/selection and failure-prefix controls.
  const validationKeys = n + n;
  const closedVocabulary = 2n + 9n * views + 8n * members;
  const optionalNames = 4n * views;
  const nameSets = members + n;
  const projectionControls = 8n + 4n * views + 4n * members;
  const hashControls = 4n * views;
  const workspace = {
    nodes: validationKeys + closedVocabulary + optionalNames + nameSets +
      projectionControls + hashControls + 2n * canonical.nodes + restore.nodes,
    // JSON decoder overlap plus both canonical forest calls and outer restore
    // encoding; SHA hex String and prefixed CID coexist before publication.
    text: 2n * u + 2n * canonical.text + restore.text + 2n * (64n + 71n) * views,
    // UTF8 hash input <=3 bytes/UTF16 unit. Per SHA256: 32-byte chaining
    // state, 64-byte block and 32-byte digest remain separate from input.
    wire: 3n * canonical.outputUnits + 128n * views,
  };
  return {
    nodes: retained.nodes + workspace.nodes,
    text: retained.text + workspace.text,
    wire: retained.wire + workspace.wire,
    retained, workspace, input,
    bounds: {views, savedBodyUnits, savedViewsWireUnits: restore.outputUnits},
  };
}

// Subsequent stages deliberately receive their extra exact borrowed originals.
// These functions do not replace/discount earlier material: the same owner
// retains each quote cumulatively until its normal constructor retirement.
const invalidGeometry = () => {throw new TypeError('InvalidDeclaredProjectCatalogConstructionGeometry');};
const stringUnits = value => {
  if (typeof value !== 'string') invalidGeometry();
  return BigInt(value.length);
};
const admittedCount = value => {
  if (!Number.isSafeInteger(value) || value < 0 || value > 128) invalidGeometry();
  return BigInt(value);
};
const zero = () => ({nodes: 0n, text: 0n, wire: 0n});
const stage = (retained, workspace, bounds = {}) => ({
  nodes: retained.nodes + workspace.nodes,
  text: retained.text + workspace.text,
  wire: retained.wire + workspace.wire,
  retained, workspace, bounds,
});
const maximum = (left, right) => left > right ? left : right;
const scopeTemplate = '{"connection":"","connector":"","dataPath":"","catalog":""}';
const versionTemplate = '{"scope":"","physical":{},"version_field":"","representation":"exact_stored_bytes"}';
const listingTemplate = '{"file_listing":{"version":"actql-file-list/0.1","kind":"file_listing","selectable":[],"allow_unfiltered_listing":true,"admitted_scope_contract_cid":"","listing_schema_contract_cid":"","version_capability":{"contract_cid":"","required_nonnull":true},"max_listing_items":100,"max_examined_items":100,"max_listing_pages":1,"max_request_attempts":1,"max_listing_bytes":1048576,"max_listing_duration_ms":30000,"maximum_path_length":4096}}';
const contentTemplate = '{"file_content":{"version":"actql-file-content/0.1","kind":"file_content","admitted_scope_contract_cid":"","content_schema_contract_cid":"","version_capability":{"contract_cid":"","required_nonnull":true},"representation":"exact_stored_bytes"},"lookup_capacity":{"version":"actql-lookup-capacity/0.1","completeness":"complete_per_requested_key","max_rows_per_key":1,"max_pages_per_request":1,"max_response_bytes_per_page":1048576}}';
const candidateTemplate = '{"relation_keys":{"candidate_keys":[[""]]}}';

// These are fixed implementation vocabularies, not parsing caller input.
const fixedCanonical = (template, additionalUnits) => {
  const shape = sourceJsonWireGeometry(template);
  const units = shape.units + additionalUnits;
  return {shape, canonical: canonicalConstruction({...shape, units,
    weighted: (shape.depth + 1n) * units})};
};

/** Exact scope-hash inputs; providerNamespace is configured provider identity,
 * NOT the logical connection used as the Source connectorId. The already-funded
 * resolvedDataPath is borrowed: resolving/canonicalizing a filesystem path is
 * not performed or funded by this quote. Whole catalog text is a STRING in
 * this preimage and is not reparsed, even if it contains detached JSON. */
export function declaredProjectCatalogScopeConstructionGeometry(
  connection, providerNamespace, resolvedDataPath, originalCatalogWire,
) {
  const units = stringUnits(connection) + stringUnits(providerNamespace) +
    stringUnits(resolvedDataPath) + stringUnits(originalCatalogWire);
  const {shape, canonical} = fixedCanonical(scopeTemplate, units);
  return stage({nodes: 1n, text: 2n * 71n, wire: 0n}, {
    // Original preimage record/fields, canonical workspace, Hash/update/digest
    // controls, 64-unit hex and 71-unit prefixed output, UTF8 hash input.
    nodes: shape.nodes + canonical.nodes + 4n,
    text: canonical.text + 2n * (64n + 71n),
    wire: 3n * canonical.outputUnits + 128n,
  }, {scopePreimageUnits: canonical.outputUnits});
}

/** Before JSON.parse(initialDeclarationWire), version hashes or File facts.
 * fileBindingCount is the exact count from ALREADY-FUNDED validated metadata,
 * never authority or a caller's capacity guess. A physical binding/schema may
 * be referenced repeatedly; every actual version-hash invocation is summed.
 * Initial native export and old saved-view Strings stay funded separately.
 * Covers final saved-view wire and its seven native argument arrays, but NOT
 * the subsequent native final restore/export, which gets its own quote. */
export function declaredProjectCatalogFileFactsConstructionGeometry(
  entryWire, initialDeclarationWire, scopeCid, fileBindingCount,
) {
  const entry = sourceJsonWireGeometry(entryWire);
  const initial = sourceJsonWireGeometry(initialDeclarationWire);
  const scope = stringUnits(scopeCid), count = admittedCount(fileBindingCount);
  if (count === 0n) return stage(zero(), zero(), {finalSavedViewsWireUnits: 0n});
  const first = declaredProjectCatalogEntryConstructionGeometry(entryWire);
  const versionFixed = sourceJsonWireGeometry(versionTemplate);
  // physical is an original entry binding with an original schema alias.
  // Adding that schema does not exceed the whole entry forest; a fresh spread
  // descriptor and the enclosing preimage have their own fixed nodes.
  const versionUnits = entry.units + scope + versionFixed.units;
  const version = canonicalConstruction({nodes: entry.nodes + versionFixed.nodes + 1n,
    units: versionUnits, depth: maximum(entry.depth + 1n, versionFixed.depth),
    weighted: entry.weighted + 2n * entry.units + 2n * (scope + versionFixed.units)});
  // The original native carrier CID is a String selected from its returned
  // export. Bound its length by that exact export, not a hardcoded CID size.
  const listing = fixedCanonical(listingTemplate, scope + initial.units + 71n);
  const content = fixedCanonical(contentTemplate, scope + initial.units + 71n);
  const factsUnits = count * (listing.canonical.outputUnits + content.canonical.outputUnits);
  const views = first.bounds.views;
  const restoreUnits = entry.units + first.bounds.savedBodyUnits + 71n * views +
    BigInt(savedViewTemplate.length) * views + BigInt(restoreEnvelope.length) + factsUnits;
  const restore = canonicalConstruction({nodes: 2n + 10n * views, units: restoreUnits,
    weighted: 4n * restoreUnits, depth: 3n});
  return stage({
    nodes: initial.nodes + count * 3n + 3n + 7n + 7n * views,
    text: 2n * (initial.units + 71n * count + factsUnits + restore.outputUnits),
    wire: 0n,
  }, {
    // Parsed initial tree failure-prefix text, each actual version preimage,
    // two separate fixed fact descriptor forests, find callbacks, canonical
    // families and final detached saved-view serialization coexist.
    nodes: initial.nodes + count * (versionFixed.nodes + 1n + version.nodes +
      listing.shape.nodes + content.shape.nodes + listing.canonical.nodes +
      content.canonical.nodes + 8n) + restore.nodes,
    text: 2n * initial.units + count * (version.text + listing.canonical.text +
      content.canonical.text + 2n * (64n + 71n)) + restore.text,
    wire: count * (3n * version.outputUnits + 128n),
  }, {finalSavedViewsWireUnits: restore.outputUnits, generatedFactsUnits: factsUnits,
    versionPreimageUnits: version.outputUnits, fileBindingCount: count});
}

/** All physical override payloads are prepared under one retained stage.
 * overrideCount comes from the already-funded validated data bindings. Each
 * override has its own schema canonical/hash, candidate-key facts and one-view
 * restore String/parallel native arrays. No native restore or export is here.
 * Aliased schemas are counted once PER INVOCATION, never deduplicated by data. */
export function declaredProjectCatalogPhysicalOverridesConstructionGeometry(entryWire, overrideCount) {
  const entry = sourceJsonWireGeometry(entryWire), count = admittedCount(overrideCount);
  if (count === 0n) return stage({nodes: 1n, text: 0n, wire: 0n}, zero(), {savedViewsWireUnits: 0n});
  const schema = canonicalConstruction(entry);
  const candidate = fixedCanonical(candidateTemplate, entry.units);
  const restoreUnits = entry.units + schema.outputUnits + 71n + candidate.canonical.outputUnits +
    BigInt(savedViewTemplate.length + restoreEnvelope.length);
  const restore = canonicalConstruction({nodes: 12n, units: restoreUnits,
    weighted: 4n * restoreUnits, depth: 3n});
  return stage({
    // Saved record+fields, outer record/array, seven one-item native arrays,
    // detached schema/facts/CID/restore Strings; all original keys are borrowed.
    // One physicalDeclarations Map stores saved inputs, then replaces those
    // SAME entries with native declarations; no second Map is constructed.
    nodes: 1n + count + count * (10n + 3n + 14n + 4n),
    text: 2n * count * (schema.outputUnits + 71n + candidate.canonical.outputUnits + restore.outputUnits),
    wire: 0n,
  }, {
    nodes: count * (2n * schema.nodes + candidate.shape.nodes + candidate.canonical.nodes +
      restore.nodes + 4n),
    text: count * (2n * schema.text + candidate.canonical.text + restore.text + 2n * (64n + 71n)),
    wire: count * (3n * schema.outputUnits + 128n),
  }, {savedViewsWireUnits: count * restore.outputUnits,
    perOverrideSavedViewsWireUnits: restore.outputUnits, overrideCount: count});
}

/** Final JS descriptors only. All supplied declaration/mapping wires and entry
 * originals remain borrowed from preceding funded constructors. mappingWires
 * accepts either the original frozen Mapping records (own body String) or
 * the existing diagnostic String array, without a pre-quote projection array.
 * Does not parse
 * these Strings or quote UPDATE Mapping/Environment/native restore operations.
 * sourceCount is the exact admitted connection count; per-entry invocation may
 * conservatively retain another final outer array envelope but never discounts
 * the already-completed source prefix. */
export function declaredProjectCatalogFinalDescriptorsConstructionGeometry(
  entryWire, declarationWire, mappingWires, sourceCount,
) {
  const entry = sourceJsonWireGeometry(entryWire);
  stringUnits(declarationWire);
  const sources = admittedCount(sourceCount);
  if (!Array.isArray(mappingWires) || nodeTypes.isProxy(mappingWires) || mappingWires.length > 128) invalidGeometry();
  let mappingCount = 0n;
  for (let index = 0; index < mappingWires.length; index++) {
    const property = Object.getOwnPropertyDescriptor(mappingWires, String(index));
    if (!property || !Object.hasOwn(property, 'value')) invalidGeometry();
    const original = property.value;
    if (typeof original === 'string') stringUnits(original);
    else {
      if (original === null || typeof original !== 'object' || nodeTypes.isProxy(original) ||
          !Object.isFrozen(original)) invalidGeometry();
      const body = Object.getOwnPropertyDescriptor(original, 'body');
      if (!body || !Object.hasOwn(body, 'value')) invalidGeometry();
      stringUnits(body.value);
    }
    mappingCount++;
  }
  const members = entry.nodes < 128n ? entry.nodes : 128n;
  const descriptors = members * (1n + 7n); // physical record and its fields
  const physicalArrays = 1n + members + members; // output slots + empty writable arrays
  const writes = 1n + mappingCount + entry.nodes; // spread writes, borrowed mapping wires
  const aliases = 1n + 3n * entry.nodes; // flatMap result + name/resource records
  // The four installed source/effect member/prepared fields borrow existing
  // owner tuples; they add references, never new initialization owners.
  const finalRecords = 13n + 9n + 4n + 1n + sources;
  const retained = {nodes: descriptors + physicalArrays + writes + aliases + finalRecords,
    text: 0n, wire: 0n};
  // freeze uses Object.values arrays and recursion for every referenced schema
  // and returned descriptor. Original subtrees may be traversed once per data
  // binding; the same nodes/text remain borrowed, never copied. Count each
  // traversal's arrays/slots/frames and spread/validation/Set work separately.
  const schemaTraversal = members * (entry.nodes + entry.nodes + entry.nodes);
  const descriptorTraversal = retained.nodes + retained.nodes + retained.nodes;
  return stage(retained, {nodes: schemaTraversal + descriptorTraversal +
    entry.nodes + entry.nodes + mappingCount + 8n,
    text: 0n, wire: 0n}, {sourceCount: sources, mappingCount});
}

const mappingWriteTemplate = '{"resource":"","primary_identity":"","update":{"fields":[],"permission":"","approval":""}}';
const mappingEnvelope = '{"writes":[]}';

/** Pre-prepareMappings JS input only, constructed inside the SAME existing
 * effect initialization's prepareNativeInput BEFORE prepareBorrowedDeclaration.
 * actualValidatedWriteCount is the exact count of already-funded admitted
 * entry.writes, not authority, a guessed budget or a new writable-target limit.
 *
 * Authored input: {writes:[{resource,primary_identity,update:{fields,permission,
 * approval}}]}. Frozen operations: {resource,operation:'update',sources:[{
 * target:name,field:name,null_behavior:'reject'}]}. Input Strings and fields
 * arrays are borrowed. Each source duplicates name REFERENCES, not text.
 * Native Mapping construction, declaration borrowing and Environment work are
 * outside this phase and remain in the original prepareMappings recipe.
 */
export function declaredProjectCatalogMappingInputsConstructionGeometry(entryWire, actualValidatedWriteCount) {
  const entry = sourceJsonWireGeometry(entryWire), count = admittedCount(actualValidatedWriteCount);
  const template = sourceJsonWireGeometry(mappingWriteTemplate);
  const envelope = sourceJsonWireGeometry(mappingEnvelope);
  const originalNodes = count === 0n ? 0n : entry.nodes;
  const originalUnits = count === 0n ? 0n : entry.units;
  const originalWeighted = count === 0n ? 0n : entry.weighted;
  // Actual writable_fields arrays are individually bounded to128 by names().
  // All fields are disjoint original entries; do not multiply the whole entry
  // payload by write count, even though a target/field pair borrows each name.
  const fields = originalNodes < 128n * count ? originalNodes : 128n * count;
  const units = originalUnits + template.units * count + envelope.units;
  const authoredNodes = originalNodes + template.nodes * count + envelope.nodes;
  const canonical = canonicalConstruction({nodes: authoredNodes, units,
    weighted: originalWeighted + 4n * originalUnits +
      6n * (template.units * count + envelope.units),
    depth: count === 0n ? envelope.depth : maximum(entry.depth + 3n, 5n)});
  const mappingsArray = 1n + count;
  const operationRecords = count * (1n + 3n);
  const sourcesArrays = count + fields;
  const sourceRecords = fields * (1n + 3n);
  const resultWrapperAndWire = 4n; // record+two fields+owned canonical String
  return stage({
    nodes: mappingsArray + operationRecords + sourcesArrays + sourceRecords + resultWrapperAndWire,
    text: 2n * canonical.outputUnits,
    wire: 0n,
  }, {
    // Temporary authored wrapper/array, two records per write and their own
    // member slots. fields borrows the existing writable_fields Array, never
    // a fresh copy. Canonical helper includes its actual traversal/sort/text.
    nodes: 3n + count + count * (2n + 6n) + canonical.nodes +
      // map callbacks, freeze calls, success/failure result controls.
      4n + 2n * count + fields,
    text: canonical.text,
    wire: 0n,
  }, {writesJsonUnits: canonical.outputUnits, writeCount: count, sourceFields: fields});
}
