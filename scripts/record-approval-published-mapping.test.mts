import assert from 'node:assert/strict';
import test from 'node:test';
import {bindPublishedRecordApprovalCase} from './fixtures/record-approval/command.mjs';
import {admitAuthoredRecordApprovalCase} from './fixtures/record-approval/workflow.mjs';

const cid = (mark: string) => 'sha256:' + mark.repeat(64);
const first = 'connector://salesforce/Account', second = 'connector://salesforce/Contact';
const targets = [first, second, first];
const ids = ['a_first', 'b_middle', 'c_last'];
const original = Object.fromEntries(ids.map((id, index) => [id, {update: {target: targets[index],
  from: {result: 'rows'}, id: 'Id', set: {Name: {literal: 'Selected'}}}}]));
const template = {version: 'actql/0.1', stages: [{id: 'apply', effects: original}], results: {}};
const parts = {format: 'json', document: JSON.stringify(template), resultName: 'main',
  parameters: {}, parameterDeclarations: {}};
const authored = admitAuthoredRecordApprovalCase({name: 'same authored case',
  effect: {...parts, expectedRows: []}, read: {...parts, beforeRows: [], afterRows: []},
  review: {effects: ids.map((effectId, index) => ({effectId, kind: 'update', target: targets[index],
    rows: [{identity: effectId, before: {Name: effectId}, changes: {Name: 'Selected'}}]}))}});
const publication = {generationCid: cid('a'), mappings: [
  {resource: 'Contact', kind: 'update', mappingRef: 'mapping:salesforce/contact-b.v1', mappingCid: cid('b')},
  {resource: 'Account', kind: 'update', mappingRef: 'mapping:salesforce/account-c.v1', mappingCid: cid('c')},
]};

test('ordered author binding selects the published resource and kind while preserving Program and Results', () => {
  const retained = structuredClone(authored);
  const bound = bindPublishedRecordApprovalCase(authored, 'salesforce', publication);
  assert.equal(bound.generationCid, publication.generationCid);
  assert.deepEqual(bound.members.map(item => item.effectId), ids);
  assert.deepEqual(bound.members.map(item => item.mappingCid), [cid('c'), cid('b'), cid('c')]);
  const issued = JSON.parse(bound.definition.effect.document);
  for (const [id, member] of bound.members.entries()) {
    assert.equal(issued.stages[0].effects[ids[id]].update.mapping, member.mappingRef);
    delete issued.stages[0].effects[ids[id]].update.mapping;
  }
  assert.deepEqual(issued, template);
  assert.deepEqual(bound.definition.review, authored.review);
  assert.deepEqual(bound.definition.effect.expectedRows, authored.effect.expectedRows);
  assert.deepEqual(authored, retained);
});

test('ordered binding refuses an already bound case, foreign targets and missing or ambiguous publication', () => {
  const bound = bindPublishedRecordApprovalCase(authored, 'salesforce', publication);
  assert.throws(() => bindPublishedRecordApprovalCase(bound.definition, 'salesforce', publication),
    /ForeignOrderedRecordMappingSlot/u);
  assert.throws(() => bindPublishedRecordApprovalCase(authored, 'foreign', publication),
    /ForeignOrderedRecordMappingSlot/u);
  for (const mappings of [[publication.mappings[0]], [...publication.mappings, publication.mappings[1]]]) {
    assert.throws(() => bindPublishedRecordApprovalCase(authored, 'salesforce', {...publication, mappings}),
      /MissingOrAmbiguousPublishedRecordMapping/u);
  }
});
