import assert from 'node:assert/strict';
import {setTimeout} from 'node:timers/promises';
import {writeFile} from 'node:fs/promises';
import {connect} from '@actql/node';
import type {EmbeddedLocalOptions, RunReference} from '@actql/node';
import {runRecordApprovalCommand} from './command.mjs';
import type {ConnectorPhaseOptions} from './command.mjs';
import {salesforceUpdateCase, hubspotUpdateCase, kintoneUpdateCase} from './cases.mjs';
import {observeRecordApprovalDescriptors} from './scoped-fds.fixture.mjs';
import {runRecordUpdateApprovalPhase, recordApprovalReplyLossExpectationFromEnvironment} from './workflow.mjs';
import {workflowWorkObservation, assertRecordWorkflowWork} from '../../../adapters/host-node/fixtures/work-observation.fixture.mjs';

type WorkSelection = Parameters<typeof assertRecordWorkflowWork>[1];

const [connectorId, phase, configuration, prefix, state, credential] = process.argv.slice(2);
const replyLossExpectation = recordApprovalReplyLossExpectationFromEnvironment();
const sourceSchemaWire = process.env.ACTQL_RECORD_APPROVAL_SOURCE_SCHEMA;
const createDefinition = {salesforce: salesforceUpdateCase,
  hubspot: hubspotUpdateCase, kintone: kintoneUpdateCase}[connectorId as 'salesforce' | 'hubspot' | 'kintone'];
assert.equal(typeof createDefinition, 'function');
const observation = process.env.ACTQL_RECORD_APPROVAL_MOCK_CONNECTOR === connectorId
  ? workflowWorkObservation({trackOriginal: true}) : undefined;
let originalRef: RunReference | undefined;
const runPhase = ({programs, selection, load, save, ...selected}: ConnectorPhaseOptions<Parameters<typeof createDefinition>[1]>) =>
  runRecordUpdateApprovalPhase({...selected,
  replyLossExpectation,
  createDefinition: selected.definition === undefined ? () => createDefinition(programs!, selection!) : undefined,
  async load(name) {
    const value = await load(name);
    if (name === 'captured') originalRef = (value as {ref: RunReference}).ref;
    return value;
  },
  async save(name, value) {
    if (name === 'submitted') originalRef = value.ref as RunReference;
    await save(name, value);
  },
  observeClose: observation === undefined && replyLossExpectation === undefined && selected.decision !== 'rejected' ? undefined
    : value => writeFile(`${prefix}.${phase}.close-${value.stage}.json`,
      JSON.stringify({...value, ...(observation === undefined ? {}
        : {workObservation: observation.forOriginal(originalRef!)})}) + '\n', {mode: 0o600, flag: 'wx'}),
});
let outcome: Record<string, unknown> | undefined;
await runRecordApprovalCommand({argv: [phase, configuration, prefix],
  retainProgramInputs: process.env.ACTQL_RECORD_APPROVAL_REMOVE_PROGRAMS === '1',
  fixtureReplyLossExpectation: replyLossExpectation,
  fixtureSourceSchema: sourceSchemaWire === undefined ? undefined : JSON.parse(sourceSchemaWire),
  programDirectory: new URL(`../${connectorId}-approval/`, import.meta.url),
  connect: options => connect(observation === undefined ? options
    : {...(options as EmbeddedLocalOptions), installation: {
      ...(options as EmbeddedLocalOptions).installation, observation: observation.connection}}),
  runPhase, createDefinition,
  log(value) {assert.equal(outcome, undefined); outcome = value;}});
assert.equal(outcome!.publicClientClose, 'returned');
const work = observation?.forOriginal(originalRef!);
if (work !== undefined) {
  assertRecordWorkflowWork(work, {phase,
    variant: process.env.ACTQL_RECORD_APPROVAL_MOCK_VARIANT || undefined} as WorkSelection);
}
const roots = credential === undefined ? [state] : [state, credential];
const before = await observeRecordApprovalDescriptors(roots);
assert.deepEqual(before.openPaths, []);
await setTimeout(2000);
const after = await observeRecordApprovalDescriptors(roots);
assert.deepEqual(after.openPaths, []);
console.log(JSON.stringify({...outcome, ...(replyLossExpectation === undefined ? {} : {replyLossExpectation}),
  pid: process.pid, workObservation: work, descriptors: {before, after}}));
