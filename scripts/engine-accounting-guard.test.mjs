import test from 'node:test';
import assert from 'node:assert/strict';
import {workspaceCustodyMutation} from './engine-accounting-guard.mjs';

test('workspace custody comparisons do not count as assignments', () => {
  for (const source of [
    'if cursor.workspace.live == 0 { None }',
    'if workspace.live==expected { release() }',
    'assert_true(workspace.live != 0)',
    'workspace.live <= limit',
    'workspace.live >= minimum',
    'let live = workspace.live',
  ]) assert.doesNotMatch(source, workspaceCustodyMutation);
});

test('workspace custody assignments are rejected with each guarded operator', () => {
  for (const operator of ['=', '+=', '-=']) {
    for (const spacing of ['', ' ', '\n  ']) {
      const source = `cursor.workspace.live${spacing}${operator} 0`;
      assert.match(source, workspaceCustodyMutation);
    }
  }
  assert.match('if workspace.live == 0 { workspace.live = count }',
    workspaceCustodyMutation);
});
