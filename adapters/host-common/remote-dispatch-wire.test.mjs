import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';
import {admitRemoteDispatchJson} from './remote-dispatch-wire.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const control = runtimeCore(moon).remoteSiteControl;

const prepared = () => control.prepare(Object.freeze({
  coordinatorAuthority: 'coordinator-a',
  runDefinitionCid: cid('0'),
  taskKey: 'task-a',
  taskAttempt: 1,
  dispatchId: 'dispatch-a',
  siteKey: 'site-a',
  siteGeneration: 1,
  runtimeBundleCid: cid('a'),
  connectorRegistration: 'local',
  connectorRevision: 'local/1',
  strategyRevision: 'strategy/1',
  inputBindingCid: cid('1'),
  obligationsCid: cid('2'),
  budgetCid: cid('3'),
  grantCid: cid('4'),
}));

test('HTTP decoding preserves transport-independent dispatch identity', () => {
  const request = prepared();
  const body = control.requestJson(request);
  const admitted = admitRemoteDispatchJson(
    control,
    body,
    control.identity(request),
  );
  assert.equal(control.identity(admitted), control.identity(request));
  assert.equal(control.requestJson(admitted), body);
});

test('HTTP decoding rejects altered identity and noncanonical JSON', () => {
  const request = prepared();
  const body = control.requestJson(request);
  assert.throws(
    () => admitRemoteDispatchJson(control, body, cid('f')),
    {code: 'InvalidRemoteDispatchWire'},
  );
  assert.throws(
    () => admitRemoteDispatchJson(
      control,
      `${body.slice(0, -1)},"extra":true}`,
      control.identity(request),
    ),
    {code: 'NonCanonicalRemoteDispatchWire'},
  );
  assert.throws(
    () => admitRemoteDispatchJson(
      control,
      body,
      control.identity(request),
      8,
    ),
    {code: 'InvalidRemoteDispatchWire'},
  );
});
