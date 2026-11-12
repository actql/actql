// Observe the SAME still-alive child after the unchanged original module
// settles, including its rejection after FIRST close. Never close twice or
// replace an original failure with a diagnostic failure or a descriptor ACK.
import assert from 'node:assert/strict';
import {resolve} from 'node:path';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';

async function observeOriginalCapture(load, observe, report) {
  let failed = false, primary, diagnosticFailed = false, diagnosticFailure;
  try {await load();} catch (error) {failed = true; primary = error;}
  try {
    const observation = await observe();
    report({phase: 'capture', event: 'after-original-module', pid: process.pid,
      originalImportFailed: failed, aliveScopedFD: {after: observation.openPaths.length}});
    assert.deepEqual(observation.openPaths, []);
  } catch (error) {diagnosticFailed = true; diagnosticFailure = error;}
  if (failed) throw primary;
  if (diagnosticFailed) throw diagnosticFailure;
}

await observeOriginalCapture(() => import('./capture-original.mjs'),
  () => observeRecordApprovalDescriptors([resolve('.actql'), resolve('mock')]),
  value => console.log(JSON.stringify(value)));
