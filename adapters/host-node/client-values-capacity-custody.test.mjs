import {publicationOriginalFixture} from './fixtures/local-publication-original.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {fundedClientPreparation} from './funded-client-preparation.fixture.mjs';
import {sourceFreeValuesPlan, sourceFreeValuesAdmissionEvidence} from './local-values-plan.mjs';
import {valuesHostPolicyOriginal, valuesExecutionContextCid} from './local-values-capacity.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const program = JSON.parse(await readFile(new URL('./fixtures/read-121.program.json', import.meta.url), 'utf8'));
const environmentWire = await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8');
const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
  'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
  false, false, true, false, false, false, false);
const control = runtimeCore(moon).publicationControl;
const scope = {namespaceId: 'values-capacity', authorityScopeCid: cid('a')};
const request = {kind: 'program', input: program, parameters: null};
const planFor = preparedProgram => sourceFreeValuesPlan({moon, control, preparedProgram, publicationOriginal: publicationOriginalFixture(moon, preparedProgram),
  ...scope, storeAuthorityCid: cid('7'), now: () => '2026-10-07T00:00:00.000Z'});

// Retained prior-format records keep their original explicit policy binding.
// Ordinary new Plans below do not invent this historical evidence field.
function priorProfilePlan(prepared) {
  const original = valuesHostPolicyOriginal(121);
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'values', {
    executionContextCid: valuesExecutionContextCid(scope.authorityScopeCid, original),
    hostPolicyCid: original.cid, expiresAt: '2098-01-01T00:00:00.000Z'});
  const runDefinition = control.defineCheckedClientCompiledRun(compiled, {
    namespaceId: scope.namespaceId, runId: 'prior-values-profile',
    createdAt: '2026-10-07T00:00:00.000Z', validUntil: '2098-01-01T00:00:00.000Z'});
  return {plan: {runDefinition}, evidence: Object.freeze({
    prepared: compiled.preparedEvidence.wire, authorization: compiled.authorization.wire,
    valuesHostPolicyOriginal: original})};
}

test('Embedded Local captures Values row selection once alongside the Host policy snapshot', async () => {
  let reads = 0;
  const installation = {hostCapacityPolicy: null,
    get valuesMaxRows() {
      reads++;
      if (reads !== 1) throw new Error('ValuesSelectionReadTwice');
      return 121;
    }};
  // The independently invalid Host policy stops before opening resources.
  // Its refusal must not be replaced by another read of the row selection.
  await assert.rejects(connectEmbeddedLocal({mode: 'local', owner: 'local', installation}),
    {code: 'InvalidInstalledHostCapacityPolicy'});
  assert.equal(reads, 1);
});

test('default Values capacity derives from input while an explicit insufficient ceiling rejects', async t => {
  const prepareStandard = await fundedClientPreparation(t, {moon, environment});
  const standard = await prepareStandard(request);
  assert.equal(moon.clientProgramValuesMaxRows(standard), 121);
  const standardPlan = planFor(standard);
  // Generic metadata retains one row collection and one order inventory.
  assert.equal(standardPlan.outputLimits.maxResultWorkspaceEntries, 2 * 121);
  const prepareShort = await fundedClientPreparation(t, {moon, environment, valuesMaxRows: 120});
  await assert.rejects(prepareShort(request), {code: 'ClientProgramUnsupported'});
  const prepareSelected = await fundedClientPreparation(t, {moon, environment, valuesMaxRows: 121});
  const selected = await prepareSelected(request);
  const plan = planFor(selected);
  assert.equal(plan.outputLimits.maxResultWorkspaceEntries, 2 * 121);
  assert.equal(plan.outputLimits.maxResultOrderWork, standardPlan.outputLimits.maxResultOrderWork);
  assert.equal(moon.clientProgramValuesMaxRows(standard), 121);
  assert.equal(moon.clientProgramValuesMaxRows(selected), 121);
  assert.deepEqual(Object.keys(sourceFreeValuesAdmissionEvidence(plan)).sort(), ['authorization', 'prepared'],
    'the selected ceiling is not a fabricated prior-format count proof');
});

test('retained prior Values profile custody rejects altered originals and a different Run context after restart',
  async t => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-values-custody-', label: 'Values profile custody'});
    const directory = scratch.path;
    const prepare = await fundedClientPreparation(t, {moon, environment, valuesMaxRows: 121});
    const prepared = await prepare(request);
    const {plan, evidence} = priorProfilePlan(prepared);
    const identity = moon.clientProgramRequestIdentity(prepared, scope.authorityScopeCid, 'saved-profile', cid('b'));
    const options = {namespaceId: scope.namespaceId, runDefinition: plan.runDefinition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
    let journal = openClientRequestJournal(directory);
    try {
      const mutations = [
        value => {value.valuesHostPolicyOriginal.cid = cid('9');},
        value => {value.valuesHostPolicyOriginal.wire = value.valuesHostPolicyOriginal.wire.replace('121', '120');},
        value => {value.valuesHostPolicyOriginal.wire += ' ';},
        value => {value.valuesHostPolicyOriginal.extra = true;},
        value => {value.prepared = JSON.stringify({...JSON.parse(value.prepared), host_policy_cid: cid('9')});},
        value => {value.authorization = JSON.stringify({...JSON.parse(value.authorization), host_policy_cid: cid('9')});},
        value => {
          // Even matching profile references cannot replace the Run's
          // authority/context binding with another current configuration.
          value.valuesHostPolicyOriginal = valuesHostPolicyOriginal(122);
          value.prepared = JSON.stringify({...JSON.parse(value.prepared), host_policy_cid: value.valuesHostPolicyOriginal.cid});
          value.authorization = JSON.stringify({...JSON.parse(value.authorization), host_policy_cid: value.valuesHostPolicyOriginal.cid});
        },
      ];
      for (const mutate of mutations) {
        const proposed = structuredClone(evidence); mutate(proposed);
        assert.throws(() => journal.acceptDefinition(identity,
          {...options, runAdmissionEvidence: proposed}, moon, control),
        {code: 'InvalidClientRunAdmissionEvidence'});
        assert.equal(journal.lookup({...scope, requestId: 'saved-profile'}, moon), undefined);
      }
      const saved = journal.acceptDefinition(identity,
        {...options, runAdmissionEvidence: evidence}, moon, control);
      journal.close(); journal = openClientRequestJournal(directory);
      assert.deepEqual(journal.lookupRunDefinition(saved.ref, moon, control).runAdmissionEvidence, evidence);
      const repeated = await journal.admitOrLookupDefinition(identity, {...options,
        issueDefinition() {throw new Error('OriginalProfileMustNotBeReissued');}}, moon, control);
      assert.deepEqual(repeated.ref, saved.ref);
      assert.deepEqual(repeated.runAdmissionEvidence, evidence);
      journal.close(); journal = undefined;
      const db = new DatabaseSync(join(directory, 'client-requests.sqlite3'));
      try {
        const changed = structuredClone(evidence);
        changed.valuesHostPolicyOriginal.wire = changed.valuesHostPolicyOriginal.wire.replace('121', '120');
        db.prepare('UPDATE client_requests SET run_admission_evidence_json=?').run(JSON.stringify(changed));
      } finally {db.close();}
      journal = openClientRequestJournal(directory);
      assert.throws(() => journal.lookupRunDefinition(saved.ref, moon, control), {code: 'ClientRequestJournalCorrupt'});
      scratch.passed();
    } finally {journal?.close();}
  });
