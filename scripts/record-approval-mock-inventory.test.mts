import assert from 'node:assert/strict';
import test from 'node:test';
import {recordApprovalMockInventory, recordApprovalMockProjectFiles, recordApprovalMockResource}
  from './fixtures/record-approval/mock-project.mjs';

const target = {ticket_key: '9007199254740993', note: 'original', owner: 'one'};
const deleting = {ticket_key: '9007199254740994', owner: 'two'};
const control = {ticket_key: 'hold', note: 'untouched', owner: 'control'};
const inserted = {ticket_key: 'new-ticket', note: 'accepted', owner: 'three'};

function project() {
  const files = recordApprovalMockProjectFiles({
    connection: 'external', resource: 'tickets', alias: 'external.tickets', identity: 'ticket_key',
    fields: ['note', 'owner'], schema: {
      ticket_key: {type: 'string', nullable: false}, note: {type: 'string', nullable: true},
      owner: {type: 'string', nullable: false},
    },
    rows: [target, deleting, control], updatePermission: 'write', observePermission: 'read',
  });
  return recordApprovalMockResource(files, 'external');
}

test('Mock expectations bind the declared schema and independent control across three ordered writes', () => {
  const original = project();
  const result = recordApprovalMockInventory(original, 'hold', [
    {operation: 'update', key: target.ticket_key, before: target, after: {...target, note: null}},
    {operation: 'delete', key: deleting.ticket_key, before: deleting, after: null},
    {operation: 'create', key: inserted.ticket_key, before: null, after: inserted},
  ]);
  assert.equal(result.approvedWrites, 3);
  assert.deepEqual(result.initial.external.tickets.rows, [target, deleting, control]);
  assert.deepEqual(result.changed.external.tickets.rows, [{...target, note: null}, control, inserted]);
  assert(!Object.hasOwn(result.initial.external.tickets.rows[1], 'note'));
  assert(Object.hasOwn(result.changed.external.tickets.rows[0], 'note'));
});

test('Mock expectations refuse foreign predecessors, the control, and a replaced key without changing the initial inventory', () => {
  const original = project();
  assert.throws(() => recordApprovalMockInventory(original, 'hold', [
    {operation: 'delete', key: deleting.ticket_key, before: {...deleting, note: null}, after: null},
  ]), /original Mock predecessor/u);
  assert.throws(() => recordApprovalMockInventory(original, 'hold', [
    {operation: 'delete', key: control.ticket_key, before: control, after: null},
  ]), /control row/u);
  assert.throws(() => recordApprovalMockInventory(original, 'hold', [
    {operation: 'update', key: target.ticket_key, before: target, after: inserted},
  ]), /same Mock row key/u);
  assert.throws(() => recordApprovalMockInventory(original, 'hold', [
    {operation: 'update', key: target.ticket_key, before: {...target, note: null}, after: target},
    {operation: 'update', key: target.ticket_key, before: target, after: {...target, note: null}},
  ]), /original Mock predecessor/u);
  assert.deepEqual(original.rows, [target, deleting, control]);
});
