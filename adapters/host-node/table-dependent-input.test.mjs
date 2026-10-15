// Real checked/captured Values -> Result import -> private Table input.
// No Source, credential, physical Table worker or Effect apply is executed.
import assert from 'node:assert/strict';
import test from 'node:test';
import {exerciseEffectSourceSet} from './client-program-bridge.test.mjs';
import {preparePinnedEffectSourceSet} from './effect-input-export.mjs';
import {checked} from '../host-common/runtime-result.mjs';

test('dependent private Table members retain their own occurrence beside an identical public Result', async t => {
  await exerciseEffectSourceSet(t, {privateTableInput: true,
    transformDocument(document) {
      const consumer = document.stages[0], producer = structuredClone(consumer);
      producer.id = 'producer'; delete producer.effects; delete producer.table_inputs;
      consumer.inputs = {rows: {result: {stage: 'producer', result: 'rows'}}};
      consumer.steps = [{from: 'rows', select: {id: 'id'}, as: 'selected'}];
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
