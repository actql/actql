// The ordinary Row Effect retains each concurrent refresh's original Catalog.
// This exercises real Site calls; the resolver gate issues no credential or
// observation and forwards the installed fixture's original secret unchanged.
import assert from 'node:assert/strict';
import {join} from 'node:path';
import test from 'node:test';
import {effectHost, effectProgram, installedEffect, salesforceMoon} from
  './installed-salesforce-effect.fixture.mjs';

test('installed concurrent refreshes retain their own Catalog when the first finishes last',
  {timeout: 20_000}, async t => {
    const installation = await installedEffect(t, {
      writes: [{resource: 'Test_Record__c', kind: 'createFromResult', sources: [
        {target: 'External_Key__c', field: 'id', nullBehavior: 'reject'},
        {target: 'Name', field: 'id', nullBehavior: 'reject'},
      ]}], writeOperation: 'create',
    });
    const rechecks = [];
    const observedProvider = Object.freeze({...salesforceMoon,
      salesforceRecheckSingleWriteRequest(request, observation) {
        rechecks.push({request, observation});
        return salesforceMoon.salesforceRecheckSingleWriteRequest(request,
          observation);
      }});
    let holdNextResolution = false;
    let notifyFirstEntered;
    let releaseFirst;
    const firstEntered = new Promise(resolve => { notifyFirstEntered = resolve; });
    const firstGate = new Promise(resolve => { releaseFirst = resolve; });
    t.after(() => releaseFirst());
    const originalResolver = installation.options.resolveSecret;
    const installed = await installation.load({}, {
      salesforceMoon: observedProvider,
      async resolveSecret(...args) {
        if (holdNextResolution) {
          holdNextResolution = false;
          notifyFirstEntered();
          await firstGate;
        }
        return Reflect.apply(originalResolver, installation.options, args);
      },
    });
    const writes = () => installation.org.seen.filter(entry =>
      entry.method === 'POST');
    let firstCatalog;
    let secondCatalog;
    const completionOrder = [];
    const host = await effectHost(t, installation,
      join(installation.root, 'host'), {effect: installed,
        wrapStage: stage => ({...stage, apply: {...stage.apply,
          async refreshPreflight(input) {
            rechecks.length = 0;
            holdNextResolution = true;
            const firstFlight = stage.apply.refreshPreflight(input);
            const firstSettled = firstFlight.then(value => ({value}),
              error => ({error, failed: true}));
            let firstOutcome;
            let second;
            try {
              await firstEntered;
              assert.equal(writes().length, 0);
              second = await stage.apply.refreshPreflight(input);
              completionOrder.push('second');
              secondCatalog = rechecks.at(-1)?.observation;
              assert.ok(secondCatalog);
              assert.equal(writes().length, 0);
              rechecks.length = 0;
            } finally {
              releaseFirst();
              // Even a later refresh failure must join this original pending
              // operation before the fixture's Host and Site can close.
              firstOutcome = await firstSettled;
            }
            if (firstOutcome.failed) throw firstOutcome.error;
            const first = firstOutcome.value;
            completionOrder.push('first');
            firstCatalog = rechecks.at(-1)?.observation;
            assert.ok(firstCatalog);
            assert.notEqual(firstCatalog, secondCatalog);
            assert.deepEqual(first.capabilities, second.capabilities);
            rechecks.length = 0;
            // Dispatch with the earlier-completed refresh after the other
            // one has finished. A mutable latest-Catalog cursor is not enough.
            return second;
          },
        }}),
      });
    const [mapping] = installed.mappings;
    const program = effectProgram({save: {create: {target: mapping.target,
      mapping: mapping.mappingRef, from: {result: 'rows'}}}},
    [{id: 'first'}, {id: 'second'}]);
    const outcome = await host.run(program, 'concurrent-original-refresh');
    assert.equal(outcome.started.value.status, 'published');
    assert.deepEqual(completionOrder, ['second', 'first']);
    assert.equal(writes().length, 2);
    assert.ok(rechecks.length >= 2);
    for (const entry of rechecks) {
      assert.equal(entry.observation, secondCatalog);
      assert.notEqual(entry.observation, firstCatalog);
    }
  });
