import assert from 'node:assert/strict';
import test from 'node:test';
import {bindInstalledManagedSources} from './installed-managed-source.mjs';

test('whole Source capacity facade captures the original method and receiver without issuing a new Run', () => {
  const selection = {}, prepared = {}, contracts = {}, selected = {};
  const facts = {preparedProgram: prepared, sourceSelection: selection, installedContracts: contracts};
  const source = {prepare() {}, ledgerCapacity() {}, managedCaptureCapacity() {},
    managedWholeSourceCapacity(value) {assert.equal(this, source); assert.equal(value, facts); return selected;}};
  const bound = bindInstalledManagedSources(source, () => assert.fail('Pre-Plan capacity cannot issue/adopt a Run'));
  source.managedWholeSourceCapacity = () => assert.fail('Original fixed method must be retained');
  assert.equal(bound.managedWholeSourceCapacity(facts), selected);
});
