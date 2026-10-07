import assert from 'node:assert/strict';
import { fieldLayout } from './native-extent.mjs';
// Pinned 64-bit Native allocation requests, reviewed against constructor
// store instructions. These exclude allocator overhead and shared referents.
export const parentFields = {
  owner: Array(6).fill('ref'),
  state: ['ref','ref','ref','i32','i32','i32','ref'],
  startEnvironment: [...Array(4).fill('ref'),'i32',...Array(3).fill('ref'),'i32'],
  advance: ['ref','ref','i32','ref','ref','ref','i32','ref','ref','ref','ref','i32'],
  cancel: Array(4).fill('ref'), stopped: Array(2).fill('ref'),
  cleanup: Array(5).fill('ref'), childWorkIssue: Array(2).fill('ref'),
};
export function parentStartupLayout() {
  const blocks = Object.fromEntries(Object.entries(parentFields)
    .map(([name, fields]) => [name, 8 + fieldLayout(fields).payloadBytes]));
  // used: Int64; cleanup_index: Int; cancelled/terminal/reclaimed: Bool.
  // Scalar Ref constructor requests were inspected separately from GC layouts.
  const references = 16 + 4 * 12;
  const reportedWork = 16;
  const callbacks = ['advance','cancel','stopped','cleanup','childWorkIssue']
    .reduce((sum,name) => sum + blocks[name],0);
  const children = 24 + 8 + 8;
  const completed = 24 + 8 + 8 * 2;
  const knownOwnedLower = references + reportedWork + blocks.owner + blocks.state + callbacks + children + completed;
  return {blocks,references,reportedWork,callbacks,children,completed,knownOwnedLower,
    startupLower:knownOwnedLower + blocks.startEnvironment,
    fullParentUpper:false,completePipelineUpper:false};
}
export function inspectParentStartup(fact,target) {
  assert.equal(target,'native','Native parent layout cannot apply to a portable target');
  const layout=parentStartupLayout();
  assert.equal(fact.kind,'startup');assert.equal(fact.count,2);
  assert.equal(fact.state.requestedBytes,layout.blocks.state);
  assert.equal(fact.callbacks.length,5);
  assert.deepEqual(fact.callbacks.map(c=>c.requestedBytes),
    ['advance','cancel','stopped','cleanup','childWorkIssue'].map(n=>layout.blocks[n]));
  assert.equal(fact.environments.length,1);
  assert.equal(fact.environments[0].requestedBytes,layout.blocks.startEnvironment);
  // Actual capture identities and Array observations are separate admission
  // obligations; this arithmetic alone is not implementation correspondence.
  return {nativeStartupRequestedLower:layout.startupLower,componentAllowance:512,
    componentBoundContradicted:layout.startupLower>512,
    totalReservationViolationProven:false,completePipelineUpper:false};
}
