import assert from 'node:assert/strict';
import test from 'node:test';
import {occurrences} from './check-owned-contract-versions.mjs';
import {assertGeneratedOwnedContracts} from './generated-owned-contracts.mjs';

const token = 'actql-model-invocation-evidence/' + ['0', '2'].join('.');
const source = occurrences(`let original_version = "${token}"`, 'src/model/owner.mbt');
const inventory = {version: 1, baseline: '0.1', entries: source.map(item =>
  ({...item, count: 1, reason: 'Explicitly reviewed current production contract.'}))};
const generated = occurrences(`var renamed = "${token}"`, 'generated/runtime.js');

test('compiled renaming and bundle duplication preserve admitted production contracts', () => {
  assertGeneratedOwnedContracts({source, generated: [...generated, ...generated], inventory});
});

test('the same token cannot admit a new source writer or changed source context', () => {
  for (const added of [
    occurrences(`let original_version = "${token}"`, 'src/model/new_writer.mbt'),
    occurrences(`let changed_version = "${token}"`, 'src/model/owner.mbt'),
    source,
  ]) {
    assert.throws(() => assertGeneratedOwnedContracts({source: [...source, ...added],
      generated, inventory}), /Unadmitted owned source contract contexts/u);
  }
});

test('unknown generated versions still refuse after valid source admission', () => {
  const unknown = occurrences('var output = "actql-model-invocation-evidence/' +
    ['0', '3'].join('.') + '"', 'generated/runtime.js');
  assert.throws(() => assertGeneratedOwnedContracts({source,
    generated: [...generated, ...unknown], inventory}), /require admitted production source/u);
});

test('historical tests and documents cannot authorize generated production contracts', () => {
  for (const path of ['src/model/rejection_test.mbt', 'src/model/rejection_wbtest.mbt',
    'docs/design/history.md']) {
    const historical = occurrences(`let old = "${token}"`, path);
    const historicalInventory = {...inventory, entries: historical.map(item =>
      ({...item, count: 1, reason: 'Historical rejection fixture.'}))};
    assert.throws(() => assertGeneratedOwnedContracts({source: historical,
      generated, inventory: historicalInventory}), /require admitted production source/u);
  }
});

test('baseline-only bundles need no nonbaseline source grant', () => {
  assertGeneratedOwnedContracts({source: [],
    generated: occurrences('var output = "actql-model-invocation-evidence/0.1"',
      'generated/runtime.js'), inventory});
});
