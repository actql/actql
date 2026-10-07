import test from 'node:test';
import assert from 'node:assert/strict';
import {exerciseEffectSourceSet} from './client-program-bridge.test.mjs';
import {authorTableOperationPreview} from './table-operation-preview.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const targetRef = 'connector://table/catalog';
const mappingRef = 'mapping:table.catalog.v1';

for (const empty of [false,true]) {
  test(`installed Table authoring ${empty ? 'empty' : 'nonempty'} uses checked whole-Relation operations`,
    async t => exerciseEffectSourceSet(t, {empty, target: targetRef, mappingRef,
      minimumApproval: 'required', onTablePreview: async f => {
        const members = f.sources.members.map((source,index) => ({
          stageIndex: 0, effectId: index === 0 ? 'first' : 'second',
          payload: source.payload,
          target: {targetRef, mappingRef, mappingCid: f.fixture.mappingCid,
            action: 'create', catalogCid: cid('3'), namespace: ['analytics'],
            tableName: `rows_${index}`, expectedTable: null,
            capabilityCid: cid('d'), permissions: ['write'],
            footprint: f.template.effects[index].write_footprint},
        }));
        const options = {moon: f.moon, control: f.sourceControl,
          prepared: f.prepared, inputs: f.inputs, checkedHost: f.checkedHost,
          requestScope: f.scope,
          context: {runDefinition: f.definition, runInvocation: f.invocation,
            compiledPlan: f.evidence[3], storeAuthorityCid: f.store.storeAuthorityCid},
          members, limits: {maxMembers: 2, maxFields: 100, planWork: 1000,
            material: f.tableLimits,
            preview: {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 16},
            key: {maxBytes: 128, maxNodes: 8, maxDepth: 3}}};
        const authored = authorTableOperationPreview(options);
        // The independent, pre-existing fixture authored these original
        // requests before invoking the production authoring connection.
        assert.deepEqual(authored.operations, f.operations);
        const body = JSON.parse(authored.wire);
        assert.equal(body.effects.length, 2);
        assert.equal(body.executed, false);
        assert.notEqual(authored.operations[0].effect_identity_cid,
          authored.operations[1].effect_identity_cid);
        assert.notEqual(authored.operations[0].request_cid,
          authored.operations[1].request_cid);
        for (const [index,member] of body.effects.entries()) {
          assert.equal(member.count, 1);
          assert.equal(member.max_items, 1);
          assert.equal(member.approval, 'required');
          assert.equal(member.effect_kind, 'store');
          assert.deepEqual(member.changes[0].before, {state: 'not_applicable'});
          assert.deepEqual(member.changes[0].after, {state: 'not_applicable'});
          assert.deepEqual(member.changes[0].target_guard, {state: 'not_applicable'});
          assert.deepEqual(member.changes[0].intended_changes.value, f.operations[index]);
          assert.equal(member.changes[0].target_row_identity, f.operations[index].request_cid);
          assert.equal(authored.keys[index].length, 1);
          assert.equal(f.sourceControl.tablePreviewLedgerBinding(
            authored.tablePreviews[index]).operationWire, authored.tableInputs[index].wire);
        }
        assert.equal(authorTableOperationPreview(options).wire, authored.wire);
        const replaceMembers = members.map(member => ({...member,
          target: {...member.target, action: 'replace', expectedTable: {
            table_uuid: '11111111-2222-3333-4444-555555555555', generation_cid: cid('b')}}}));
        const replaced = authorTableOperationPreview({...options, members: replaceMembers});
        assert.notEqual(replaced.wire, authored.wire);
        for (const member of JSON.parse(replaced.wire).effects) {
          assert.deepEqual(member.changes[0].target_guard,
            {state: 'version', version_cid: cid('b')});
        }
        for (const field of ['targetRef','mappingRef','mappingCid']) {
          const foreign = members.map(member => ({...member, target: {...member.target,
            [field]: field === 'mappingCid' ? cid('9') : 'foreign'}}));
          assert.throws(() => authorTableOperationPreview({...options, members: foreign}),
            {code: 'TablePreviewMappingNotInstalled'});
        }
        assert.throws(() => authorTableOperationPreview({...options, members: [...members].reverse()}),
          {code: 'TablePreviewMappingNotInstalled'});
        assert.throws(() => authorTableOperationPreview({...options,
          members: members.map(member => ({...member, payload: {...member.payload,
            localResultArtifact: {...member.payload.localResultArtifact}}}))}), {name: 'TypeError'});
        assert.throws(() => authorTableOperationPreview({...options,
          limits: {...options.limits, maxMembers: 1}}), {code: 'InvalidTablePreviewConfiguration'});
      }}));
}
