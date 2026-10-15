// Real checked/captured Values -> Result import -> private Table input.
// No Source, credential, physical Table worker or Effect apply is executed.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {exerciseEffectSourceSet} from './client-program-bridge.test.mjs';
import {preparePinnedEffectSourceSet, preparePinnedEffectDependencyInventory} from './effect-input-export.mjs';
import {checked} from '../host-common/runtime-result.mjs';

test('dependent private Table members retain their own occurrence beside an identical public Result', async t => {
  await exerciseEffectSourceSet(t, {privateTableInput: true,
    transformDocument(document) {
      const consumer = document.stages[0], producer = structuredClone(consumer);
      producer.id = 'producer'; delete producer.effects; delete producer.table_inputs;
      consumer.inputs = {rows: {result: {stage: 'producer', result: 'rows'}}};
      consumer.steps = [{from: 'rows', select: ['id'], as: 'selected'}];
      document.stages.unshift(producer);
    },
    async onCompletedTableRun({moon, checkedHost, options, sourceControl}) {
      const inputs = checked(moon.clientProgramPinEffectSources(checkedHost, 64));
      let sources;
      try {
        assert.equal(moon.clientProgramEffectInputCount(inputs), 2);
        assert(moon.clientProgramEffectTableInputAt(inputs, 0));
        assert.equal(moon.clientProgramEffectInputAt(inputs, 0), undefined);
        assert.equal(moon.clientProgramEffectLocalResultCount(inputs), 2);
        // Equal rows and a same-named public Result do not substitute for the
        // private Table namespace, occurrence or borrow.
        for (let result = 0; result < 2; result++) {
          assert.equal(moon.clientProgramEffectLocalResultMatchesMember(inputs, result, 0), false);
        }
        sources = await preparePinnedEffectSourceSet({...options, inputs,
          maxGroupingWork: (2 + 64) * 2,
          localEvidenceContext: {...options.localEvidenceContext,
            sourceFreeDependencyClosure: true, retentionDependencies: []}});
        assert.equal(sources.members.length, 2);
        for (const {payload} of sources.members) {
          assert.equal(JSON.parse(payload.localResultDefinition.wire).version,
            'actql-local-table-input-definition/0.1');
          assert.equal(JSON.parse(payload.localResultArtifact.wire).actual_row_count, 2);
        }
        assert.equal(sources.members[0].payload, sources.members[1].payload,
          'The same checked private input may share its actual borrow');
      } finally {
        for (const payload of sources?.payloads ?? []) {
          if (payload.prepared.status().pending) await payload.prepared.release();
        }
        assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
      }
    }});
});

// Original policy preimages use the same closed contracts as installed local
// retention. Their identities are independently hashed, not read from exports.
function dependencyPolicies() {
  const body = (kind, value) => ({kind, wire: canonicalText(value),
    cid: `sha256:${createHash('sha256').update(canonicalText(value)).digest('hex')}`});
  const installed = (kind, name) => body(kind,
    {version: 'actql-installed-local-policy/0.1', name});
  const dataPolicy = body('data_policy', {
    version: 'actql-effective-data-policy/0.1', classification: 'unknown',
    source_data_policy_cids: [], source_response_policy_cids: [], unknown_provenance: true});
  const contracts = [installed('retention_contract', 'local-result-retention'),
    installed('metadata_retention_policy', 'local-result-metadata'),
    installed('clock_contract', 'local-clock')];
  const preimage = {version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: contracts[0].cid, effective_data_policy_cid: dataPolicy.cid,
    available_until: '2026-09-24T01:00:00.000Z', delete_by: '2026-09-24T02:00:00.000Z',
    extension_ceiling_at: '2026-09-24T03:00:00.000Z',
    metadata_retention_policy_cid: contracts[1].cid,
    metadata_delete_by: '2026-09-24T04:00:00.000Z', clock_contract_cid: contracts[2].cid};
  const retention = body('result_retention_policy', preimage);
  retention.wire = canonicalText({...preimage, effective_retention_policy_cid: retention.cid});
  return {dataPolicy, retention, bodies: [dataPolicy, retention, ...contracts]};
}

