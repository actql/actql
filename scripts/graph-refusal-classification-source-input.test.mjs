import {graphAnyDirectionRefusals as historicalgraphAnyDirectionRefusals} from '../reviews/2026-10-11-with-carrier-cutover/pre-with-refusal-inputs/graph-any-direction-source-input.mjs';
import {graphAbbreviatedRefusals as historicalgraphAbbreviatedRefusals} from '../reviews/2026-10-11-with-carrier-cutover/pre-with-refusal-inputs/graph-abbreviated-edge-source-input.mjs';
import {graphQuantifierFormsRefusals as historicalgraphQuantifierFormsRefusals} from '../reviews/2026-10-11-with-carrier-cutover/pre-with-refusal-inputs/graph-quantifier-forms-source-input.mjs';
import {graphEdgePredicateRefusals as historicalgraphEdgePredicateRefusals} from '../reviews/2026-10-11-with-carrier-cutover/pre-with-refusal-inputs/graph-edge-predicate-source-input.mjs';
import {graphHopNodePredicateRefusals as historicalgraphHopNodePredicateRefusals} from '../reviews/2026-10-11-with-carrier-cutover/pre-with-refusal-inputs/graph-hop-node-predicate-source-input.mjs';
import {graphDifferenceSourceRefusals as historicalgraphDifferenceSourceRefusals} from '../reviews/2026-10-11-with-carrier-cutover/pre-with-refusal-inputs/graph-difference-source-input.mjs';
import {graphEqualitySourceRefusals as historicalgraphEqualitySourceRefusals} from '../reviews/2026-10-11-with-carrier-cutover/pre-with-refusal-inputs/graph-equality-source-input.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {graphSourceRefusals} from './fixtures/graph-source-input.mjs';
import {subgraphSourceRefusals} from './fixtures/subgraph-source-input.mjs';
import {subgraphSourceRefusals as historicalSubgraphRefusals} from '../reviews/2026-10-11-with-carrier-cutover/pre-with-subgraph-source-input.mjs';
import {graphAnyDirectionRefusals} from './fixtures/graph-any-direction-source-input.mjs';
import {graphAbbreviatedRefusals} from './fixtures/graph-abbreviated-edge-source-input.mjs';
import {graphQuantifierFormsRefusals} from './fixtures/graph-quantifier-forms-source-input.mjs';
import {graphEdgePredicateRefusals} from './fixtures/graph-edge-predicate-source-input.mjs';
import {graphHopNodePredicateRefusals} from './fixtures/graph-hop-node-predicate-source-input.mjs';
import {graphRowSourceRefusals} from './fixtures/graph-row-source-input.mjs';
import {graphDiagnosticSourceRefusals} from './fixtures/graph-diagnostics-source-input.mjs';
import {graphDifferenceSourceRefusals} from './fixtures/graph-difference-source-input.mjs';
import {graphEqualitySourceRefusals} from './fixtures/graph-equality-source-input.mjs';

