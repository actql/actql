import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { hash } from './inventory.mjs';
import { providerConstructionBound, inspectProviderConstruction } from './capacity/parent-control/provider-construction.mjs';
const read = path => readFileSync(new URL(`../../${path}`, import.meta.url));
// Synthetic admission tests, separate from the archived real native reader.
const fact = () => ({ kind: 'provider construction observation', providers: 11,
  records: 11, arraySlots: 11, callbacks: 30, defaultArrays: 1, indexedBytes: 1504,
  unclassifiedCaptures: 0, scalarDynamicCallbacks: 0 });
test('constructor bound is derived from source counts and declared ABI, not observations', () => {
  const b = providerConstructionBound(read);
  assert.equal(b.bytes, 2344);
  assert.equal(b.bytes, 11 * (40 + 4 * 40) + 120 + 24);
  assert.equal(b.completeParentUpper, false);
  assert.equal(b.completePipelineUpper, false);
  assert.equal(inspectProviderConstruction([fact()], read, 'native').recipe.bytes, b.bytes);
  assert.equal(inspectProviderConstruction([{ ...fact(), indexedBytes: 2344 }], read, 'native').recipe.bytes, b.bytes);
});
test('constructor source and compatibility representation are independent admission premises', () => {
  for (const path of ['src/connectors/local/selected_relation_provider.mbt',
    'src/connectors/local/managed_provider.mbt', 'src/execution_relation/generated_sequence.mbt']) {
    assert.throws(() => providerConstructionBound(p => p === path ? Buffer.concat([read(p), Buffer.from('\n')]) : read(p)),
      /Unreviewed provider constructor|Changed provider representation premise/);
  }
});
test('constructor facts cannot be relabeled as portable or complete pipeline evidence', () => {
  for (const target of ['js', 'wasm'])
    assert.throws(() => inspectProviderConstruction([fact()], read, target), /native only/);
  assert.throws(() => inspectProviderConstruction([], read, 'native'), /Missing real/);
  for (const [key, value] of Object.entries({ providers: 10, records: 10, arraySlots: 10,
    callbacks: 45, defaultArrays: 2, unclassifiedCaptures: 1, scalarDynamicCallbacks: 45,
    indexedBytes: 2345 })) {
    assert.throws(() => inspectProviderConstruction([{ ...fact(), [key]: value }], read, 'native'));
  }
  assert.throws(() => inspectProviderConstruction([{ ...fact(), indexedBytes: 0 }], read, 'native'), /Missing candidate/);
});
test('scalar callback counts never become measured extents or a complete byte guarantee', () => {
  const result = inspectProviderConstruction([{ ...fact(), callbacks: 20, scalarDynamicCallbacks: 20 }], read, 'native');
  assert.equal(result.scalarPayloadBytesObserved, false);
  assert.equal(result.completeConstructorByteCorrespondence, false);
  assert(result.recipe.unresolved.some(p => p.includes('scalar callback')));
  assert.throws(() => inspectProviderConstruction([{ ...fact(), callbacks: 40, scalarDynamicCallbacks: 5 }], read, 'native'),
    /Too many constructor callbacks/);
});

// The actual recipe-introduction sources remain the review baseline. These
// checks distinguish the reviewed source changes from arbitrary digest refresh.
const recipeIntroduction = '58fd19eade59cf3bcbf6a859c9821471346e3b41';
const historical = path => execFileSync('git', ['--no-replace-objects', 'show',
  `${recipeIntroduction}:${path}`], {cwd:fileURLToPath(new URL('../../',import.meta.url))});
test('reviewed handoff helper leaves provider fields and constructor bodies unchanged', () => {
  const path = 'src/connectors/local/managed_provider.mbt';
  const before = historical(path), source = read(path).toString();
  assert.equal(hash(before), '8d00f3fb875d1523796a13ae5ac67906fb16f9ee64f67cd85205bc0544ca3f2e');
  const start = source.indexOf('///|\n/// Charge a validated handoff delta to the SAME provider accounting owner.');
  const end = source.indexOf('///|\npub fn cancel_managed_provider(',start);
  assert(start >= 0 && end > start);
  // The whole remaining file, including all fields, wrappers, captures and
  // accounting/lifecycle functions, must equal the original source bytes.
  assert.equal(source.slice(0,start) + source.slice(end), before.toString());
  assert.throws(() => providerConstructionBound(p => p === path ? before : read(p)),
    /Changed provider representation premise src\/connectors\/local\/managed_provider\.mbt/);
});
test('reviewed Graph rejection branches preserve the Relation capability predicate', () => {
  const path = 'src/execution_relation/generated_sequence.mbt';
  const before = historical(path), source = read(path).toString();
  assert.equal(hash(before), '3a2c83c19c767b0f160afde6b85fe84ab87e3a0a391dc95a52be98edae760981');
  const oldBranch = [
    '      | @lower.GraphBasicStep(_)',
    '      | @lower.GraphStructuralStep(_)',
    '      | @lower.GraphUnionStep(_)',
    '      | @lower.GraphMeanStep(_)',
    '      | @lower.GraphMatchStep(_)',
    '      | @lower.GraphReachStep(_)',
    '      | @lower.GraphSubgraphStep(_)',
    '      | @lower.GraphTraverseStep(_)',
    '      | @lower.GraphShortestStep(_)',
    '      | @lower.GraphRelationStep(_)',
    '      | @lower.GraphConstructionStep(_)',
  ].join('\n');
  const newBranch = [
    '      | @lower.GraphMatchStep(_)',
    '      | @lower.GraphTraverseStep(_)',
    '      | @lower.GraphDiagnosticStep(_)',
    '      | @lower.PropertyGraphConstructionStep(_)',
  ].join('\n');
  assert.equal(before.toString().split(oldBranch).length,2);
  // GraphDiagnosticStep is only another non-Row false-branch alternative.
  // The active RowStep predicate, constructor records, callback captures,
  // candidate array, GeneratedSequence fields and other functions are unchanged.
  assert.equal(before.toString().replace(oldBranch,newBranch),source);
  assert.throws(() => providerConstructionBound(p => p === path ? before : read(p)),
    /Changed provider representation premise src\/execution_relation\/generated_sequence\.mbt/);
});
