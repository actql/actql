import assert from 'node:assert/strict';
import {setTimeout} from 'node:timers/promises';
import {connect} from '@actql/node';
import {runRecordApprovalCommand} from '../record-approval/command.mjs';
import {hubspotUpdateCase} from '../record-approval/cases.mjs';
import {observeRecordApprovalDescriptors} from '../record-approval/scoped-fds.fixture.mjs';
import {runHubSpotApprovalPhase} from './workflow.mjs';

const [phase, configuration, prefix, state, credential] = process.argv.slice(2);
let outcome;
await runRecordApprovalCommand({argv: [phase, configuration, prefix],
  programDirectory: new URL('./', import.meta.url), connect,
  runPhase: runHubSpotApprovalPhase, createDefinition: hubspotUpdateCase,
  log(value) {assert.equal(outcome, undefined); outcome = value;}});
assert.equal(outcome.publicClientClose, 'returned');
const before = await observeRecordApprovalDescriptors([state, credential]);
assert.deepEqual(before.openPaths, []);
await setTimeout(2000);
const after = await observeRecordApprovalDescriptors([state, credential]);
assert.deepEqual(after.openPaths, []);
console.log(JSON.stringify({...outcome, pid: process.pid, descriptors: {before, after}}));
