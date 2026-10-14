// Installation DATA refusals only, not Source authorization or byte funding.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledRowSource} from './installed-row-source.mjs';

test('listing installation refuses malformed declarations without invoking a supplier callback', async () => {
  let calls = 0;
  const callback = () => { calls++; };
  for (const listingReportCapacity of [null, [], 1n, 0, false, callback]) {
    await assert.rejects(createInstalledRowSource({listingReportCapacity}),
      {code: 'InvalidInstalledListingReportCapacity'});
  }
  assert.equal(calls, 0);
});

test('explicit listing installation requires both planner and acquisition consumer before preparation', async () => {
  const listingReportCapacity = Object.freeze({fixture: 'opaque declaration'});
  const start = () => assert.fail('No original RowRun may start');
  for (const moon of [undefined, {},
    {clientProgramRowSourceStartListingAccounted: start},
    {clientProgramInstalledListingRowCaptureCapacity: start}]) {
    await assert.rejects(createInstalledRowSource({moon, listingReportCapacity}),
      {code: 'InstalledListingSourceUnavailable'});
  }
});
