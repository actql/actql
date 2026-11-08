import assert from 'node:assert/strict';
import {setTimeout} from 'node:timers/promises';
import {connect} from '@actql/node';
import {runRecordApprovalCommand} from './command.mjs';
import {salesforceUpdateCase, hubspotUpdateCase, kintoneUpdateCase} from './cases.mjs';
import {observeRecordApprovalDescriptors} from './scoped-fds.fixture.mjs';
import {runRecordUpdateApprovalPhase} from './workflow.mjs';

const [connectorId, phase, configuration, prefix, state, credential] = process.argv.slice(2);
const createDefinition = {salesforce: salesforceUpdateCase,
  hubspot: hubspotUpdateCase, kintone: kintoneUpdateCase}[connectorId];
assert.equal(typeof createDefinition, 'function');
const runPhase = ({programs, selection, ...phase}) => runRecordUpdateApprovalPhase({...phase,
  createDefinition: () => createDefinition(programs, selection)});
let outcome;
await runRecordApprovalCommand({argv: [phase, configuration, prefix],
  programDirectory: new URL(`../${connectorId}-approval/`, import.meta.url), connect,
  runPhase, createDefinition,
  log(value) {assert.equal(outcome, undefined); outcome = value;}});
assert.equal(outcome.publicClientClose, 'returned');
const roots = credential === undefined ? [state] : [state, credential];
const before = await observeRecordApprovalDescriptors(roots);
assert.deepEqual(before.openPaths, []);
await setTimeout(2000);
const after = await observeRecordApprovalDescriptors(roots);
assert.deepEqual(after.openPaths, []);
console.log(JSON.stringify({...outcome, pid: process.pid, descriptors: {before, after}}));
