import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {sourceFreeValuesPlan, sourceFreeValuesAdmissionEvidence} from './local-values-plan.mjs';
import {valuesHostPolicyOriginal} from './local-values-capacity.mjs';
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
const planFor = preparedProgram => sourceFreeValuesPlan({moon, control, preparedProgram,
  ...scope, storeAuthorityCid: cid('7'), now: () => '2026-10-07T00:00:00.000Z'});

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

test('default and insufficient Values ceilings still reject the valid 121-row Program', () => {
  const standard = installNodeClientProgramPreparation({moon, environment})(request);
  assert.equal(moon.clientProgramValuesMaxRows(standard), 100);
  assert.throws(() => planFor(standard), {code: 'RunHostCompilationRejected'});
  const short = installNodeClientProgramPreparation({moon, environment, valuesMaxRows: 120})(request);
  assert.throws(() => planFor(short), {code: 'RunHostCompilationRejected'});
  const selected = installNodeClientProgramPreparation({moon, environment, valuesMaxRows: 121})(request);
  const plan = planFor(selected);
  assert.equal(plan.outputLimits.maxResultWorkspaceEntries, 121);
  assert.equal(plan.outputLimits.maxResultOrderWork, 10000);
  assert.equal(moon.clientProgramValuesMaxRows(standard), 100);
  assert.equal(sourceFreeValuesAdmissionEvidence(plan).valuesHostPolicyOriginal.wire,
    '{"max_rows":121,"name":"source-free-values","version":"actql-installed-local-policy/0.1"}');
});

test('Values profile custody rejects altered originals and a different Run context, and preserves its original after restart',
  async () => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-values-custody-', label: 'Values profile custody'});
    const directory = scratch.path;
    const prepared = installNodeClientProgramPreparation({moon, environment, valuesMaxRows: 121})(request);
    const plan = planFor(prepared);
    const evidence = sourceFreeValuesAdmissionEvidence(plan);
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
