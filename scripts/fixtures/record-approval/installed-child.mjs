import assert from 'node:assert/strict';
import {setTimeout} from 'node:timers/promises';
import {writeFile} from 'node:fs/promises';
import {connect} from '@actql/node';
import {runRecordApprovalCommand} from './command.mjs';
import {salesforceUpdateCase, hubspotUpdateCase, kintoneUpdateCase} from './cases.mjs';
import {observeRecordApprovalDescriptors} from './scoped-fds.fixture.mjs';
import {runRecordUpdateApprovalPhase} from './workflow.mjs';
import {workflowWorkObservation, assertRecordWorkflowWork} from '../../../adapters/host-node/fixtures/work-observation.fixture.mjs';

const [connectorId, phase, configuration, prefix, state, credential] = process.argv.slice(2);
const createDefinition = {salesforce: salesforceUpdateCase,
  hubspot: hubspotUpdateCase, kintone: kintoneUpdateCase}[connectorId];
assert.equal(typeof createDefinition, 'function');
const observation = process.env.ACTQL_RECORD_APPROVAL_MOCK_CONNECTOR === connectorId
  ? workflowWorkObservation({trackOriginal: true}) : undefined;
let originalRef;
const runPhase = ({programs, selection, load, save, ...selected}) => runRecordUpdateApprovalPhase({...selected,
  createDefinition: () => createDefinition(programs, selection),
  async load(name) {
    const value = await load(name);
    if (name === 'captured') originalRef = value.ref;
    return value;
  },
  async save(name, value) {
    if (name === 'submitted') originalRef = value.ref;
    await save(name, value);
  },
  observeClose: observation === undefined ? undefined : value => writeFile(`${prefix}.${phase}.close-${value.stage}.json`,
    JSON.stringify({...value, workObservation: observation.forOriginal(originalRef)}) + '\n', {mode: 0o600, flag: 'wx'}),
});
let outcome;
await runRecordApprovalCommand({argv: [phase, configuration, prefix],
  retainProgramInputs: process.env.ACTQL_RECORD_APPROVAL_REMOVE_PROGRAMS === '1',
  programDirectory: new URL(`../${connectorId}-approval/`, import.meta.url),
  connect: options => connect(observation === undefined ? options
    : {...options, installation: {...options.installation, observation: observation.connection}}),
  runPhase, createDefinition,
  log(value) {assert.equal(outcome, undefined); outcome = value;}});
assert.equal(outcome.publicClientClose, 'returned');
const work = observation?.forOriginal(originalRef);
if (work !== undefined) {
  assertRecordWorkflowWork(work, {phase,
    variant: process.env.ACTQL_RECORD_APPROVAL_MOCK_VARIANT || undefined});
}
const roots = credential === undefined ? [state] : [state, credential];
const before = await observeRecordApprovalDescriptors(roots);
assert.deepEqual(before.openPaths, []);
await setTimeout(2000);
const after = await observeRecordApprovalDescriptors(roots);
assert.deepEqual(after.openPaths, []);
console.log(JSON.stringify({...outcome, pid: process.pid, workObservation: work, descriptors: {before, after}}));