test('dependent private Table members retain a complete typed inventory and reject foreign provenance', async t => {
  const policy = dependencyPolicies();
  await exerciseEffectSourceSet(t, {privateTableInput: true, dependencyPolicy: policy,
    transformDocument(document) {
      const consumer = document.stages[0], producer = structuredClone(consumer);
      producer.id = 'producer'; delete producer.effects; delete producer.table_inputs;
      consumer.inputs = {rows: {result: {stage: 'producer', result: 'rows'}}};
      consumer.steps = [{from: 'rows', select: ['id'], as: 'selected'}];
      document.stages.unshift(producer);
    },
    async onCompletedTableRun({moon, checkedHost, options, sourceControl}) {
      const inputs = checked(moon.clientProgramPinEffectSources(checkedHost, 64));
      const limits = options.contractLimits;
      let sources, privateIssuances = 0;
      const control = Object.freeze({...sourceControl,
        issueDependentLocalEffectTableArtifact(...args) {
          const [owner, actualInputs, member, importing, dependency, definition,
            receipt, retention, context, bounds] = args;
          assert.throws(() => sourceControl.issueDependentLocalEffectTableArtifact(
            owner, actualInputs, member, importing, {...dependency}, definition,
            receipt, retention, context, bounds), /Foreign private Table dependency/);
          assert.throws(() => sourceControl.issueSourceFreeLocalEffectTableArtifact(
            owner, actualInputs, member, importing, definition, dependency.invocation,
            receipt, retention, context, bounds), {code: 'MoonBitHostFailure'},
          'an imported Unit cannot be reissued as source-free');
          assert.throws(() => sourceControl.issueDependentLocalEffectTableArtifact(
            owner, actualInputs, 2, importing, dependency, definition,
            receipt, retention, context, bounds), {code: 'MoonBitHostFailure'},
          'a real export does not grant a foreign member');
          privateIssuances++;
          return sourceControl.issueDependentLocalEffectTableArtifact(...args);
        }});
      const prepare = signal => preparePinnedEffectSourceSet({...options, control, inputs, signal,
        maxGroupingWork: (2 + 64) * 2,
        localEvidenceContext: {...options.localEvidenceContext,
          sourceFreeDependencyClosure: true, retentionDependencies: policy.bodies}});
      try {
        const abort = new AbortController(); abort.abort(new Error('IndependentCancelled'));
        await assert.rejects(prepare(abort.signal), /IndependentCancelled/);
        assert.equal(privateIssuances, 0, 'cancel before export issues no private artifact');
        sources = await prepare();
        assert.equal(privateIssuances, 1, 'one live private borrow for two members');
        const wire = preparePinnedEffectDependencyInventory({sources, store: options.store,
          control, contractLimits: limits});
        const inventory = JSON.parse(wire);
        const entries = kind => inventory.filter(entry => entry.kind === kind);
        for (const kind of ['local_table_input_definition', 'table_input_artifact',
          'table_input_derivation', 'table_input_ordering', 'result_artifact',
          'local_manifest', 'result_import_observation']) assert.equal(entries(kind).length, 1, kind);
        const table = sources.members[0].payload;
        assert.equal(entries('table_input_artifact')[0].cid, table.localResultArtifact.identity);
        assert.equal(sources.members[1].payload, table);
        const relation = table.dependencyBodies.find(entry => entry.kind === 'relation_value');
        assert.deepEqual(JSON.parse(relation.wire).value, [{id: 1}, {id: 2}]);
        assert.deepEqual(JSON.parse(table.dependencyBodies.find(entry => entry.kind === 'relation_schema').wire),
          {id: {type: 'number', nullable: false}});
        const reissue = values => control.prepareLocalEffectDependencyInventory(
          sources.members.map(({payload}) => payload.localResultArtifact),
          values.map(entry => ({kind: entry.kind, cid: entry.cid, wire: canonicalText(entry.body)})), limits);
        assert.equal(reissue(inventory), wire);
        for (const kind of ['local_table_input_definition', 'table_input_derivation',
          'table_input_ordering', 'result_import_observation', 'local_manifest']) {
          assert.throws(() => reissue(inventory.filter(entry => entry.kind !== kind)),
            {code: 'MoonBitHostFailure'}, `missing ${kind} remains a refusal`);
        }
        const impostor = structuredClone(inventory);
        impostor.find(entry => entry.kind === 'table_input_artifact').kind = 'result_artifact';
        assert.throws(() => reissue(impostor), {code: 'MoonBitHostFailure'},
          'equal rows do not merge the private Table and public Result namespaces');
      } finally {
        for (const payload of sources?.payloads ?? []) {
          if (payload.prepared.status().pending) await payload.prepared.release();
        }
        assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
      }
    }});
});


