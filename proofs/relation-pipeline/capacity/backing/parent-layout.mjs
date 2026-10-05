import assert from 'node:assert/strict';
import { fieldLayout } from './native-extent.mjs';
// Conditional pinned 64-bit native layout. Code pointers have the same width
// as references, but the GC descriptor omits them. This is an input model,
// not a maximum obtained by measuring the investigation fixture.
export const parentFields = {
  owner: Array(6).fill('ref'),
  startEnvironment: [...Array(9).fill('ref'), 'i32', ...Array(3).fill('ref'), 'i32'],
  advance: [...Array(10).fill('ref'), 'i32'],
  cancel: Array(4).fill('ref'), stopped: Array(2).fill('ref'),
  cleanup: Array(7).fill('ref'), childWorkIssue: Array(2).fill('ref'),
};
export function parentStartupLayout() {
  const blocks = Object.fromEntries(Object.entries(parentFields)
    .map(([name, fields]) => [name, 8 + fieldLayout(fields).payloadBytes]));
  // Three pointer Refs, two Int Refs, four Bool Refs and one Int64 Ref.
  // Scalar Ref payloads need at least their declared field width, even if
  // a compiler adds further padding. This is a lower bound for that group.
  const references = 3 * 16 + 2 * 12 + 4 * 12 + 16;
  const reportedWork = 8 + 8;
  const callbacks = ['advance', 'cancel', 'stopped', 'cleanup', 'childWorkIssue']
    .reduce((sum, name) => sum + blocks[name], 0);
  const children = 24 + 8 + 8; // Array owner and initial one-reference buffer.
  const completed = 24 + 8 + 8 * 2; // Fixed two-child nullable output slots.
  return { blocks, references, reportedWork, callbacks, children, completed,
    knownOwnedLower: references + reportedWork + blocks.owner + callbacks + children + completed,
    startupLower: references + reportedWork + blocks.owner + callbacks + children + completed + blocks.startEnvironment,
    fullParentUpper: false, completePipelineUpper: false };
}
export function inspectParentStartup(fact, target) {
  assert.equal(target, 'native', 'Native parent layout cannot apply to a portable target');
  assert.equal(fact.kind, 'parent control investigation');
  assert.equal(fact.count, 2, 'This finite counterexample is the two-child startup');
  const bound = parentStartupLayout();
  assert.equal(fact.rootBytes, bound.references + bound.reportedWork + bound.blocks.owner);
  assert.equal(fact.callbackBytes, bound.callbacks);
  assert.equal(fact.childrenContainerBytes, bound.children);
  assert.equal(fact.completedContainerBytes, bound.completed);
  assert.equal(fact.knownOwnedLowerBytes, bound.knownOwnedLower);
  assert.equal(fact.matchedEnvironment, 1, 'Source capture identities were not independently bound');
  assert.equal(fact.environmentBytes, bound.blocks.startEnvironment);
  assert.equal(fact.unclassifiedCaptures, 0);
  assert.equal(fact.unclassifiedRegularBytes, 0);
  assert.equal(fact.embeddedCaptures, 0);
  assert.equal(fact.allowance, 2 * 256);
  return { nativeStartupLower: bound.startupLower, componentAllowance: fact.allowance,
    componentBoundContradicted: bound.startupLower > fact.allowance,
    totalReservationViolationProven: false, completePipelineUpper: false };
}
