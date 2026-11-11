// Run the unchanged public capture once, then observe the SAME still-alive
// child after its original FIRST close. A descriptor snapshot is not an ACK.
import assert from 'node:assert/strict';
import {resolve} from 'node:path';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';

await import('./capture-original.mjs');
const observation = await observeRecordApprovalDescriptors([resolve('.actql'), resolve('mock')]);
assert.deepEqual(observation.openPaths, []);
console.log(JSON.stringify({phase: 'capture', event: 'after-first-close', pid: process.pid,
  aliveScopedFD: {after: observation.openPaths.length}}));