// Literal digests pin the complete original authored inputs at 8c0b9fd2.
// They were recorded before these exact-code additions, not sampled from a runtime.
const originals = [
  ['keyed-unadapted-endpoint-label', '271185b4eb1586042c77bff2cff6b473dd7509c6eccb5f09bfa09168cbd7df9d', true],
  ['keyed-unadapted-heterogeneous-binding', '82dc7e5a434454aa830c821bad33e40be38e7de30f2941896a11d102ac2f219c', false],
  ['unsupported-mean-consumer', 'b164194202d0df9d5e7022fae8650017da18cf8ae0f8a2dd382fa28e5325bb71', false],
  ['keyed-star', '8b191e4609d8b8d39ca18148e9aeb4c1ba7420bee4779a95d588447130479169', true],
  ['keyed-implicit-element-export', 'a25334045955b4a360eeec2201b1a24c04932abfd10d67e14509dafebb8450a9', true],
  ['subgraph-common-where-selector-gap', 'cd4f6028e330b2fbe70af45749ace50c479372c74a6f49ca7188146ae76e1a05', true],
  ['subgraph-after-relation-transition', '3603abbe70204df741a2c1caf28d1a18490cc55871c08b498c1481ac18ebd35a', false],
  ['graph-any-direction-unfiltered-reached-label', '98cb499420b4b5a35276dcf83990791fd59ba8c3904b7768749a5d6ef53a9370', true],
  ['graph-abbreviated-terminal-quantified-predicate', 'a2cfb424368a3c964468642c0ccd841658d215b679971117b6c1cb0fc6b9c0cd', true],
  ['graph-quantifier-terminal-only-predicate', 'cbd9207ba6c75aae5f9078f564be2da3f44f88bb15a39b9259243ee7e1cca99b', true],
  ['graph-edge-predicate-invalid-named-binding', '41c36eae87773f3febb8ad66d4290c746264efbb7bc2032cd8364b5c7db12a04', true],
  ['graph-hop-node-quantified-endpoint', '75dd553b7380a68b1f86306c0807bd39e9e3120cdc20d50eeeefdbe94ab524cf', true],
  ['graph-hop-node-unfiltered-label', 'de88f2e64e981ebfe3e478d5690b94ea6ec54617df9bf568b2dda315d2e511e0', true],
  ['graph-row-carrier-mismatch', '758a9614611b14a4dd2cbb5974df49fccb02d8b68629c64f7c3201a0461633db', false],
  ['graph-row-unknown-definition', 'be4f054d42d89109b8a0891d8329761d7443338945ea30c599fed03e3ca67d0d', false],
  ['graph-row-wrong-kind', '247f8456230bca433136514901d9e73f6173108a5f3dde4db37e571031cc5df9', false],
  ['graph-row-unknown-label', 'e78e0dab7c7255cac17d16bb8ea0e30f9ffa81ede25b97f9845cd0b733128006', false],
  ['graph-row-both-selectors', '40956878a447f1d8f54ccb6c586227c4920783d7134d084110ba6bd82e3489b2', false],
  ['graph-row-non-string-selector', 'd1bde5e7648e079d63cf45f3be8ec08faf57c1581d5e28aed12678182f57d8a9', false],
  ['graph-diagnostics-second-graph-call', 'a048bd302192a8a5fca5fe5849793da63f94016576aec7e6d2ef647b43f84244', false],
  ['graph-difference-missing-argument', '6680267580d79c1691775babb05897de2d9908ae286130ddd3424cd3166079a1', false],
  ['graph-difference-extra-argument', 'a1e595c60abb785e697ea7adec60bd0257bc1cdfd22f9df8c0ec9f53d2d9cef0', false],
  ['graph-difference-repeated-transition', 'ab084a4835d25da06f591913ce1f5ae5780973fafb74f598e3e44639f7c32ea4', false],
  ['graph-equality-missing-argument', '8f2bb722afd70d2e45d0fdc7dc1397daee259e3838184ba7ffb3312781576d77', false],
  ['graph-equality-extra-argument', '1aec74bc5fd9a9ccee77380876878bfa64926d6600f1a9af43818461a73d85a7', false],
  ['graph-equality-graph-call-after-transition', '2460ffb2a2bab8d2a1a3345ec1efd8c162329f85999137cfa524eb93dff44f83', false],
];
// Retired authored sources remain immutable evidence, not accepted callers.
const historicalCore = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/pre-with-graph-core-source-input.json', import.meta.url), 'utf8'));
const historicalRows = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/pre-with-graph-row-source-input.json', import.meta.url), 'utf8'));
const historicalOperations = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/pre-with-graph-operation-source-input.json', import.meta.url), 'utf8'));
const cases = new Map([
  ...historicalCore.graph.refusals,
  ...historicalSubgraphRefusals.map(item => ({...item,
    ...(item.name === 'subgraph-common-where-selector-gap' ? {expectedCode:'ClientProgramImplementationLimit'} : {})})),
  ...historicalgraphAnyDirectionRefusals,
  ...historicalgraphAbbreviatedRefusals,
  ...historicalgraphQuantifierFormsRefusals,
  ...historicalgraphEdgePredicateRefusals,
  ...historicalgraphHopNodePredicateRefusals,
  ...historicalRows.refusals,
  ...historicalOperations.groups.diagnostics.refusals,
  ...historicalgraphDifferenceSourceRefusals,
  ...historicalgraphEqualitySourceRefusals,
].map(item => [item.name, item]));