test('dependent private Table members retain distinct equal-valued declarations and reject swapped exports', async t => {
  await exerciseEffectSourceSet(t, {privateTableInput: true,
    transformDocument(document) {
      const consumer = document.stages[0], producer = structuredClone(consumer);
      producer.id = 'producer'; delete producer.effects; delete producer.table_inputs;
      consumer.inputs = {rows: {result: {stage: 'producer', result: 'rows'}}};
      consumer.steps = [{from: 'rows', select: ['id'], as: 'selected'}];
      consumer.table_inputs.other = structuredClone(consumer.table_inputs.rows);
      consumer.effects.second.store.from = {table_input: 'other'};
      document.stages.unshift(producer);
    },
    async onCompletedTableRun({moon, checkedHost, options, sourceControl}) {
      const inputs = checked(moon.clientProgramPinEffectSources(checkedHost, 64));
      let sources, first, exports = 0;
      const control = Object.freeze({...sourceControl,
        issueDependentLocalEffectTableArtifact(...args) {
          if (first === undefined) first = args;
          else {
            // Both declarations project the exact same rows, but their
            // original Table occurrence/borrow and live receipts are distinct.
            const foreignDefinition = [...args]; foreignDefinition[5] = first[5];
            assert.throws(() => sourceControl.issueDependentLocalEffectTableArtifact(...foreignDefinition),
              {code: 'MoonBitHostFailure'});
            const foreignExport = [...args]; foreignExport[3] = first[3];
            assert.throws(() => sourceControl.issueDependentLocalEffectTableArtifact(...foreignExport),
              {code: 'MoonBitHostFailure'});
          }
          exports++;
          return sourceControl.issueDependentLocalEffectTableArtifact(...args);
        }});
      try {
        assert.equal(moon.clientProgramEffectInputsShareView(inputs, 0, 1), false);
        sources = await preparePinnedEffectSourceSet({...options, inputs, control,
          maxGroupingWork: (2 + 64) * 2,
          localEvidenceContext: {...options.localEvidenceContext,
            sourceFreeDependencyClosure: true, retentionDependencies: []}});
        assert.equal(exports, 2);
        const left = sources.members[0].payload, right = sources.members[1].payload;
        assert.notEqual(left, right);
        assert.equal(left.summary.logicalCid, right.summary.logicalCid);
        assert.notEqual(left.localResultDefinition.identity, right.localResultDefinition.identity);
        assert.notEqual(left.localResultArtifact.identity, right.localResultArtifact.identity);
        assert.equal(left.summary.rowCount, 2); assert.equal(right.summary.rowCount, 2);
      } finally {
        for (const payload of sources?.payloads ?? []) {
          if (payload.prepared.status().pending) await payload.prepared.release();
        }
        assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
      }
    }});
});


test('source-free private Table dependency control preserves the original no-import issuer', async t => {
  await exerciseEffectSourceSet(t, {privateTableInput: true,
    async onCompletedTableRun({moon, checkedHost, options}) {
      const inputs = checked(moon.clientProgramPinEffectSources(checkedHost, 64));
      let sources;
      try {
        sources = await preparePinnedEffectSourceSet({...options, inputs,
          maxGroupingWork: (2 + 64) * 2});
        assert.equal(sources.members.length, 2);
        assert.equal(sources.members[0].payload, sources.members[1].payload);
        const payload = sources.members[0].payload;
        assert.equal(payload.summary.rowCount, 2);
        assert.deepEqual(payload.summary.fields, ['id']);
        assert.deepEqual(JSON.parse(payload.localResultArtifact.derivationWire).input_relation_cids, []);
        assert.equal(JSON.parse(payload.localResultDefinition.wire).version,
          'actql-local-table-input-definition/0.1');
        assert.equal(payload.dependencyBodies, undefined,
          'the ordinary source-free path does not fabricate an import inventory');
      } finally {
        for (const payload of sources?.payloads ?? []) {
          if (payload.prepared.status().pending) await payload.prepared.release();
        }
        assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
      }
    }});
});
