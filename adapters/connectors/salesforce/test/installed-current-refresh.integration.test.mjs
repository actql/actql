// Current Catalog observations belong to the exact preflight the common apply
// owner validates, even when this captured Set has another refresh in flight.
import assert from 'node:assert/strict';
import {join} from 'node:path';
import test from 'node:test';
import {effectHost, effectProgram, installedEffect, salesforceMoon} from
  './installed-salesforce-effect.fixture.mjs';

const write = {resource: 'Test_Record__c', kind: 'createFromResult', sources: [
  {target: 'External_Key__c', field: 'id', nullBehavior: 'reject'},
  {target: 'Name', field: 'id', nullBehavior: 'reject'},
]};
const writesOf = org => org.seen.filter(entry => entry.method === 'POST');

for (const copied of [false, true]) {
  test(`installed dispatch ${copied ? 'refuses a copied' : 'uses its original'} refresh instead of the latest Catalog`, async t => {
    const installation = await installedEffect(t, {writes: [write], writeOperation: 'create'});
    const rechecks = [];
    // Transparent observation of the actual provider export. The same original
    // requests/observations are passed through; no Catalog or outcome is issued.
    const observedProvider = Object.freeze({...salesforceMoon,
      salesforceRecheckSingleWriteRequest(request, observation) {
        rechecks.push({request, observation});
        return salesforceMoon.salesforceRecheckSingleWriteRequest(request, observation);
      }});
    const installed = await installation.load({}, {salesforceMoon: observedProvider});
    let originalCatalog;
    let laterCatalog;
    const host = await effectHost(t, installation, join(installation.root, 'host'), {
      effect: installed,
      wrapStage: stage => ({...stage, apply: {...stage.apply,
        async refreshPreflight(input) {
          rechecks.length = 0;
          const original = await stage.apply.refreshPreflight(input);
          originalCatalog = rechecks.at(-1)?.observation;
          assert.ok(originalCatalog);
          rechecks.length = 0;
          const later = await stage.apply.refreshPreflight(input);
          laterCatalog = rechecks.at(-1)?.observation;
          assert.ok(laterCatalog);
          assert.notEqual(originalCatalog, laterCatalog);
          // Equal capability DATA is not permission to substitute this later
          // Catalog for the original current observation used by this apply.
          assert.deepEqual(original.capabilities, later.capabilities);
          rechecks.length = 0;
          return copied ? Object.freeze({...original}) : original;
        },
      }}),
    });
    const [mapping] = installed.mappings;
    const program = effectProgram({save: {create: {target: mapping.target,
      mapping: mapping.mappingRef, from: {result: 'rows'}}}},
    [{id: 'first'}, {id: 'second'}]);
    const outcome = await host.run(program, copied ? 'copied-refresh' : 'original-refresh')
      .then(result => ({result}), error => ({error}));
    if (copied) {
      assert.equal(outcome.error?.code, 'InvalidInstalledRowEffectRoute');
      assert.equal(writesOf(installation.org).length, 0);
      assert.equal(rechecks.length, 0);
    } else {
      assert.equal(outcome.error, undefined, String(outcome.error?.code));
      assert.equal(outcome.result.started.value.status, 'published');
      assert.equal(writesOf(installation.org).length, 2);
      assert.ok(rechecks.length >= 2);
      for (const entry of rechecks) {
        assert.equal(entry.observation, originalCatalog);
        assert.notEqual(entry.observation, laterCatalog);
      }
    }
  });
}