const currentCases = new Map([...graphSourceRefusals,...subgraphSourceRefusals,...graphAnyDirectionRefusals,...graphAbbreviatedRefusals,...graphQuantifierFormsRefusals,...graphEdgePredicateRefusals,...graphHopNodePredicateRefusals,...graphRowSourceRefusals,...graphDiagnosticSourceRefusals,...graphDifferenceSourceRefusals,...graphEqualitySourceRefusals].map(item=>[item.name,item]));

test('only independently proven Graph support gaps gain exact implementation-limit expectations', () => {
  assert.equal(originals.filter(([, , gap]) => gap).length, 10);
  for (const [name, originalDigest, gap] of originals) {
    const item = cases.get(name);
    assert.ok(item, name);
    const {expectedCode, ...input} = item;
    assert.equal(createHash('sha256').update(encodeRetainedFixture(input)).digest('hex'),
      originalDigest, name + ': preserve the complete original authored input');
    const current = currentCases.get(name);
    assert.ok(current,name);
    if (gap) assert.equal(current.expectedCode, 'ClientProgramImplementationLimit', name);
    else assert.equal(Object.hasOwn(current, 'expectedCode'), false,
      name + ': malformed input retains its original rejection policy');
  }
});

test('WITH Graph row refusals preserve their existing rejection policy', () => {
  assert.equal(graphRowSourceRefusals.length, historicalRows.refusals.length);
  for (const current of graphRowSourceRefusals) {
    const previous = historicalRows.refusals.find(input => input.name === current.name);
    const {text: oldText, ...oldPolicy} = previous;
    const {text, ...policy} = current;
    assert.deepEqual(policy, oldPolicy);
    assert.notEqual(text, oldText);
    assert.ok(text.startsWith('WITH '));
    assert.ok(!/\bDATA\b|PROPERTY GRAPH/.test(text));
  }
});

test('WITH Graph core refusals preserve independent rejection policy', () => {
  assert.equal(graphSourceRefusals.length, historicalCore.graph.refusals.length);
  for (const current of graphSourceRefusals) {
    const previous = historicalCore.graph.refusals.find(item => item.name === current.name);
    const {text: oldText, ...oldPolicy} = previous;
    const {text, ...policy} = current;
    assert.deepEqual(policy, oldPolicy, current.name);
    if (current.name === 'data-sql-format') {
      assert.equal(text, oldText, 'retain explicit rejection of the retired entry');
    } else {
      assert.notEqual(text, oldText, current.name);
      assert.ok(text.startsWith('WITH '), current.name);
      assert.ok(!/\bDATA\b|PROPERTY GRAPH/.test(text), current.name);
    }
  }
});


test('WITH diagnostic refusals retain complete input policy', () => {
  for (const current of graphDiagnosticSourceRefusals) {
    const {text: oldText, ...oldPolicy} = historicalOperations.groups.diagnostics.refusals.find(item => item.name === current.name);
    const {text, ...policy} = current;
    assert.deepEqual(policy, oldPolicy);
    assert.notEqual(text, oldText);
    assert.ok(text.startsWith('WITH '));
  }
});

// A historical digest never becomes a digest of the migrated current caller.
// The input grammar changes; the independent refusal policy does not.
test('current subgraph callers retain the independently pinned refusal policy',()=>{
  for(const name of ['subgraph-common-where-selector-gap','subgraph-after-relation-transition']){
    const current=subgraphSourceRefusals.find(item=>item.name===name);
    const old=historicalSubgraphRefusals.find(item=>item.name===name);
    assert.ok(current&&old,name);
    assert.notEqual(current.text,old.text);
    assert.ok(current.text.startsWith('WITH '));
    assert.equal(current.expectedCode,name==='subgraph-common-where-selector-gap'?'ClientProgramImplementationLimit':undefined);
    const {text:currentText,expectedCode:currentCode,...currentInput}=current;
    const {text:oldText,expectedCode:oldCode,...oldInput}=old;
    assert.deepEqual(currentInput,oldInput);
  }
});
