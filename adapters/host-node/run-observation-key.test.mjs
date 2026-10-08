import assert from 'node:assert/strict';
import test from 'node:test';
import * as standard from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as rela from
  '../../_build/js/release/build/connectors_builtin_node_rela/connectors_builtin_node_rela.js';
import {issueInstalledRunObservationKey} from '../host-common/run-state-observation.mjs';

for (const [name, moon] of [['standard', standard], ['RelA', rela]]) {
  test(`${name} observation ABI preserves all optional Boolean states`, () => {
    assert.equal(typeof moon.clientProgramRunObservationKey, 'function');
    for (const [args, expected] of [
      [[false, false, false, false], 'running;7;?;?'],
      [[false, false, true, false], 'running;7;?;0'],
      [[false, false, true, true], 'running;7;?;1'],
      [[true, false, false, false], 'running;7;0;?'],
      [[true, false, true, false], 'running;7;0;0'],
      [[true, false, true, true], 'running;7;0;1'],
      [[true, true, false, false], 'running;7;1;?'],
      [[true, true, true, false], 'running;7;1;0'],
      [[true, true, true, true], 'running;7;1;1'],
      [[false, true, false, true], 'running;7;?;?'],
    ]) assert.equal(moon.clientProgramRunObservationKey('running', 7n, ...args), expected);
  });

  test(`${name} observation ABI retains outcome and revision admission`, () => {
    for (const [outcome, expected] of [
      ['preparing', 'preparing;0;?;?'], ['running', 'running;0;?;?'],
      ['waiting_checkpoint', 'waiting_checkpoint;0;?;?'], ['resuming', 'resuming;0;?;?'],
      ['needs_reconciliation', 'needs_reconciliation;0;?;?'], ['succeeded', 'succeeded;0;?;?'],
      ['failed', 'failed;0;?;?'], ['cancelled', 'cancelled;0;?;?'],
    ]) assert.equal(moon.clientProgramRunObservationKey(outcome, 0n,
      false, false, false, false), expected);
    assert.equal(moon.clientProgramRunObservationKey('running', 9007199254740991n,
      false, false, false, false), 'running;9007199254740991;?;?');
    for (const [outcome, revision] of [
      ['unrecognized', 0n], ['running', -1n], ['running', 9007199254740992n],
    ]) assert.equal(moon.clientProgramRunObservationKey(outcome, revision,
      false, false, false, false), undefined);
  });

  test(`${name} installed Host preserves unknown facts across the real ABI`, () => {
    for (const [cleanupPending, physicalCloseConfirmed, expected] of [
      [undefined, undefined, 'running;7;?;?'],
      [undefined, false, 'running;7;?;?'],
      [false, false, 'running;7;0;?'],
      [true, undefined, 'running;7;1;?'],
      [true, true, 'running;7;1;1'],
      [false, true, 'running;7;0;1'],
    ]) assert.equal(issueInstalledRunObservationKey(moon, {
      outcome: 'running', revision: 7, cleanupPending, physicalCloseConfirmed,
    }), expected);
    assert.equal(issueInstalledRunObservationKey(moon, {
      outcome: 'invalid', revision: 7, cleanupPending: undefined,
      physicalCloseConfirmed: false,
    }), undefined);
  });
}
